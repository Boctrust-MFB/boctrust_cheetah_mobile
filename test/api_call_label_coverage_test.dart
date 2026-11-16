import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every service API call carries an ApiCallLabel', () {
    final call = RegExp(r'\.(getData|postData|patchData|deleteData)\s*[<(]');
    final separator = Platform.pathSeparator;
    final problems = <String>[];
    final files = Directory('lib/module')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.dart') &&
              f.path.contains('${separator}service$separator'),
        );
    for (final file in files) {
      final source = file.readAsStringSync();
      final calls = call.allMatches(source).length;
      final labels = 'apiCallLabelKey'.allMatches(source).length;
      if (calls != labels) {
        problems.add('${file.path}: $calls calls, $labels labels');
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
