import 'package:boctrust_savings_loan/app/api_failure_classifier.dart';
import 'package:boctrust_savings_loan/app/error_reporting.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases = <(ApiOutcome, ErrorKind, String)>[
    (
      ApiOutcome(backend: ApiBackend.user, dioType: DioExceptionType.cancel),
      ErrorKind.ignored,
      'cancel',
    ),
    (
      ApiOutcome(
        backend: ApiBackend.user,
        statusCode: 401,
        localSessionExpired: true,
      ),
      ErrorKind.breadcrumb,
      'session_expired',
    ),
    (
      ApiOutcome(
        backend: ApiBackend.user,
        statusCode: 401,
        hasEnvelope: true,
        sessionExpiryHandled: true,
      ),
      ErrorKind.breadcrumb,
      'session_expired',
    ),
    (
      ApiOutcome(
        backend: ApiBackend.user,
        dioType: DioExceptionType.connectionError,
      ),
      ErrorKind.breadcrumb,
      'offline',
    ),
    (
      ApiOutcome(
        backend: ApiBackend.core,
        dioType: DioExceptionType.receiveTimeout,
      ),
      ErrorKind.nonfatal,
      'timeout',
    ),
    (
      ApiOutcome(
        backend: ApiBackend.user,
        dioType: DioExceptionType.badCertificate,
      ),
      ErrorKind.nonfatal,
      'transport',
    ),
    (
      ApiOutcome(
        backend: ApiBackend.core,
        statusCode: 401,
        hasEnvelope: true,
        success: false,
      ),
      ErrorKind.nonfatal,
      'core_401',
    ),
    (
      ApiOutcome(
        backend: ApiBackend.user,
        statusCode: 429,
        hasEnvelope: true,
        success: false,
      ),
      ErrorKind.nonfatal,
      'rate_429',
    ),
    (
      ApiOutcome(
        backend: ApiBackend.user,
        statusCode: 503,
        hasEnvelope: true,
        success: false,
      ),
      ErrorKind.nonfatal,
      'server_5xx',
    ),
    (
      ApiOutcome(backend: ApiBackend.user, statusCode: 404),
      ErrorKind.nonfatal,
      'client_4xx_malformed',
    ),
    for (final s in [400, 403, 404, 409, 422])
      (
        ApiOutcome(
          backend: ApiBackend.user,
          statusCode: s,
          hasEnvelope: true,
          success: false,
        ),
        ErrorKind.breadcrumb,
        'client_4xx',
      ),
    (
      ApiOutcome(
        backend: ApiBackend.user,
        statusCode: 200,
        hasEnvelope: true,
        success: false,
      ),
      ErrorKind.breadcrumb,
      'success_false',
    ),
    (
      ApiOutcome(backend: ApiBackend.user, statusCode: 200),
      ErrorKind.nonfatal,
      'malformed_envelope',
    ),
    (
      ApiOutcome(
        backend: ApiBackend.user,
        statusCode: 200,
        hasEnvelope: true,
        success: true,
        parserFailed: true,
      ),
      ErrorKind.nonfatal,
      'parser',
    ),
  ];

  for (final (outcome, kind, category) in cases) {
    test('$category (${outcome.statusCode ?? outcome.dioType})', () {
      final result = classifyApiOutcome(outcome);
      expect(result.kind, kind);
      expect(result.category, category);
      expect(
        result.origin,
        category == 'parser' ? ErrorOrigin.parser : ErrorOrigin.api,
      );
    });
  }

  test('a clean success is ok', () {
    final result = classifyApiOutcome(
      const ApiOutcome(
        backend: ApiBackend.user,
        statusCode: 200,
        hasEnvelope: true,
        success: true,
      ),
    );
    expect(result.category, 'ok');
    expect(result.kind, ErrorKind.breadcrumb);
  });
}
