import 'dart:typed_data';

import 'package:boctrust_savings_loan/app/error_reporting.dart';
import 'package:boctrust_savings_loan/app/services.dart';
import 'package:boctrust_savings_loan/helper/signed_upload_client.dart';
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

final _url = Uri.parse(
  'https://bucket.s3.eu-west-1.amazonaws.com/kyc/doc.png'
  '?X-Amz-Signature=abc123secret&X-Amz-Credential=cred',
);
const _headers = {'x-amz-meta-secret': 'header-secret'};

DioSignedUploadClient _client(_Reply reply, RecordingErrorReporter reporter) =>
    DioSignedUploadClient(
      Dio()..httpClientAdapter = _Adapter(reply),
      logger: Logger(level: Level.off),
      reporter: reporter,
    );

_Reply _status(int code) =>
    (_) async => ResponseBody.fromString('', code);

_Reply _throws(DioExceptionType type) =>
    (o) async => throw DioException(requestOptions: o, type: type);

Future<NotifierState<SignedUploadResult>> _put(DioSignedUploadClient c) =>
    c.putBytes(url: _url, bytes: [1, 2, 3], headers: _headers);

void main() {
  const label = ApiCallLabel(
    feature: 'kyc',
    action: 'upload_kyc_document',
    stage: 'upload',
    endpoint: 'signed_upload',
  );

  test('upload 500 reports a nonfatal with endpoint signed_upload', () async {
    final reporter = RecordingErrorReporter();
    final state = await _put(_client(_status(500), reporter));

    expect(state.statusCode, 500);
    final e = reporter.events.single;
    expect(e.kind, ErrorKind.nonfatal);
    expect(e.origin, ErrorOrigin.upload);
    expect(e.reason, 'server_5xx');
    expect(e.category, 'server_5xx');
    expect(e.label, label);
    expect(e.backend, ApiBackend.storage);
    expect(e.method, 'PUT');
    expect(e.statusCode, 500);
    expect(e.summary, isNull);
    expect(e.error.toString(), 'storage PUT signed_upload server_5xx');
    expect(e.stack, isNotNull);
  });

  test('expired link 403 reports a breadcrumb', () async {
    final reporter = RecordingErrorReporter();
    await _put(_client(_status(403), reporter));

    final e = reporter.events.single;
    expect(e.kind, ErrorKind.breadcrumb);
    expect(e.reason, 'expired_link');
    expect(e.statusCode, 403);
  });

  test('offline upload reports a breadcrumb', () async {
    final reporter = RecordingErrorReporter();
    await _put(_client(_throws(DioExceptionType.connectionError), reporter));

    final e = reporter.events.single;
    expect(e.kind, ErrorKind.breadcrumb);
    expect(e.reason, 'offline');
    expect(e.statusCode, isNull);
  });

  test('timeout and transport failures report nonfatals', () async {
    final reporter = RecordingErrorReporter();
    await _put(_client(_throws(DioExceptionType.sendTimeout), reporter));
    await _put(_client(_throws(DioExceptionType.unknown), reporter));

    expect(reporter.events.map((e) => (e.kind, e.reason)), [
      (ErrorKind.nonfatal, 'timeout'),
      (ErrorKind.nonfatal, 'transport'),
    ]);
  });

  test(
    'other 4xx is nonfatal client_4xx; success and cancel are silent',
    () async {
      final reporter = RecordingErrorReporter();
      await _put(_client(_status(413), reporter));
      await _put(_client(_status(200), reporter));
      await _put(_client(_throws(DioExceptionType.cancel), reporter));

      final e = reporter.events.single;
      expect(e.kind, ErrorKind.nonfatal);
      expect(e.reason, 'client_4xx');
    },
  );

  test(
    '3xx and other non-2xx statuses are nonfatal unexpected_status',
    () async {
      final reporter = RecordingErrorReporter();
      await _put(_client(_status(302), reporter));
      await _put(_client(_status(100), reporter));

      expect(reporter.events.map((e) => (e.kind, e.reason)), [
        (ErrorKind.nonfatal, 'unexpected_status'),
        (ErrorKind.nonfatal, 'unexpected_status'),
      ]);
    },
  );

  test(
    'upload event never contains the signed url, query or headers',
    () async {
      final reporter = RecordingErrorReporter();
      await _put(_client(_status(500), reporter));
      await _put(_client(_status(403), reporter));
      await _put(_client(_throws(DioExceptionType.unknown), reporter));
      expect(reporter.events, hasLength(3));

      for (final e in reporter.events) {
        final text = [
          e.kind,
          e.origin,
          e.reason,
          e.label.feature,
          e.label.action,
          e.label.stage,
          e.label.endpoint,
          e.backend,
          e.method,
          e.category,
          e.statusCode,
          e.summary,
          e.error,
        ].join(' ');
        for (final secret in [
          'X-Amz-Signature',
          'abc123secret',
          'amazonaws',
          'bucket',
          'header-secret',
          'x-amz-meta',
        ]) {
          expect(text, isNot(contains(secret)));
        }
      }
    },
  );

  test('a throwing reporter leaves the returned state unchanged', () async {
    final reporter = RecordingErrorReporter()..throwOnReport = true;
    final state = await _put(_client(_status(500), reporter));

    expect(state.statusCode, 500);
    expect(state.message, 'The upload failed. Please try again.');
  });
}
