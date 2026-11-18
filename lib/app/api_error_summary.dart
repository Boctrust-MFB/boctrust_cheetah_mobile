import 'error_reporting.dart';
import 'services.dart';

/// Server messages known to be static and free of customer data, keyed by
/// server code. Ships empty until the API owners confirm any entries, so
/// every server message is currently reported as `[redacted]`.
const Map<String, String> kSafeServerMessages = <String, String>{};

const _redacted = '[redacted]';
const _maxMessageLength = 120;
const _maxFields = 5;

final _codePattern = RegExp(r'^[A-Za-z0-9_.-]{2,48}$');
final _requestIdPattern = RegExp(r'^[A-Za-z0-9._:-]{1,64}$');
final _fieldPattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9_.]{0,40}$');

/// [candidate] when it is a well-formed opaque request ID, otherwise null.
String? validRequestId(Object? candidate) =>
    candidate is String && _requestIdPattern.hasMatch(candidate)
    ? candidate
    : null;

const _fieldKeys = ['field', 'path', 'param'];

/// Builds a payload-free summary of an error response.
///
/// The message is kept only when [safeMessages] has an entry for the response
/// code and the response message equals that entry exactly; it is then
/// truncated to 120 characters. Anything else becomes `[redacted]`. Request
/// ID precedence: `meta.requestId`, `meta.correlationId`, [headerRequestId];
/// an invalid candidate falls through to the next.
ApiErrorSummary summarizeApiError(
  ServiceResponse<Object?> response, {
  String? headerRequestId,
  Map<String, String> safeMessages = kSafeServerMessages,
}) {
  final rawCode = response.errorCode;
  final code = rawCode != null && _codePattern.hasMatch(rawCode)
      ? rawCode
      : null;
  final message = response.message;

  var safe = _redacted;
  if (code != null && message != null && safeMessages[code] == message) {
    safe = message.length <= _maxMessageLength
        ? message
        : message.substring(0, _maxMessageLength);
  }

  String? requestId;
  for (final candidate in [
    response.meta?.requestId,
    response.meta?.correlationId,
    headerRequestId,
  ]) {
    if (candidate != null && _requestIdPattern.hasMatch(candidate)) {
      requestId = candidate;
      break;
    }
  }

  return ApiErrorSummary(
    code: code,
    message: safe,
    fields: _fieldNames(response.errors),
    requestId: requestId,
  );
}

/// Field names come from `field`/`path`/`param` values; an entry without any
/// of those contributes its map keys. Values are never read otherwise.
List<String> _fieldNames(List<Object?> errors) {
  final names = <String>[];
  void add(Object? name) {
    if (names.length >= _maxFields) return;
    if (name is String &&
        _fieldPattern.hasMatch(name) &&
        !names.contains(name)) {
      names.add(name);
    }
  }

  for (final entry in errors) {
    if (entry is! Map) continue;
    if (_fieldKeys.any(entry.containsKey)) {
      for (final key in _fieldKeys) {
        add(entry[key]);
      }
    } else {
      entry.keys.forEach(add);
    }
  }
  return names;
}
