import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/api_logger.dart';
import '../../../helper/local_notification_service.dart';
import '../../../helper/secure_storage.dart';
import '../../onboarding/provider/auth_session_provider.dart';
import '../model/savings_plan_models.dart';
import '../model/savings_reminder.dart';
import 'core_savings_plan_service.dart';
import 'savings_reminder_schedule.dart';
import '../../account/provider/account_preferences_provider.dart';

final savingsReminderServiceProvider = Provider<SavingsReminderService>(
  SavingsReminderService.new,
);

/// The signed-in user's stored choice for [planId]; off when none.
final contributionReminderChoiceProvider = FutureProvider.autoDispose
    .family<ContributionReminderChoice, String>((ref, planId) async {
      final userId = ref.watch(
        authSessionProvider.select((session) => session?.userId),
      );
      if (userId == null) return ContributionReminderChoice.off;
      final record = await ref
          .read(secureStorageProvider)
          .readSavingsReminders(userId);
      return record.choices[planId] ?? ContributionReminderChoice.off;
    });

/// Keeps the pending savings reminders in step with Core's plans. Every
/// public call runs on one queue, so overlapping calls never re-add a
/// request another call has just cancelled.
class SavingsReminderService {
  SavingsReminderService(this._ref);

  final Ref _ref;
  Future<void> _tail = Future<void>.value();

  Future<void> sync() => _enqueue(_sync);

  /// Cancels every pending savings reminder, whoever owns it.
  Future<void> cancelAllScheduled() => _enqueue(_cancelAllScheduled);

  Future<void> setContributionChoice(
    String planId,
    ContributionReminderChoice choice,
  ) => _enqueue(() async {
    final userId = _ref.read(authSessionProvider)?.userId;
    if (userId == null) return;
    final storage = _ref.read(secureStorageProvider);
    final record = await storage.readSavingsReminders(userId);
    final choices = {...record.choices};
    if (choice == ContributionReminderChoice.off) {
      choices.remove(planId);
    } else {
      choices[planId] = choice;
    }
    await storage.writeSavingsReminders(
      userId,
      SavingsReminderRecord(
        entries: record.entries,
        choices: choices,
        fundingSpent: record.fundingSpent,
      ),
    );
    await _sync();
  });

  Future<void> _enqueue(Future<void> Function() task) {
    final run = _tail.then((_) => task());
    _tail = run.catchError((Object error) {
      apiLogger.w('Savings reminder sync failed: ${error.runtimeType}');
    });
    return _tail;
  }

  Future<void> _cancelAllScheduled() async {
    final notifications = _ref.read(localNotificationServiceProvider);
    if (notifications == null) return;
    final pending = await notifications.pendingReminders(savingsReminderAction);
    for (final request in pending) {
      await notifications.cancelReminder(request.id);
    }
  }

  Future<void> _sync() async {
    final session = _ref.read(authSessionProvider);
    final notifications = _ref.read(localNotificationServiceProvider);
    if (session == null || notifications == null) return;
    final userId = session.userId;
    await notifications.refreshLocalTimeZone();
    final owner = savingsOwnerTag(userId);

    final pending = await notifications.pendingReminders(savingsReminderAction);
    final mine = <int>{};
    for (final request in pending) {
      if (_ownerOf(request.argument) == owner) {
        mine.add(request.id);
      } else {
        await notifications.cancelReminder(request.id);
      }
    }

    final storage = _ref.read(secureStorageProvider);
    final record = await storage.readSavingsReminders(userId);
    if (!_ref.read(notificationPreferencesProvider).savingsReminders) {
      for (final id in mine) {
        await notifications.cancelReminder(id);
      }
      await storage.writeSavingsReminders(
        userId,
        SavingsReminderRecord(
          entries: const [],
          choices: record.choices,
          fundingSpent: record.fundingSpent,
        ),
      );
      return;
    }

    final plansService = _ref.read(coreSavingsPlanServiceProvider);
    final smartSave = await plansService.getPlans(SavingsProductType.smartSave);
    final fixed = await plansService.getPlans(SavingsProductType.fixed);
    final plans = <SavingsPlan>[];
    for (final reply in [smartSave, fixed]) {
      final groups = reply.data;
      if (!reply.isDone || groups == null) return;
      for (final group in groups) {
        plans.addAll(group.plans);
      }
    }
    // The owner or session may have changed while Core was answering.
    if (_ref.read(authSessionProvider)?.userId != userId) return;

    final now = DateTime.now();
    final planIds = {for (final plan in plans) plan.id};
    final awaitingFunding = {
      for (final plan in plans)
        if (plan.status == SavingsPlanStatus.pendingFunding) plan.id,
    };
    final spent = {...record.fundingSpent};
    for (final entry in record.entries) {
      if (entry.kind == SavingsReminderKind.funding &&
          !entry.dueAt.isAfter(now)) {
        spent.add(entry.planId);
      }
    }
    spent.removeWhere((id) => !awaitingFunding.contains(id));
    final choices = {
      for (final c in record.choices.entries)
        if (planIds.contains(c.key)) c.key: c.value,
    };

    final planned = plannedSavingsReminders(
      plans,
      now: now,
      choices: choices,
      fundingSpent: spent,
    );
    final desired = <int, SavingsReminder>{};
    for (final reminder in planned) {
      desired.putIfAbsent(savingsReminderOsId(owner, reminder), () => reminder);
    }

    for (final id in mine) {
      if (!desired.containsKey(id)) await notifications.cancelReminder(id);
    }
    final entries = <SavingsReminderEntry>[];
    for (final item in desired.entries) {
      final reminder = item.value;
      var scheduled = mine.contains(item.key);
      if (!scheduled) {
        scheduled = await notifications.scheduleReminder(
          id: item.key,
          title: reminder.title,
          body: reminder.body,
          dueAt: reminder.dueAt,
          action: savingsReminderAction,
          argument: SavingsReminderTap.encode(
            reminder.product,
            owner,
            reminder.planId,
          ),
        );
      }
      if (scheduled) {
        entries.add(
          SavingsReminderEntry(
            planId: reminder.planId,
            product: reminder.product,
            kind: reminder.kind,
            dueAt: reminder.dueAt,
            osId: item.key,
          ),
        );
      }
    }
    await storage.writeSavingsReminders(
      userId,
      SavingsReminderRecord(
        entries: entries,
        choices: choices,
        fundingSpent: spent,
      ),
    );
  }

  /// The owner tag in a savings tap argument, `<product>|<owner>|<planId>`.
  static String? _ownerOf(String? argument) {
    final parts = argument?.split('|');
    if (parts == null || parts.length < 3) return null;
    return parts[1];
  }
}
