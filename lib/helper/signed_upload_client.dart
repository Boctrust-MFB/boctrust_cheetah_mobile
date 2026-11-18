import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

import '../app/api_logger.dart';
import '../app/error_reporting.dart';
import '../app/services.dart';

/// Outcome of a signed binary upload.
///
/// The signed storage endpoint is not the User Service, so its responses never
/// carry the `{ success, message, data, meta }` envelope. Any 2xx is success.
class SignedUploadResult {
  const SignedUploadResult({required this.statusCode});

  final int statusCode;
}

/// Uploads bytes to a short-lived, API-issued signed URL.
///
/// Deliberately separate from [ApiService]: a signed upload must never receive
/// the User Service bearer token, and must never be resolved against the
/// User Service base URL.
abstract interface class SignedUploadClient {
  Future<NotifierState<SignedUploadResult>> putBytes({
    required Uri url,
    required List<int> bytes,
    required Map<String, String> headers,
  });
}

/// Dio instance dedicated to signed uploads.
///
/// No base URL, no default JSON content type, and — critically — no
/// [AuthInterceptor]. Logging is wired separately so uploads stay observable.
final signedUploadDioProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
    ),
  ),
);

final signedUploadClientProvider = Provider<SignedUploadClient>(
  (ref) => DioSignedUploadClient(
    ref.watch(signedUploadDioProvider),
    reporter: ref.watch(errorReporterProvider),
    releaseLogPolicy: Env.releaseLogPolicy,
  ),
);

class DioSignedUploadClient implements SignedUploadClient {
  DioSignedUploadClient(
    this._dio, {
    Logger? logger,
    this._reporter = const NoopErrorReporter(),
    this.releaseLogPolicy = false,
  }) : _logger = logger ?? apiLogger;

  static const _label = ApiCallLabel(
    feature: 'kyc',
    action: 'upload_kyc_document',
    stage: 'upload',
    endpoint: 'signed_upload',
  );

  final Dio _dio;
  final Logger _logger;
  final AppErrorReporter _reporter;

  /// Production release builds only: log event, method, full URL, status and
  /// duration. Headers, response bodies and exception text are dropped. The
  /// signed URL stays by decision; it is a bearer credential until it expires.
  final bool releaseLogPolicy;

  /// Reports a failed upload. Never throws, and never carries the signed URL,
  /// its query, the headers or the exception text.
  void _report(
    String category,
    ErrorKind kind,
    int? statusCode,
    StackTrace stack,
  ) {
    try {
      _reporter.report(
        ErrorEvent(
          kind: kind,
          origin: ErrorOrigin.upload,
          reason: category,
          label: _label,
          backend: ApiBackend.storage,
          method: 'PUT',
          category: category,
          statusCode: statusCode,
          error: ApiFailure('storage PUT ${_label.endpoint} $category'),
          stack: stack,
        ),
      );
    } catch (_) {}
  }

  @override
  Future<NotifierState<SignedUploadResult>> putBytes({
    required Uri url,
    required List<int> bytes,
    required Map<String, String> headers,
  }) async {
    if (url.scheme != 'https') {
      _logger.e({
        'event': 'UPLOAD_REJECTED',
        'reason': 'non-https upload URL',
        'scheme': url.scheme,
      });
      return const NotifierState.error(
        'The upload link was not secure. Request a new link and try again.',
      );
    }

    // Captured before any await so the report points at the upload call site.
    final callStack = StackTrace.current;
    final startedAt = DateTime.now();
    _logger.i({
      'event': 'UPLOAD_REQUEST',
      'method': 'PUT',
      'url': url.toString(),
      if (!releaseLogPolicy) ...{
        'headers': headers,
        'body': '<binary ${bytes.length} bytes>',
      },
    });

    try {
      final response = await _dio.putUri<Object?>(
        url,
        data: Stream<List<int>>.value(bytes),
        options: Options(
          headers: {...headers, Headers.contentLengthHeader: bytes.length},
          responseType: ResponseType.plain,
          // The storage endpoint owns the status contract; map it ourselves.
          validateStatus: (_) => true,
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final duration = DateTime.now().difference(startedAt);
      final isSuccess = statusCode >= 200 && statusCode < 300;

      _logger.i({
        'event': 'UPLOAD_RESPONSE',
        if (releaseLogPolicy) 'method': 'PUT',
        'url': url.toString(),
        'status': statusCode,
        'durationMs': duration.inMilliseconds,
        if (!isSuccess && !releaseLogPolicy) 'body': response.data,
      });

      if (isSuccess) {
        return NotifierState.done(SignedUploadResult(statusCode: statusCode));
      }
      _reportStatus(statusCode, callStack);
      return NotifierState.error(
        _failureMessage(statusCode),
        statusCode: statusCode,
      );
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      _logger.e({
        'event': 'UPLOAD_ERROR',
        if (releaseLogPolicy) 'method': 'PUT',
        'url': url.toString(),
        'status': statusCode,
        'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        'type': error.type.name,
        if (!releaseLogPolicy) ...{
          'message': error.message,
          'body': error.response?.data,
        },
      });
      if (statusCode != null) {
        _reportStatus(statusCode, callStack);
        return NotifierState.error(
          _failureMessage(statusCode),
          statusCode: statusCode,
        );
      }
      _reportTransport(error.type, callStack);
      return NotifierState.error(_transportMessage(error));
    }
  }

  void _reportStatus(int statusCode, StackTrace stack) {
    if (statusCode >= 500) {
      _report('server_5xx', ErrorKind.nonfatal, statusCode, stack);
    } else if (statusCode == 400 || statusCode == 403) {
      _report('expired_link', ErrorKind.breadcrumb, statusCode, stack);
    } else if (statusCode >= 400 && statusCode < 500) {
      // Not listed by the spec; signals a broken upload contract.
      _report('client_4xx', ErrorKind.nonfatal, statusCode, stack);
    } else {
      // Missing, informational or redirect status from the storage endpoint.
      _report('unexpected_status', ErrorKind.nonfatal, statusCode, stack);
    }
  }

  void _reportTransport(DioExceptionType type, StackTrace stack) {
    switch (type) {
      case DioExceptionType.cancel:
        return;
      case DioExceptionType.connectionError:
        _report('offline', ErrorKind.breadcrumb, null, stack);
      case DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout:
        _report('timeout', ErrorKind.nonfatal, null, stack);
      default:
        _report('transport', ErrorKind.nonfatal, null, stack);
    }
  }

  static const _expiredMessage =
      'The upload link expired. Request a new link and try again.';

  static String _failureMessage(int statusCode) => switch (statusCode) {
    400 || 403 => _expiredMessage,
    _ => 'The upload failed. Please try again.',
  };

  static String _transportMessage(DioException error) => switch (error.type) {
    DioExceptionType.connectionError =>
      'No internet connection. Please try again.',
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout =>
      'The upload timed out. Please try again.',
    DioExceptionType.cancel => 'The upload was cancelled.',
    _ => error.message ?? 'The upload failed. Please try again.',
  };
}
