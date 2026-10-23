import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import 'interbank_models.dart';

/// A rectangle in `[0,1]` with a top-left origin, measured on the upright
/// image after EXIF orientation: `(0,0)` is its top-left pixel and `(1,1)` its
/// bottom-right.
class ScanTextBox extends Equatable {
  const ScanTextBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  @override
  List<Object?> get props => [left, top, width, height];
}

/// One line of text recognized on a scanned image.
class RecognizedLine extends Equatable {
  const RecognizedLine(this.text, this.box);

  final String text;
  final ScanTextBox box;

  @override
  List<Object?> get props => [text, box];
}

/// The pixel layout of a live camera frame.
enum ScanFrameFormat { nv21, bgra8888 }

/// A raw camera preview frame. [width] and [height] are the sensor frame's,
/// [bytesPerRow] its row stride, and [rotation] the turn (0, 90, 180 or 270)
/// that makes the frame upright: the sensor orientation on Android, 0 on iOS
/// because its frames arrive upright.
class ScanFrame {
  const ScanFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.rotation,
    required this.format,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int bytesPerRow;
  final int rotation;
  final ScanFrameFormat format;
}

/// What a scan offers the customer to confirm. Nothing here is sent anywhere
/// until they confirm it.
class ScanCandidates extends Equatable {
  const ScanCandidates({
    required this.accountNumbers,
    required this.bankTextLines,
  });

  /// Distinct ten-digit numbers in reading order.
  final List<String> accountNumbers;

  /// Every recognized line with its digit runs removed, empty lines dropped.
  final List<String> bankTextLines;

  @override
  List<Object?> get props => [accountNumbers, bankTextLines];
}

enum BankMatchStatus {
  /// Exactly one supported bank was named.
  unique,

  /// Several banks were named, or only near matches were found.
  ambiguous,

  /// No supported bank was found.
  none,
}

/// The supported banks a scan's text points to, best first. Only
/// [BankMatchStatus.unique] is safe to preselect.
class BankMatch extends Equatable {
  const BankMatch(this.status, this.candidates);

  final BankMatchStatus status;
  final List<CommercialBank> candidates;

  @override
  List<Object?> get props => [status, candidates];
}
