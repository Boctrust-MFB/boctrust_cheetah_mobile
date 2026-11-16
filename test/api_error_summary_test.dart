import 'package:boctrust_savings_loan/app/api_error_summary.dart';
import 'package:boctrust_savings_loan/app/services.dart';
import 'package:flutter_test/flutter_test.dart';

ServiceResponse<Object?> _err({
  String? message,
  String? code,
  List<Object?> errors = const [],
  ApiMeta? meta,
}) => ServiceResponse.error(
  message ?? 'm',
  errorCode: code,
  errors: errors,
  meta: meta,
);

void main() {
  test('keeps a valid code and redacts an unlisted message', () {
    final s = summarizeApiError(
      _err(code: 'TRANSFER_FAILED', message: 'Transfer failed'),
    );
    expect(s.code, 'TRANSFER_FAILED');
    expect(s.message, '[redacted]');
  });

  test('redacts free-text and echoed messages', () {
    for (final m in [
      'Call 08012345678',
      'Account 0123456789 invalid',
      'Bearer abc',
      'John Okafor not found',
    ]) {
      expect(
        summarizeApiError(_err(code: 'E_X', message: m)).message,
        '[redacted]',
      );
    }
  });

  test('uses an allowlisted message for its code, truncated to 120', () {
    final long = 'a' * 200;
    final map = {'E_LONG': long, 'E_SHORT': 'Try later'};
    expect(
      summarizeApiError(
        _err(code: 'E_LONG', message: long),
        safeMessages: map,
      ).message,
      'a' * 120,
    );
    expect(
      summarizeApiError(
        _err(code: 'E_SHORT', message: 'Try later'),
        safeMessages: map,
      ).message,
      'Try later',
    );
    expect(
      summarizeApiError(
        _err(code: 'E_SHORT', message: 'Other'),
        safeMessages: map,
      ).message,
      '[redacted]',
    );
    expect(
      summarizeApiError(
        _err(code: 'E_OTHER', message: 'Try later'),
        safeMessages: map,
      ).message,
      '[redacted]',
    );
  });

  test('rejects codes outside the pattern', () {
    for (final c in ['x', '<script>', 'A' * 49, '{"a":1}']) {
      expect(summarizeApiError(_err(code: c)).code, isNull);
    }
  });

  test('keeps at most five valid field names and never values', () {
    final s = summarizeApiError(
      _err(
        errors: [
          {'field': 'amount', 'message': '08012345678'},
          {'08012345678': 'bad'},
        ],
      ),
    );
    expect(s.fields, ['amount']);

    final many = summarizeApiError(
      _err(
        errors: [
          for (final n in ['a', 'b', 'c', 'd', 'e', 'f']) {'path': n},
        ],
      ),
    );
    expect(many.fields, ['a', 'b', 'c', 'd', 'e']);
  });

  test('reads request id from meta before header and validates it', () {
    expect(
      summarizeApiError(
        _err(
          meta: const ApiMeta(requestId: 'req-1', correlationId: 'c-1'),
        ),
        headerRequestId: 'h-1',
      ).requestId,
      'req-1',
    );
    expect(
      summarizeApiError(
        _err(meta: const ApiMeta(correlationId: 'c-1')),
        headerRequestId: 'h-1',
      ).requestId,
      'c-1',
    );
    expect(summarizeApiError(_err(), headerRequestId: 'h-1').requestId, 'h-1');
    expect(
      summarizeApiError(
        _err(meta: const ApiMeta(requestId: 'abc\nInjected')),
      ).requestId,
      isNull,
    );
    expect(
      summarizeApiError(
        _err(meta: const ApiMeta(requestId: 'abc\nInjected')),
        headerRequestId: 'h-1',
      ).requestId,
      'h-1',
    );
  });
}
