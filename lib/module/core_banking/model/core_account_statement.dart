import 'dart:convert';
import 'dart:typed_data';

import 'core_json.dart';

const _pdfContentType = 'application/pdf';

/// Why a statement range cannot be requested, or null when it can: the dates
/// must be ordered, [toDate] no later than [today], and the span at most one
/// calendar year. Time of day is ignored.
String? coreStatementRangeError(
  DateTime fromDate,
  DateTime toDate, {
  required DateTime today,
}) {
  final from = DateTime(fromDate.year, fromDate.month, fromDate.day);
  final to = DateTime(toDate.year, toDate.month, toDate.day);
  final now = DateTime(today.year, today.month, today.day);
  if (from.isAfter(to)) return 'The start date must not be after the end date.';
  if (to.isAfter(now)) return 'The end date cannot be in the future.';
  if (from.isBefore(DateTime(to.year - 1, to.month, to.day))) {
    return 'Choose a period of up to 12 months.';
  }
  return null;
}

/// A PDF statement from Core, with its content already decoded.
class CoreAccountStatement {
  const CoreAccountStatement({
    required this.accountNumber,
    required this.fromDate,
    required this.toDate,
    required this.fileName,
    required this.contentType,
    required this.bytes,
  });

  factory CoreAccountStatement.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Invalid statement.');
    final accountNumber = coreText(json['accountNumber']);
    final fromDate = coreText(json['fromDate']);
    final toDate = coreText(json['toDate']);
    final fileName = coreText(json['fileName']);
    final contentType = coreText(json['contentType']);
    final content = coreText(json['content']);
    if (accountNumber == null ||
        fromDate == null ||
        toDate == null ||
        fileName == null ||
        contentType == null ||
        content == null) {
      throw const FormatException('Incomplete statement.');
    }
    if (contentType.toLowerCase() != _pdfContentType) {
      throw const FormatException('Statement is not a PDF.');
    }
    final bytes = base64Decode(content);
    if (bytes.isEmpty) throw const FormatException('Statement is empty.');
    return CoreAccountStatement(
      accountNumber: accountNumber,
      fromDate: fromDate,
      toDate: toDate,
      fileName: fileName,
      contentType: _pdfContentType,
      bytes: bytes,
    );
  }

  final String accountNumber;
  final String fromDate;
  final String toDate;
  final String fileName;
  final String contentType;
  final Uint8List bytes;
}
