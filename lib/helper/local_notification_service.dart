import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../app/api_logger.dart';
import 'notification_payload.dart';

/// The app's notification service, created in `main()`. Null when the app
/// runs without one (tests, or a platform without local notifications).
final localNotificationServiceProvider = Provider<LocalNotificationService?>(
  (ref) => null,
);

/// Local-notification taps received while the app is running.
final localNotificationTapProvider = StreamProvider<Map<String, String>>(
  (ref) =>
      ref.watch(localNotificationServiceProvider)?.taps ??
      const Stream<Map<String, String>>.empty(),
);

/// The single boundary that displays remote messages as local notifications
/// and reports local-notification taps.
class LocalNotificationService {
  LocalNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    void Function(String message)? log,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _log = log ?? apiLogger.w;

  /// Android small icon: the white Cheetah silhouette drawable.
  static const androidSmallIcon = 'ic_stat_boctrust';
  static const channelId = 'boctrust_general';
  // The id stays so existing notification settings carry over.
  static const channelName = 'Cheetah notifications';
  static const remindersChannelId = 'boctrust_reminders';
  static const remindersChannelName = 'Reminders';
  static const _fallbackTimeZone = 'Africa/Lagos';

  final FlutterLocalNotificationsPlugin _plugin;
  final void Function(String message) _log;
  final _taps = StreamController<Map<String, String>>.broadcast();
  Future<bool>? _initialized;
  bool _launchConsumed = false;
  bool _zonesLoaded = false;

  /// Normalized `route`/`id` payloads of notifications tapped while the app
  /// is running.
  Stream<Map<String, String>> get taps => _taps.stream;

  /// Initializes the plugin and channel once. Returns false, without
  /// throwing, when the platform is unavailable; a later call retries.
  Future<bool> initialize() => _initialized ??= _initialize().then((ready) {
    if (!ready) _initialized = null;
    return ready;
  });

  Future<bool> _initialize() async {
    try {
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings(androidSmallIcon),
          iOS: darwin,
          macOS: darwin,
        ),
        onDidReceiveNotificationResponse: _onResponse,
      );
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          channelId,
          channelName,
          importance: Importance.high,
        ),
      );
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          remindersChannelId,
          remindersChannelName,
          importance: Importance.defaultImportance,
        ),
      );
      return true;
    } catch (error) {
      _log('Local notifications unavailable: ${error.runtimeType}');
      return false;
    }
  }

  /// Points `tz.local` at the device's current zone, or Africa/Lagos when it
  /// cannot be read. Loads the time-zone database on first use.
  Future<void> _setLocalTimeZone() async {
    if (!_zonesLoaded) {
      tzdata.initializeTimeZones();
      _zonesLoaded = true;
    }
    var name = _fallbackTimeZone;
    try {
      name = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(name));
    } catch (error) {
      _log('Device time zone unavailable: ${error.runtimeType}');
      tz.setLocalLocation(tz.getLocation(_fallbackTimeZone));
    }
  }

  /// Re-reads the device time zone so reminders are scheduled in local time.
  /// Safe to call repeatedly; never throws.
  Future<void> refreshLocalTimeZone() async {
    try {
      if (!await initialize()) return;
      await _setLocalTimeZone();
    } catch (error) {
      _log('Time zone refresh failed: ${error.runtimeType}');
    }
  }

  /// Schedules a one-off reminder at [dueAt] on the reminders channel. The tap
  /// payload carries [action] and [argument]. Returns false, without
  /// throwing, when [dueAt] is not in the future, notifications are disabled
  /// or scheduling fails.
  Future<bool> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime dueAt,
    required String action,
    required String argument,
  }) async {
    if (!dueAt.isAfter(DateTime.now())) return false;
    if (!await initialize() || !await notificationsEnabled()) return false;
    try {
      if (!_zonesLoaded) await _setLocalTimeZone();
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(dueAt, tz.local),
        _reminderDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: NotificationPayload.localPayload(action: action, id: argument),
      );
      return true;
    } catch (error) {
      _log('Reminder $id not scheduled: ${error.runtimeType}');
      return false;
    }
  }

  /// Pending reminders whose payload action equals [action]. Null when the
  /// platform cannot be read, so callers can tell failure from "none".
  Future<List<({int id, String? argument})>?> pendingReminders(
    String action,
  ) async {
    if (!await initialize()) return null;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      return [
        for (final request in pending)
          if (NotificationPayload.decodeLocalPayload(
                request.payload,
              )?['action'] ==
              action)
            (
              id: request.id,
              argument: NotificationPayload.decodeLocalPayload(
                request.payload,
              )?['id'],
            ),
      ];
    } catch (error) {
      _log('Pending reminders unavailable: ${error.runtimeType}');
      return null;
    }
  }

  Future<void> cancelReminder(int id) async {
    if (!await initialize()) return;
    try {
      await _plugin.cancel(id);
    } catch (error) {
      _log('Reminder $id not cancelled: ${error.runtimeType}');
    }
  }

  void _onResponse(NotificationResponse response) {
    final payload = NotificationPayload.decodeLocalPayload(response.payload);
    if (payload != null) _taps.add(payload);
  }

  /// Shows [message] with generic copy. Messages with nothing to display are
  /// skipped; failures are logged without message content and never thrown.
  Future<void> showRemoteMessage(RemoteMessage message) async {
    final payload = NotificationPayload.fromRemoteMessage(message);
    if (!payload.isDisplayable || !await initialize()) return;
    try {
      await _plugin.show(
        payload.notificationId,
        NotificationPayload.title,
        NotificationPayload.body,
        _details,
        payload: payload.toLocalPayload(),
      );
    } catch (error) {
      _log(
        'Local notification ${payload.notificationId} not shown: '
        '${error.runtimeType}',
      );
    }
  }

  /// Whether the OS currently lets the app show notifications. Never asks
  /// for permission; null or failing platform checks count as disabled.
  Future<bool> notificationsEnabled() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.areNotificationsEnabled() ?? false;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return (await ios.checkPermissions())?.isEnabled ?? false;
      }
      return false;
    } catch (error) {
      _log('Notification permission check failed: ${error.runtimeType}');
      return false;
    }
  }

  /// Shows a notification the app itself raised, such as a saved file, on
  /// the app's channel. With [key] the id is stable, so a later post with the
  /// same key replaces the earlier one; without it the id is time-based.
  /// [action] and [argument] are carried in the tap payload. Failures are
  /// logged without content and never thrown; returns true only when
  /// notifications are enabled and the notification was handed to the
  /// platform.
  Future<bool> showAppNotification({
    required String title,
    required String body,
    String? key,
    String? action,
    String? argument,
  }) async {
    if (!await initialize() || !await notificationsEnabled()) return false;
    final id = key != null
        ? NotificationPayload.stableId(key)
        : NotificationPayload.stableId(
            '$title:${DateTime.now().microsecondsSinceEpoch}',
          );
    try {
      await _plugin.show(
        id,
        title,
        body,
        _details,
        payload: NotificationPayload.localPayload(id: argument, action: action),
      );
      return true;
    } catch (error) {
      _log('Local notification $id not shown: ${error.runtimeType}');
      return false;
    }
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.high,
      priority: Priority.high,
      icon: androidSmallIcon,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
    ),
  );

  static const _reminderDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      remindersChannelId,
      remindersChannelName,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: androidSmallIcon,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
    ),
  );

  /// The payload of the notification that launched the app, returned at most
  /// once per process: the plugin keeps reporting the same launch, which
  /// would otherwise replay on rebuilds.
  Future<Map<String, String>?> getInitialTapPayload() async {
    if (_launchConsumed) return null;
    _launchConsumed = true;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return null;
      return NotificationPayload.decodeLocalPayload(
        details.notificationResponse?.payload,
      );
    } catch (error) {
      _log('Notification launch details unavailable: ${error.runtimeType}');
      return null;
    }
  }
}
