import 'dart:convert';
import 'dart:typed_data';

import 'package:boctrust_savings_loan/app/core_api_endpoints.dart';
import 'package:boctrust_savings_loan/app/error_reporting.dart';
import 'package:boctrust_savings_loan/app/firebase_error_reporter.dart';
import 'package:boctrust_savings_loan/app/interceptors.dart';
import 'package:boctrust_savings_loan/app/network.dart';
import 'package:boctrust_savings_loan/app/services.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'support/recording_error_reporter.dart';

typedef _Reply = Future<ResponseBody> Function(RequestOptions options);

class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply);
  final _Reply reply;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => reply(options);

  @override
  void close({bool force = false}) {}
}

_Reply _json(int statusCode, Object? body, {Duration delay = Duration.zero}) =>
    (_) async {
      await Future<void>.delayed(delay);
      return ResponseBody.fromString(
        jsonEncode(body),
        statusCode,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    };

_Reply _throws(DioExceptionType type) =>
    (options) async => throw DioException(requestOptions: options, type: type);

Dio _dio(_Reply reply) => Dio()..httpClientAdapter = _Adapter(reply);

const _authorize = ApiCallLabel(
  feature: 'transfer',
  action: 'authorize_transfer',
  stage: 'submit',
  endpoint: 'transfers_authorize',
);

Map<String, Object?> _labelled(ApiCallLabel label) => {apiCallLabelKey: label};

Map<String, Object?> _serverError(String requestId) => {
  'success': false,
  'message': 'Upstream unavailable.',
  'code': 'UPSTREAM_DOWN',
  'meta': {'requestId': requestId},
};

Future<ServiceResponse<Object?>> callingServiceMethod(ApiService api) =>
    api.getData<Object?>('/x', parser: (data) => data);

String rejectingParser(Object? data) =>
    throw const FormatException('unexpected shape');

void main() {
  late RecordingErrorReporter reporter;

  setUp(() => reporter = RecordingErrorReporter());

  test('503 reports one nonfatal with label, code and request id', () async {
    await ApiService(
      _dio(_json(503, _serverError('req-1'))),
      reporter: reporter,
    ).postData<Object?>(
      '/transfers/authorize',
      parser: (data) => data,
      requestExtra: _labelled(_authorize),
    );

    final event = reporter.events.single;
    expect(event.kind, ErrorKind.nonfatal);
    expect(event.origin, ErrorOrigin.api);
    expect(event.category, 'server_5xx');
    expect(event.reason, 'api server_5xx');
    expect(event.label.action, 'authorize_transfer');
    expect(event.backend, ApiBackend.user);
    expect(event.method, 'POST');
    expect(event.statusCode, 503);
    expect(event.summary?.code, 'UPSTREAM_DOWN');
    expect(event.summary?.requestId, 'req-1');
    expect(event.error.toString(), 'user POST transfers_authorize server_5xx');
  });

  test('validation 422 reports a breadcrumb, not a nonfatal', () async {
    await ApiService(
      _dio(
        _json(422, {
          'success': false,
          'message': 'Amount is too high.',
          'code': 'VALIDATION_ERROR',
          'errors': [
            {'field': 'amount', 'message': 'Must be at most 5000.'},
          ],
        }),
      ),
      reporter: reporter,
    ).postData<Object?>('/x', parser: (data) => data);

    final event = reporter.events.single;
    expect(event.kind, ErrorKind.breadcrumb);
    expect(event.category, 'client_4xx');
    expect(event.summary?.fields, ['amount']);
  });

  test('cancel reports nothing', () async {
    await ApiService(
      _dio(_throws(DioExceptionType.cancel)),
      reporter: reporter,
    ).getData<Object?>('/x', parser: (data) => data);

    expect(reporter.events, isEmpty);
  });

  test('parser failure reports origin parser with the parser stack', () async {
    await ApiService(
      _dio(_json(200, {'success': true, 'data': 'not a map'})),
      reporter: reporter,
    ).getData<String>('/x', parser: rejectingParser);

    final event = reporter.events.single;
    expect(event.kind, ErrorKind.nonfatal);
    expect(event.origin, ErrorOrigin.parser);
    expect(event.category, 'parser');
    expect(event.stack.toString(), contains('rejectingParser'));
  });

  test('stack captured at call site names the calling function', () async {
    await callingServiceMethod(
      ApiService(_dio(_json(503, _serverError('req-1'))), reporter: reporter),
    );

    expect(
      reporter.events.single.stack.toString(),
      contains('callingServiceMethod'),
    );
  });

  test('core service is labelled core backend', () async {
    await ApiService(
      _dio(_json(500, _serverError('req-1'))),
      backend: ApiBackend.core,
      reporter: reporter,
    ).getData<Object?>('/x', parser: (data) => data);

    final event = reporter.events.single;
    expect(event.backend, ApiBackend.core);
    expect(event.error.toString(), startsWith('core GET '));
  });

  test(
    'two interleaved failures keep their own labels and summaries',
    () async {
      const balance = ApiCallLabel(
        feature: 'home',
        action: 'load_balance',
        stage: 'load',
        endpoint: 'bank_account',
      );
      final api = ApiService(
        _dio(
          (options) => options.path == '/slow'
              ? _json(
                  503,
                  _serverError('req-slow'),
                  delay: const Duration(milliseconds: 30),
                )(options)
              : _json(500, _serverError('req-fast'))(options),
        ),
        reporter: reporter,
      );

      await Future.wait([
        api.postData<Object?>(
          '/slow',
          parser: (data) => data,
          requestExtra: _labelled(_authorize),
        ),
        api.getData<Object?>(
          '/fast',
          parser: (data) => data,
          requestExtra: _labelled(balance),
        ),
      ]);

      expect(reporter.events, hasLength(2));
      final slow = reporter.events.singleWhere((e) => e.label == _authorize);
      final fast = reporter.events.singleWhere((e) => e.label == balance);
      expect(slow.summary?.requestId, 'req-slow');
      expect(slow.method, 'POST');
      expect(fast.summary?.requestId, 'req-fast');
      expect(fast.method, 'GET');
    },
  );

  test('unlabeled dynamic path never leaks', () async {
    await ApiService(
      _dio(_json(500, _serverError('req-1'))),
      backend: ApiBackend.core,
      reporter: reporter,
    ).getData<Object?>(
      CoreApiEndpoints.bankAccount('0123456789'),
      parser: (data) => data,
    );

    final event = reporter.events.single;
    expect(event.label.endpoint, 'endpoint_unclassified');
    for (final text in [
      event.error.toString(),
      event.reason,
      event.information.join('\n'),
      event.breadcrumb,
    ]) {
      expect(text, isNot(contains('0123456789')));
    }
  });

  test('throwing reporter does not change the response', () async {
    final replies = <_Reply>[
      _json(503, _serverError('req-1')),
      _json(409, {
        'success': false,
        'message': 'In progress.',
        'code': 'IN_PROGRESS',
        'data': 'existing',
      }),
      _json(200, {'success': true, 'data': 'not a map'}),
      _throws(DioExceptionType.receiveTimeout),
    ];
    for (final reply in replies) {
      final throwing = RecordingErrorReporter()..throwOnReport = true;
      final quiet = await ApiService(
        _dio(reply),
      ).getData<String>('/x', parser: (data) => data! as String);
      final noisy = await ApiService(
        _dio(reply),
        reporter: throwing,
      ).getData<String>('/x', parser: (data) => data! as String);
      expect(noisy, quiet);
    }
  });

  test('bad network session stays within budget', () async {
    final sink = FakeSink();
    final firebase = FirebaseErrorReporter(sink, context: ReportingContext());
    final offline = ApiService(
      _dio(_throws(DioExceptionType.connectionError)),
      reporter: firebase,
    );
    final slow = ApiService(
      _dio(_throws(DioExceptionType.receiveTimeout)),
      reporter: firebase,
    );

    for (var i = 0; i < 20; i++) {
      await offline.getData<Object?>(
        '/x',
        parser: (data) => data,
        requestExtra: _labelled(_authorize),
      );
    }
    for (var i = 0; i < 10; i++) {
      await slow.getData<Object?>(
        '/x',
        parser: (data) => data,
        requestExtra: _labelled(_authorize),
      );
    }

    expect(sink.recordErrorCalls.length, lessThanOrEqualTo(4));
    expect(sink.logCalls, hasLength(30));
  });

  test('label is not written to the staging request log', () async {
    final output = _CapturingOutput();
    final dio = _dio(_json(200, {'success': true, 'data': 'ok'}))
      ..interceptors.add(
        LoggingInterceptor(
          includeSensitiveData: true,
          logger: Logger(
            filter: ProductionFilter(),
            printer: SimplePrinter(printTime: false, colors: false),
            output: output,
          ),
        ),
      );

    await ApiService(dio, reporter: reporter).getData<Object?>(
      '/x',
      parser: (data) => data,
      requestExtra: _labelled(_authorize),
    );

    expect(output.lines, isNotEmpty);
    expect(output.lines.join(), isNot(contains(apiCallLabelKey)));
    expect(reporter.events, isEmpty);
  });
}

class _CapturingOutput extends LogOutput {
  final List<String> lines = [];

  @override
  void output(OutputEvent event) => lines.addAll(event.lines);
}
