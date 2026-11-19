import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../helper/secure_storage.dart';
import '../module/onboarding/provider/auth_session_provider.dart';
import 'api_error_summary.dart';
import 'api_failure_classifier.dart';
import 'api_logger.dart';
import 'error_reporting.dart';
import 'interceptors.dart';
import 'services.dart';
import 'session_expiry_coordinator.dart';

typedef ApiDataParser<T> = T Function(Object? data);

/// A mapped reply, the facts used to classify it, and the parser's stack
/// when the parser rejected the data.
typedef _Mapped<T> = ({
  ServiceResponse<T> response,
  ApiOutcome outcome,
  StackTrace? parserStack,
});

/// The Dio shared by the User and Core transports: JSON headers, 30 second
/// timeouts, and the [auth] interceptor followed by logging and activity.
Dio buildApiDio(String baseUrl, AuthInterceptor auth) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );
  dio.interceptors.addAll([
    auth,
    LoggingInterceptor(
      includeSensitiveData: Env.logsSensitiveData,
      releaseLogPolicy: Env.releaseLogPolicy,
    ),
    ActivityInterceptor(),
  ]);
  return dio;
}

final dioProvider = Provider<Dio>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return buildApiDio(
    baseUrl(),
    AuthInterceptor(
      readAccessToken: storage.readAccessToken,
      readCurrentSession: () => ref.read(authSessionProvider),
      expireSessionOnce: () =>
          ref.read(sessionExpiryCoordinatorProvider).expireOnce(),
    ),
  );
});

final apiServiceProvider = Provider<ApiService>(
  (ref) => ApiService(
    ref.watch(dioProvider),
    reporter: ref.watch(errorReporterProvider),
  ),
);

class ApiService {
  const ApiService(
    this._dio, {
    this._backend = ApiBackend.user,
    this._reporter = const NoopErrorReporter(),
  });

  final Dio _dio;
  final ApiBackend _backend;
  final AppErrorReporter _reporter;

  /// [cancelToken] abandons a request whose answer is no longer wanted,
  /// such as a recipient lookup for a number the customer has since changed.
  /// [receiveTimeout] replaces the 30 second default for a reply Core is
  /// known to take longer to produce.
  Future<ServiceResponse<T>> getData<T>(
    String path, {
    required ApiDataParser<T> parser,
    Map<String, dynamic>? queryParameters,
    Map<String, Object?>? requestExtra,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) => _request(
    () => _dio.get<Object?>(
      path,
      queryParameters: queryParameters,
      options: Options(extra: requestExtra, receiveTimeout: receiveTimeout),
      cancelToken: cancelToken,
    ),
    parser,
    method: 'GET',
    requestExtra: requestExtra,
    // Captured before any await so each service operation groups apart.
    callStack: StackTrace.current,
  );

  Future<ServiceResponse<T>> postData<T>(
    String path, {
    Object? data,
    required ApiDataParser<T> parser,
    Map<String, Object?>? requestExtra,
    CancelToken? cancelToken,
  }) => _request(
    () => _dio.post<Object?>(
      path,
      data: data,
      options: Options(extra: requestExtra),
      cancelToken: cancelToken,
    ),
    parser,
    method: 'POST',
    requestExtra: requestExtra,
    // Captured before any await so each service operation groups apart.
    callStack: StackTrace.current,
  );

  Future<ServiceResponse<T>> patchData<T>(
    String path, {
    Object? data,
    required ApiDataParser<T> parser,
    Map<String, Object?>? requestExtra,
  }) => _request(
    () => _dio.patch<Object?>(
      path,
      data: data,
      options: Options(extra: requestExtra),
    ),
    parser,
    method: 'PATCH',
    requestExtra: requestExtra,
    // Captured before any await so each service operation groups apart.
    callStack: StackTrace.current,
  );

  Future<ServiceResponse<T>> deleteData<T>(
    String path, {
    Object? data,
    required ApiDataParser<T> parser,
    Map<String, Object?>? requestExtra,
  }) => _request(
    () => _dio.delete<Object?>(
      path,
      data: data,
      options: Options(extra: requestExtra),
    ),
    parser,
    method: 'DELETE',
    requestExtra: requestExtra,
    // Captured before any await so each service operation groups apart.
    callStack: StackTrace.current,
  );

  Future<ServiceResponse<T>> _request<T>(
    Future<Response<Object?>> Function() call,
    ApiDataParser<T> parser, {
    required String method,
    required Map<String, Object?>? requestExtra,
    required StackTrace callStack,
  }) async {
    _Mapped<T> mapped;
    try {
      mapped = _mapResponse(await call(), parser);
    } on DioException catch (error) {
      mapped = _mapDioException(error, parser);
    } catch (_) {
      mapped = (
        response: const ServiceResponse.error(
          'The server response was invalid.',
        ),
        outcome: ApiOutcome(backend: _backend, parserFailed: true),
        parserStack: null,
      );
    }
    _report(mapped, method, requestExtra, callStack);
    return mapped.response;
  }

  /// Reports a failed request once. Never throws and never changes the reply.
  void _report<T>(
    _Mapped<T> mapped,
    String method,
    Map<String, Object?>? requestExtra,
    StackTrace callStack,
  ) {
    try {
      final (:kind, :origin, :category) = classifyApiOutcome(mapped.outcome);
      if (kind == ErrorKind.ignored || category == 'ok') return;
      final value = requestExtra?[apiCallLabelKey];
      final label = value is ApiCallLabel ? value : ApiCallLabel.unlabeled;
      _reporter.report(
        ErrorEvent(
          kind: kind,
          origin: origin,
          reason: category,
          label: label,
          backend: _backend,
          method: method,
          category: category,
          statusCode: mapped.outcome.statusCode,
          summary: summarizeApiError(mapped.response, headerRequestId: null),
          // The endpoint comes from the label only, never the request path.
          error: ApiFailure(
            '${_backend.name} $method ${label.endpoint} $category',
          ),
          stack: mapped.parserStack ?? callStack,
        ),
      );
    } catch (_) {}
  }

  _Mapped<T> _mapResponse<T>(
    Response<Object?> response,
    ApiDataParser<T> parser,
  ) {
    final statusCode = response.statusCode;
    final body = response.data;
    if (body is! Map) {
      return (
        response: ServiceResponse<T>.error(
          'The server response was invalid.',
          statusCode: statusCode,
        ),
        outcome: ApiOutcome(backend: _backend, statusCode: statusCode),
        parserStack: null,
      );
    }
    final json = Map<String, Object?>.from(body);
    final message = json['message'] as String?;
    final meta = ApiMeta.fromJson(json['meta']);
    if (json['success'] != true) {
      return (
        response: ServiceResponse<T>(
          status: ServiceStatus.error,
          data: _conflictData(statusCode, json, parser),
          message: message ?? 'Request failed.',
          statusCode: statusCode,
          errorCode: json['code'] as String?,
          errors: _errors(json['errors']),
          meta: meta,
        ),
        outcome: _envelopeOutcome(statusCode, json),
        parserStack: null,
      );
    }

    try {
      return (
        response: ServiceResponse<T>.success(
          parser(json['data']),
          message: message,
          statusCode: statusCode,
          meta: meta,
        ),
        outcome: _envelopeOutcome(statusCode, json),
        parserStack: null,
      );
    } catch (error, stack) {
      // Staging reads this beside the logged RESPONSE body to fit a model to
      // a reply whose schema is unpublished. Parser messages carry no data.
      if (Env.isStaging) {
        apiLogger.w({
          'event': 'PARSE_ERROR',
          'url': response.requestOptions.uri.toString().split('?').first,
          'model': '$T',
          'error': error is FormatException
              ? error.message
              : error.runtimeType.toString(),
        });
      }
      return (
        response: ServiceResponse<T>.error(
          'The server response was invalid.',
          statusCode: statusCode,
          meta: meta,
        ),
        outcome: ApiOutcome(
          backend: _backend,
          statusCode: statusCode,
          hasEnvelope: true,
          success: true,
          parserFailed: true,
        ),
        parserStack: stack,
      );
    }
  }

  _Mapped<T> _mapDioException<T>(DioException error, ApiDataParser<T> parser) {
    final statusCode = error.response?.statusCode;
    final noAuth = error.requestOptions.extra['sessionExpiryHandled'] == true;
    if (error.error is LocalSessionExpired) {
      return (
        response: ServiceResponse<T>.error(
          'Your session has expired. Please sign in again.',
          statusCode: 401,
          errorCode: kLocalSessionExpiredCode,
          noAuth: noAuth,
        ),
        // Not a cancel for reporting: classified as session expiry.
        outcome: ApiOutcome(
          backend: _backend,
          statusCode: 401,
          localSessionExpired: true,
          sessionExpiryHandled: noAuth,
        ),
        parserStack: null,
      );
    }

    final body = error.response?.data;
    if (body is Map) {
      final json = Map<String, Object?>.from(body);
      return (
        response: ServiceResponse<T>(
          status: ServiceStatus.error,
          data: _conflictData(statusCode, json, parser),
          message: json['message'] as String? ?? 'Request failed.',
          statusCode: statusCode,
          errorCode: json['code'] as String?,
          errors: _errors(json['errors']),
          meta: ApiMeta.fromJson(json['meta']),
          noAuth: noAuth,
        ),
        outcome: _envelopeOutcome(
          statusCode,
          json,
          dioType: error.type,
          sessionExpiryHandled: noAuth,
        ),
        parserStack: null,
      );
    }

    return (
      response: ServiceResponse<T>.error(
        _transportMessage(error),
        statusCode: statusCode,
        noAuth: noAuth,
      ),
      outcome: ApiOutcome(
        backend: _backend,
        statusCode: statusCode,
        dioType: error.type,
        sessionExpiryHandled: noAuth,
      ),
      parserStack: null,
    );
  }

  /// A JSON object body is an envelope when it carries `success`; as in
  /// [_mapResponse], anything but `true` counts as a failed reply.
  ApiOutcome _envelopeOutcome(
    int? statusCode,
    Map<String, Object?> json, {
    DioExceptionType? dioType,
    bool sessionExpiryHandled = false,
  }) => ApiOutcome(
    backend: _backend,
    statusCode: statusCode,
    dioType: dioType,
    hasEnvelope: json.containsKey('success'),
    success: json['success'] == true,
    sessionExpiryHandled: sessionExpiryHandled,
  );

  /// A 409 may return the resource already in the way (for KYC, the
  /// verification in progress) so the caller can reopen it. Any other error's
  /// data, or conflict data that does not parse, is dropped.
  static T? _conflictData<T>(
    int? statusCode,
    Map<String, Object?> json,
    ApiDataParser<T> parser,
  ) {
    if (statusCode != 409 || json['data'] == null) return null;
    try {
      return parser(json['data']);
    } catch (_) {
      return null;
    }
  }

  static List<Object?> _errors(Object? value) {
    if (value == null) return const [];
    if (value is List) return List<Object?>.unmodifiable(value);
    if (value is Map) {
      return [Map<String, Object?>.unmodifiable(Map.from(value))];
    }
    return [value];
  }

  static String _transportMessage(DioException error) => switch (error.type) {
    DioExceptionType.connectionError =>
      'No internet connection. Please try again.',
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => 'Request timed out. Please try again.',
    DioExceptionType.cancel => 'Request was cancelled.',
    _ => error.message ?? 'Network request failed.',
  };
}
