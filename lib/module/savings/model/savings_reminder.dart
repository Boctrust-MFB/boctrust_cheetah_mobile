import 'package:boctrust_savings_loan/app/services.dart';
import 'package:boctrust_savings_loan/helper/notification_payload.dart';
import 'package:boctrust_savings_loan/module/savings/model/savings_plan_models.dart';
import 'package:timezone/timezone.dart' as tz;

enum SavingsReminderKind { contribution, maturity, funding }

enum ContributionReminderChoice {
  off('Off'),
  morningOf('Morning of'),
  eveningBefore('Evening before');

  const ContributionReminderChoice(this.label);
  final String label;
}

/// A reminder the planner wants scheduled.
class SavingsReminder {
  const SavingsReminder({
    required this.planId,
    required this.product,
    required this.kind,
    required this.dueAt,
    required this.title,
    required this.body,
  });

  final String planId;
  final SavingsProductType product;
  final SavingsReminderKind kind;

  /// UTC.
  final DateTime dueAt;
  final String title;
  final String body;
}

/// What is stored for a scheduled reminder: no copy, amounts or names.
class SavingsReminderEntry {
  const SavingsReminderEntry({
    required this.planId,
    required this.product,
    required this.kind,
    required this.dueAt,
    required this.osId,
  });

  final String planId;
  final SavingsProductType product;
  final SavingsReminderKind kind;
  final DateTime dueAt;
  final int osId;

  Map<String, Object?> toJson() => {
    'planId': planId,
    'product': product.name,
    'kind': kind.name,
    'dueAt': dueAt.toUtc().toIso8601String(),
    'osId': osId,
  };

  static SavingsReminderEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final planId = json['planId'];
    final dueAt = json['dueAt'];
    final osId = json['osId'];
    final product = _byName(SavingsProductType.values, json['product']);
    final kind = _byName(SavingsReminderKind.values, json['kind']);
    if (planId is! String || planId.isEmpty) return null;
    if (dueAt is! String || osId is! int) return null;
    if (product == null || kind == null) return null;
    final due = DateTime.tryParse(dueAt);
    if (due == null) return null;
    return SavingsReminderEntry(
      planId: planId,
      product: product,
      kind: kind,
      dueAt: due.toUtc(),
      osId: osId,
    );
  }
}

/// Everything saved between launches for one signed-in user.
class SavingsReminderRecord {
  const SavingsReminderRecord({
    required this.entries,
    required this.choices,
    required this.fundingSpent,
  });

  static const version = 1;
  static const empty = SavingsReminderRecord(
    entries: [],
    choices: {},
    fundingSpent: {},
  );

  final List<SavingsReminderEntry> entries;

  /// Per plan; a plan not listed is off.
  final Map<String, ContributionReminderChoice> choices;

  /// Plans whose one funding reminder has been used.
  final Set<String> fundingSpent;

  Map<String, Object?> toJson() => {
    'version': version,
    'entries': [for (final e in entries) e.toJson()],
    'choices': {for (final c in choices.entries) c.key: c.value.name},
    'fundingSpent': fundingSpent.toList(),
  };

  /// A wrong version or unreadable record is an empty one.
  static SavingsReminderRecord fromJson(Object? json) {
    if (json is! Map || json['version'] != version) return empty;
    final rawEntries = json['entries'];
    final rawChoices = json['choices'];
    final rawSpent = json['fundingSpent'];
    final entries = <SavingsReminderEntry>[];
    if (rawEntries is List) {
      for (final raw in rawEntries) {
        final entry = SavingsReminderEntry.fromJson(raw);
        if (entry != null) entries.add(entry);
      }
    }
    final choices = <String, ContributionReminderChoice>{};
    if (rawChoices is Map) {
      for (final c in rawChoices.entries) {
        final choice = _byName(ContributionReminderChoice.values, c.value);
        if (c.key is String && choice != null) {
          choices[c.key as String] = choice;
        }
      }
    }
    final spent = <String>{};
    if (rawSpent is List) {
      for (final id in rawSpent) {
        if (id is String) spent.add(id);
      }
    }
    return SavingsReminderRecord(
      entries: entries,
      choices: choices,
      fundingSpent: spent,
    );
  }
}

T? _byName<T extends Enum>(List<T> values, Object? name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

/// A short, stable tag for the signed-in user. Never the user id itself.
String savingsOwnerTag(String userId) => NotificationPayload.stableId(
  '${Env.secureStorageNamespace}:$userId',
).toRadixString(16);

/// The OS notification id: stable for one plan, kind and local due day.
int savingsReminderOsId(String ownerTag, SavingsReminder r) {
  final local = tz.TZDateTime.from(r.dueAt, tz.local);
  final day =
      '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
  return NotificationPayload.stableId(
    'savings:$ownerTag:${r.planId}:${r.kind.name}:$day',
  );
}

/// The tap argument carried by a savings reminder.
class SavingsReminderTap {
  const SavingsReminderTap({required this.planId, required this.product});

  final String planId;
  final SavingsProductType product;

  static String encode(
    SavingsProductType product,
    String ownerTag,
    String planId,
  ) => '${product.name}|$ownerTag|$planId';
}

/// The notification action carried by every savings reminder.
const savingsReminderAction = 'savings.reminder';
