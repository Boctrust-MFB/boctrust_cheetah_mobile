import 'dart:collection';

import '../model/scan_text_models.dart';

/// Accepts a scanned account number only once it repeats across recent
/// camera frames, since OCR flickers individual digits from frame to frame.
class ScanFrameStabilizer {
  ScanFrameStabilizer({this.window = 5, this.required = 3});

  /// How many recent frames are kept.
  final int window;

  /// How many frames in the window must read a number before it is accepted.
  final int required;

  final Queue<ScanCandidates> _frames = Queue<ScanCandidates>();

  /// Records one frame. Returns the stable result once a number has held
  /// steady, or `null` until then.
  ScanCandidates? add(ScanCandidates frame) {
    _frames.addLast(frame);
    while (_frames.length > window) {
      _frames.removeFirst();
    }

    final stable = [
      for (final entry in _counts().entries)
        if (entry.value >= required) entry.key,
    ];
    if (stable.isEmpty) return null;
    final lines = <String>{
      for (final f in _frames) ...f.bankTextLines,
    };
    return ScanCandidates(
      accountNumbers: stable,
      bankTextLines: lines.toList(),
    );
  }

  /// True while a number is in the window but none has reached [required].
  bool get forming {
    final counts = _counts();
    return counts.isNotEmpty && counts.values.every((c) => c < required);
  }

  /// How many frames in the window read each number, in first-seen order.
  Map<String, int> _counts() {
    final counts = <String, int>{};
    for (final f in _frames) {
      for (final number in f.accountNumbers.toSet()) {
        counts[number] = (counts[number] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Clears the window, e.g. when the camera retargets.
  void reset() => _frames.clear();
}
