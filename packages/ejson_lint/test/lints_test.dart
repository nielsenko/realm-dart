@Timeout(Duration(minutes: 5)) // the analysis server needs to resolve and compile the plugin on first run
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const lintNames = {'mismatched_getter_type', 'missing_getter', 'too_many_annotated_constructors'};

/// Parse `// expect_lint: name, ...` comments.
/// Each comment declares the lints expected on the next line.
Set<(int, String)> expectedLints(File file) {
  final result = <(int, String)>{};
  final lines = file.readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    final match = RegExp(r'//\s*expect_lint:\s*(.*)$').firstMatch(lines[i]);
    if (match == null) continue;
    for (final name in match[1]!.split(',')) {
      result.add((i + 2, name.trim())); // lints expected on the next 1-indexed line
    }
  }
  return result;
}

void main() {
  test('example triggers all expected lints', () {
    final exampleDir = Directory('example').absolute;
    final exampleFile = File('${exampleDir.path}/bin/example.dart');
    final expected = expectedLints(exampleFile);
    expect(expected, isNotEmpty, reason: 'sanity check: example should declare expect_lint comments');

    final analyze = Process.runSync('dart', ['analyze', '--format=json', '.'], workingDirectory: exampleDir.path);
    final jsonStart = (analyze.stdout as String).indexOf('{');
    expect(jsonStart, isNot(-1), reason: 'no json in analyze output:\n${analyze.stdout}\n${analyze.stderr}');

    final report = jsonDecode((analyze.stdout as String).substring(jsonStart)) as Map<String, dynamic>;
    final actual = <(int, String)>{};
    for (final diagnostic in report['diagnostics'] as List<dynamic>) {
      final code = (diagnostic as Map<String, dynamic>)['code'] as String;
      final name = lintNames.lookup(code.split('/').last); // strip plugin prefix, if any
      if (name == null) continue;
      final line = ((diagnostic['location'] as Map<String, dynamic>)['range'] as Map<String, dynamic>)['start'] as Map<String, dynamic>;
      actual.add((line['line'] as int, name));
    }
    expect(actual, expected);
  });
}
