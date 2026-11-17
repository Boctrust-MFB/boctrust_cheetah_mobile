import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef NotificationActionRun = Future<void> Function(String? argument);

/// What a local-notification tap runs for a given `action`.
class NotificationActionHandler {
  const NotificationActionHandler({
    required this.run,
    this.requiresSession = true,
  });

  final NotificationActionRun run;

  /// Whether the tap waits for an authenticated session before running.
  final bool requiresSession;
}

/// The single registration point for notification actions, keyed by the
/// payload `action`, like the route table.
final notificationActionHandlersProvider =
    Provider<Map<String, NotificationActionHandler>>((ref) => const {});
