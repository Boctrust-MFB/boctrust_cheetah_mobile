import '../app/app_router.dart';
import '../app/error_reporting.dart';
import '../app/navigators.dart';
import '../app/route_arguments.dart';
import '../module/app_flow/app_ui.dart';
import 'notification_payload.dart';

class NotificationIntent {
  const NotificationIntent({required this.routeName, this.entityId});
  final String routeName;
  final String? entityId;
}

class NotificationNavigator {
  const NotificationNavigator._();

  static NotificationIntent parse(Map<String, dynamic> payload) {
    final route = _bounded(payload['route']);
    if (route == null || !AppRoutes.allRoutes.contains(route)) {
      if (route != null) _reportUnknownRoute(route);
      return const NotificationIntent(routeName: AppRoutes.notifications);
    }
    return NotificationIntent(
      routeName: route,
      entityId: _bounded(payload['id']),
    );
  }

  /// Navigation falls back to notifications, so the router never sees the
  /// unknown name; report it here instead (once per parse).
  static void _reportUnknownRoute(String route) {
    try {
      AppRouter.reporter.report(
        ErrorEvent(
          kind: ErrorKind.nonfatal,
          origin: ErrorOrigin.routing,
          reason: 'unknown_route',
          requestedRoute: safeRouteName(route),
          error: const UnknownRouteError(),
          stack: StackTrace.current,
        ),
      );
    } catch (_) {}
  }

  static String? _bounded(Object? value) =>
      value is String && value.length <= NotificationPayload.maxFieldLength
      ? value
      : null;

  static Future<void> dispatch(Map<String, dynamic> payload) async {
    final intent = parse(payload);
    // A hub is a tab of the shell when the shell is on top. Over other
    // pages it opens above them, so a flow in progress is not discarded.
    final section = sectionForRoute(intent.routeName);
    if (section != null && selectOpenSection(section, dropPages: false)) {
      return;
    }
    await pushTo(
      intent.routeName,
      arguments: AppRouteArguments(entityId: intent.entityId),
    );
  }
}
