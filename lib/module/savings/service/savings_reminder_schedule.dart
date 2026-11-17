import 'package:boctrust_savings_loan/module/savings/model/savings_plan_models.dart';
import 'package:boctrust_savings_loan/module/savings/model/savings_reminder.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

const _maxRequests = 48;
const _fundingWindow = Duration(days: 7);

/// The reminders to have scheduled, nearest first within priority, at most
/// 48. Maturity and funding come before contributions.
List<SavingsReminder> plannedSavingsReminders(
  List<SavingsPlan> plans, {
  required DateTime now,
  required Map<String, ContributionReminderChoice> choices,
  required Set<String> fundingSpent,
}) {
  final nowUtc = now.toUtc();
  final today = _localDate(now);
  final important = <SavingsReminder>[];
  final contributions = <SavingsReminder>[];

  for (final plan in plans) {
    if (!_hasReminderCopy(plan.type)) continue;

    if (plan.status == SavingsPlanStatus.active) {
      final maturity = plan.maturityDate;
      if (maturity != null) {
        final day = _localDate(maturity);
        final due = tz.TZDateTime(
          tz.local,
          day.year,
          day.month,
          day.day - 3,
          9,
        );
        if (due.isAfter(nowUtc)) {
          important.add(
            SavingsReminder(
              planId: plan.id,
              product: plan.type,
              kind: SavingsReminderKind.maturity,
              dueAt: due.toUtc(),
              title: 'Plan maturing soon',
              body:
                  'Your ${_productName(plan.type)} matures in 3 days, on '
                  '${DateFormat('d MMM').format(day)}. '
                  'Tap to view your plan.',
            ),
          );
        }
      }
    }

    if (plan.status == SavingsPlanStatus.pendingFunding) {
      final created = plan.createdAt;
      if (created != null && !fundingSpent.contains(plan.id)) {
        final earliest = _later(
          created.toUtc().add(const Duration(hours: 24)),
          nowUtc,
        );
        final local = tz.TZDateTime.from(earliest, tz.local);
        var due = tz.TZDateTime(
          tz.local,
          local.year,
          local.month,
          local.day,
          9,
        );
        if (due.isBefore(local)) {
          due = tz.TZDateTime(
            tz.local,
            local.year,
            local.month,
            local.day + 1,
            9,
          );
        }
        if (due.toUtc().isBefore(created.toUtc().add(_fundingWindow))) {
          important.add(
            SavingsReminder(
              planId: plan.id,
              product: plan.type,
              kind: SavingsReminderKind.funding,
              dueAt: due.toUtc(),
              title: 'Fund your new plan',
              body:
                  'Your new ${_productName(plan.type)} plan is waiting for '
                  'its first deposit. Tap to add money.',
            ),
          );
        }
      }
    }

    if (plan.status == SavingsPlanStatus.active &&
        plan.type == SavingsProductType.smartSave) {
      final choice = choices[plan.id] ?? ContributionReminderChoice.off;
      final frequency = plan.saveFrequency;
      if (choice == ContributionReminderChoice.off || frequency == null) {
        continue;
      }
      final count = switch (frequency) {
        SavingsFrequency.daily => 7,
        SavingsFrequency.weekly => 4,
        SavingsFrequency.monthly => 2,
      };
      final evening = choice == ContributionReminderChoice.eveningBefore;
      for (final date in contributionDates(plan, today: today, count: count)) {
        final due = evening
            ? tz.TZDateTime(tz.local, date.year, date.month, date.day - 1, 18)
            : tz.TZDateTime(tz.local, date.year, date.month, date.day, 8);
        if (!due.isAfter(nowUtc)) continue;
        contributions.add(
          SavingsReminder(
            planId: plan.id,
            product: plan.type,
            kind: SavingsReminderKind.contribution,
            dueAt: due.toUtc(),
            title: 'SmartSave reminder',
            body:
                'Your ${frequency.label.toLowerCase()} SmartSave auto-save is '
                'scheduled for ${evening ? 'tomorrow' : 'today'}. '
                'Tap to view your plan.',
          ),
        );
      }
    }
  }

  int byDue(SavingsReminder a, SavingsReminder b) => a.dueAt.compareTo(b.dueAt);
  important.sort(byDue);
  contributions.sort(byDue);
  return [...important, ...contributions].take(_maxRequests).toList();
}

/// Upcoming local calendar dates (date only) of a SmartSave auto-save,
/// strictly after [today] and before the maturity date. Empty when the plan
/// lacks a start date, frequency or recurring amount.
List<DateTime> contributionDates(
  SavingsPlan plan, {
  required DateTime today,
  required int count,
}) {
  final start = plan.startDate;
  final frequency = plan.saveFrequency;
  final amount = plan.recurringAmount;
  if (start == null || frequency == null || amount == null || count <= 0) {
    return const [];
  }
  final first = _localDate(start);
  final after = DateTime(today.year, today.month, today.day);
  final maturity = plan.maturityDate == null
      ? null
      : _localDate(plan.maturityDate!);

  final dates = <DateTime>[];
  // Bounded: at most count dates, and the start is never far in the past.
  var index = 0;
  while (dates.length < count && index < 100000) {
    final date = switch (frequency) {
      SavingsFrequency.daily => DateTime(
        first.year,
        first.month,
        first.day + index,
      ),
      SavingsFrequency.weekly => DateTime(
        first.year,
        first.month,
        first.day + 7 * index,
      ),
      SavingsFrequency.monthly => _monthlyDate(first, index),
    };
    index++;
    if (maturity != null && !date.isBefore(maturity)) break;
    if (date.isAfter(after)) dates.add(date);
  }
  return dates;
}

DateTime _monthlyDate(DateTime first, int monthsAhead) {
  final month = first.month + monthsAhead;
  final year = first.year + (month - 1) ~/ 12;
  final m = (month - 1) % 12 + 1;
  final lastDay = DateTime(year, m + 1, 0).day;
  return DateTime(year, m, first.day > lastDay ? lastDay : first.day);
}

DateTime _localDate(DateTime value) {
  final local = tz.TZDateTime.from(value.toUtc(), tz.local);
  return DateTime(local.year, local.month, local.day);
}

DateTime _later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

bool _hasReminderCopy(SavingsProductType type) =>
    type == SavingsProductType.smartSave || type == SavingsProductType.fixed;

String _productName(SavingsProductType type) =>
    type == SavingsProductType.smartSave ? 'SmartSave' : 'Fixed Deposit';
