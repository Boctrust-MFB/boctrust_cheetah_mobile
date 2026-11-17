import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/preferences.dart';
import 'local_notification_service.dart';

/// Remembers which once-only notifications were already posted.
class NotificationOnceLedger {
  NotificationOnceLedger(this._prefs);

  final SharedPreferences _prefs;

  static String _prefsKey(String key) => 'notification_once.$key';

  bool hasPosted(String key) => _prefs.getBool(_prefsKey(key)) ?? false;

  Future<void> markPosted(String key) async {
    await _prefs.setBool(_prefsKey(key), true);
  }
}

final notificationOnceLedgerProvider = Provider<NotificationOnceLedger>(
  (ref) => NotificationOnceLedger(ref.watch(sharedPreferencesProvider)),
);

/// Posts at most once per [onceKey]: skipped when already posted, and marked
/// posted only when the notification was actually shown.
Future<bool> postOnce(
  LocalNotificationService service,
  NotificationOnceLedger ledger, {
  required String onceKey,
  required String title,
  required String body,
  String? key,
  String? action,
  String? argument,
}) async {
  if (ledger.hasPosted(onceKey)) return false;
  final posted = await service.showAppNotification(
    title: title,
    body: body,
    key: key,
    action: action,
    argument: argument,
  );
  if (posted) await ledger.markPosted(onceKey);
  return posted;
}
