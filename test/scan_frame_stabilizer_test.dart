import 'package:boctrust_savings_loan/module/core_banking/model/scan_text_models.dart';
import 'package:boctrust_savings_loan/module/core_banking/service/scan_frame_stabilizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a number is accepted only after 3 of the last 5 frames agree', () {
    final s = ScanFrameStabilizer();
    ScanCandidates f(List<String> n) =>
        ScanCandidates(accountNumbers: n, bankTextLines: const ['GTBank']);
    expect(s.add(f(['0123456789'])), isNull);
    expect(s.add(f(['0123456780'])), isNull);
    expect(s.add(f(['0123456789'])), isNull);
    expect(s.add(f(['0123456780'])), isNull);
    expect(s.forming, isTrue);
    final accepted = s.add(f(['0123456789']));
    expect(accepted?.accountNumbers, ['0123456789']);
    expect(accepted?.bankTextLines, ['GTBank']);
  });
}
