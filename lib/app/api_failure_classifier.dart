import 'package:dio/dio.dart';

import 'error_reporting.dart';

/// Facts about one API call outcome, gathered by the API layer.
class ApiOutcome {
  const ApiOutcome({
    required this.backend,
    this.statusCode,
    this.dioType,
    this.hasEnvelope = false,
    this.success,
    this.parserFailed = false,
    this.localSessionExpired = false,
    this.sessionExpiryHandled = false,
  });

  final ApiBackend backend;
  final int? statusCode;
  final DioExceptionType? dioType;

  /// The body was a JSON object carrying the expected envelope.
  final bool hasEnvelope;
  final bool? success;
  final bool parserFailed;
  final bool localSessionExpired;
  final bool sessionExpiryHandled;
}

typedef ApiClassification = ({
  ErrorKind kind,
  ErrorOrigin origin,
  String category,
});

ApiClassification _api(ErrorKind kind, String category) =>
    (kind: kind, origin: ErrorOrigin.api, category: category);

/// Classifies an outcome by evaluating the spec table's rows in order.
ApiClassification classifyApiOutcome(ApiOutcome o) {
  final status = o.statusCode;
  final type = o.dioType;
  final failedEnvelope = o.hasEnvelope && o.success == false;

  if (type == DioExceptionType.cancel) {
    return _api(ErrorKind.ignored, 'cancel');
  }
  if (o.localSessionExpired || o.sessionExpiryHandled) {
    return _api(ErrorKind.breadcrumb, 'session_expired');
  }
  if (type == DioExceptionType.connectionError) {
    return _api(ErrorKind.breadcrumb, 'offline');
  }
  if (type == DioExceptionType.connectionTimeout ||
      type == DioExceptionType.sendTimeout ||
      type == DioExceptionType.receiveTimeout) {
    return _api(ErrorKind.nonfatal, 'timeout');
  }
  if (type != null && status == null) {
    return _api(ErrorKind.nonfatal, 'transport');
  }
  if (o.backend == ApiBackend.core && status == 401) {
    return _api(ErrorKind.nonfatal, 'core_401');
  }
  if (status == 429) return _api(ErrorKind.nonfatal, 'rate_429');
  if (status != null && status >= 500) {
    return _api(ErrorKind.nonfatal, 'server_5xx');
  }
  if (status != null && status >= 400) {
    return failedEnvelope
        ? _api(ErrorKind.breadcrumb, 'client_4xx')
        : _api(ErrorKind.nonfatal, 'client_4xx_malformed');
  }
  if (status != null && status >= 200 && status < 300) {
    if (!o.hasEnvelope) return _api(ErrorKind.nonfatal, 'malformed_envelope');
    if (o.success != true) return _api(ErrorKind.breadcrumb, 'success_false');
  }
  if (o.parserFailed) {
    return (
      kind: ErrorKind.nonfatal,
      origin: ErrorOrigin.parser,
      category: 'parser',
    );
  }
  return _api(ErrorKind.breadcrumb, 'ok');
}
