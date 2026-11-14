import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ErrorOrigin { flutter, platform, api, parser, routing, upload }

enum ErrorKind { nonfatal, breadcrumb, ignored }

enum ApiBackend { user, core, storage }

/// Constant label attached to an API call so failures group by feature.
class ApiCallLabel {
  const ApiCallLabel({
    required this.feature,
    required this.action,
    required this.stage,
    required this.endpoint,
  });

  static const unlabeled = ApiCallLabel(
    feature: 'unknown_feature',
    action: 'unknown_action',
    stage: 'unknown_stage',
    endpoint: 'endpoint_unclassified',
  );

  final String feature;
  final String action;
  final String stage;
  final String endpoint;

  @override
  bool operator ==(Object other) =>
      other is ApiCallLabel &&
      other.feature == feature &&
      other.action == action &&
      other.stage == stage &&
      other.endpoint == endpoint;

  @override
  int get hashCode => Object.hash(feature, action, stage, endpoint);
}

/// Dio extras key under which an [ApiCallLabel] travels with a request.
const apiCallLabelKey = 'telemetry.apiCallLabel';

/// Safe, payload-free description of a failed API call.
class ApiFailure implements Exception {
  const ApiFailure(this.description);

  final String description;

  @override
  String toString() => description;
}

/// Safe summary of an API error body. Plain data; produced by the API layer.
class ApiErrorSummary {
  const ApiErrorSummary({
    this.code,
    required this.message,
    this.fields = const [],
    this.requestId,
  });

  final String? code;
  final String message;
  final List<String> fields;
  final String? requestId;
}

class ErrorEvent {
  const ErrorEvent({
    required this.kind,
    required this.origin,
    required this.reason,
    this.label = ApiCallLabel.unlabeled,
    this.backend,
    this.method,
    this.category,
    this.statusCode,
    this.summary,
    this.route,
    this.requestedRoute,
    this.error,
    this.stack,
    this.throttled = false,
  });

  final ErrorKind kind;
  final ErrorOrigin origin;
  final String reason;
  final ApiCallLabel label;
  final ApiBackend? backend;
  final String? method;
  final String? category;
  final int? statusCode;
  final ApiErrorSummary? summary;
  final String? route;
  final String? requestedRoute;
  final Object? error;
  final StackTrace? stack;
  final bool throttled;

  ErrorEvent copyWith({String? route, bool? throttled}) => ErrorEvent(
    kind: kind,
    origin: origin,
    reason: reason,
    label: label,
    backend: backend,
    method: method,
    category: category,
    statusCode: statusCode,
    summary: summary,
    route: route ?? this.route,
    requestedRoute: requestedRoute,
    error: error,
    stack: stack,
    throttled: throttled ?? this.throttled,
  );

  String get groupKey => [
    backend?.name ?? '',
    method ?? '',
    label.endpoint,
    category ?? '',
    summary?.code ?? '',
    label.action,
  ].join('|');

  bool get _hasApiLabel =>
      origin == ErrorOrigin.api ||
      origin == ErrorOrigin.parser ||
      origin == ErrorOrigin.upload;

  /// One bounded, space-separated line for Crashlytics logs.
  String get breadcrumb {
    final parts = <String?>[
      origin.name,
      if (throttled) 'suppressed',
      reason,
      backend?.name,
      method,
      if (_hasApiLabel) label.endpoint,
      if (_hasApiLabel) label.action,
      statusCode?.toString(),
      category,
      summary?.code,
      if (route != null) 'route=$route',
      if (requestedRoute != null) 'requested_route=$requestedRoute',
    ];
    final line = parts.whereType<String>().where((p) => p.isNotEmpty).join(' ');
    return line.length <= 200 ? line : line.substring(0, 200);
  }

  List<String> get information {
    final lines = <String>[];
    void add(String key, Object? value) {
      final text = value?.toString() ?? '';
      if (text.isNotEmpty) lines.add('$key=$text');
    }

    add('origin', origin.name);
    add('backend', backend?.name);
    add('method', method);
    if (_hasApiLabel) {
      add('endpoint', label.endpoint);
      add('feature', label.feature);
      add('action', label.action);
      add('stage', label.stage);
    }
    add('status', statusCode);
    add('category', category);
    add('code', summary?.code);
    add('message', summary?.message);
    add('fields', summary?.fields.join(','));
    add('request_id', summary?.requestId);
    add('route', route);
    add('requested_route', requestedRoute);
    return lines;
  }
}

/// Fire-and-forget; implementations never throw.
abstract interface class AppErrorReporter {
  void report(ErrorEvent event);

  void recordUncaught(
    Object error,
    StackTrace stack, {
    required ErrorOrigin origin,
    FlutterErrorDetails? details,
  });

  void breadcrumb(String line);
}

class NoopErrorReporter implements AppErrorReporter {
  const NoopErrorReporter();

  @override
  void report(ErrorEvent event) {}

  @override
  void recordUncaught(
    Object error,
    StackTrace stack, {
    required ErrorOrigin origin,
    FlutterErrorDetails? details,
  }) {}

  @override
  void breadcrumb(String line) {}
}

class ReportingContext {
  String? lastRoute;
}

final reportingContext = ReportingContext();

/// Allows one report per group key per window and a limited number per session.
class ReportThrottle {
  ReportThrottle({
    DateTime Function()? now,
    this.perSessionLimit = 4,
    this.window = const Duration(minutes: 10),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final int perSessionLimit;
  final Duration window;
  final Map<String, DateTime> _last = {};
  int _allowed = 0;

  bool allow(String groupKey) {
    final now = _now();
    final last = _last[groupKey];
    if (last != null && now.difference(last) < window) return false;
    if (_allowed >= perSessionLimit) return false;
    _last[groupKey] = now;
    _allowed++;
    return true;
  }
}

final errorReporterProvider = Provider<AppErrorReporter>(
  (ref) => const NoopErrorReporter(),
);
