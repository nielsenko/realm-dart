import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:dart_style/dart_style.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:realm_generator/realm_generator.dart';
import 'package:realm_generator/src/realm_object_generator.dart' show RealmObjectGenerator;
import 'package:source_gen/source_gen.dart' show LibraryReader;
import 'package:test/test.dart';
import 'package:pub_semver/pub_semver.dart';

final _formatter = DartFormatter(languageVersion: Version(3, 7, 0), lineEnding: '\n');

/// Sources for the packages the test inputs (transitively) use, handed to
/// [testBuilder] explicitly. (Resolving them from the test isolate's own
/// package config sends the analyzer's constant evaluator into infinite
/// recursion under build_test >= 3.3 - hence explicit assets.)
final Map<String, String> _realmCommonAssets = {
  for (final pkg in ['realm_common', 'objectid', 'sane_uuid', 'meta', 'crypto', 'typed_data', 'collection']) ..._packageAssets(pkg),
};

Map<String, String> _packageAssets(String name) {
  final configUri = Uri.file(File('../../.dart_tool/package_config.json').absolute.path);
  final config = jsonDecode(File.fromUri(configUri).readAsStringSync()) as Map<String, dynamic>;
  final pkg = (config['packages'] as List).cast<Map<String, dynamic>>().singleWhere((p) => p['name'] == name);
  var rootUri = pkg['rootUri'] as String;
  if (!rootUri.endsWith('/')) rootUri = '$rootUri/';
  final root = configUri.resolve(rootUri);
  final lib = Directory.fromUri(root.resolve('lib/'));
  final sep = Platform.pathSeparator;
  final libPath = lib.path.endsWith(sep) ? lib.path : '${lib.path}$sep';
  return {
    for (final f in lib.listSync(recursive: true).whereType<File>())
      if (f.path.endsWith('.dart')) '$name|lib/${f.path.substring(libPath.length).replaceAll(r'\', '/')}': f.readAsStringSync(),
  };
}

/// Used to test both correct an erroneous compilation.
/// [source] can be a [File] or a [String].
/// [matcher] can be a [File], [String] or a [Matcher].
/// Both expected and actual output will be formatted with [DartFormatter].
@isTest
void testCompile(String description, dynamic source, dynamic matcher, {dynamic skip, void Function(LogRecord)? onLog}) {
  if (source is Iterable) {
    testCompileMany(description, source, matcher);
    return;
  }

  final assetName = source is File ? source.path.replaceAll(r'\', '/') : 'source.dart';
  source = source is File ? source.readAsStringSync() : source;
  if (source is! String) throw ArgumentError.value(source, 'source');

  matcher = matcher is File ? matcher.readAsStringSync() : matcher;
  if (matcher is String) {
    final source = _formatter.format(matcher);
    matcher = completion(equals(source));
  }
  if (matcher is! Matcher) throw ArgumentError.value(matcher, 'matcher');

  test(description, () async {
    generate() async {
      final assets = {..._realmCommonAssets, 'pkg|$assetName': '$source'};
      await _generateDirect(assets, 'pkg|$assetName', onLog: onLog);
      final result = await testBuilder(generateRealmObjects(), assets, rootPackage: 'pkg');
      final outputs = result.buildResult.outputs;
      if (outputs.isEmpty) {
        throw StateError('build produced no outputs');
      }
      final generated = _readOutput(result, outputs.single);
      return _formatter.format(generated);
    }

    expect(generate(), matcher);
  }, skip: skip);
}

@isTest
void testCompileMany(String description, Iterable<dynamic> sources, dynamic matcher) async {
  final inputs = switch (sources) {
    Iterable<File> files => files.map((file) {
      return ('pkg|${file.path.replaceAll(r'\', '/')}', _formatter.format(file.readAsStringSync()));
    }),
    Iterable<String> strings => strings.indexed.map((x) {
      final (index, text) = x;
      return ('pkg|source_$index.dart', _formatter.format(text));
    }),
    _ => throw ArgumentError.value(sources, 'sources'),
  };

  matcher = switch (matcher) {
    Matcher m => m,
    Iterable<String> strings => completion(equals(strings.map((e) => _formatter.format(e)))),
    Iterable<File> files => completion(equals(files.map((x) => _formatter.format(x.readAsStringSync())))),
    _ => throw ArgumentError.value(matcher, 'matcher'),
  };

  test(description, () {
    generate() async {
      final result = await testBuilder(generateRealmObjects(), {..._realmCommonAssets, for (final (id, source) in inputs) id: source}, rootPackage: 'pkg');
      return [for (final a in result.buildResult.outputs) _formatter.format(_readOutput(result, a))];
    }

    expect(generate(), matcher);
  });
}

/// Runs the generator outside build_runner: exceptions propagate to the
/// caller instead of being swallowed as build log entries.
Future<void> _generateDirect(Map<String, String> assets, String input, {void Function(LogRecord)? onLog}) async {
  assets = {input: assets[input]!, ...assets};
  final logger = Logger.detached('testBuilder');
  final subscription = onLog == null ? null : logger.onRecord.listen(onLog);
  try {
    await resolveSources(assets, rootPackage: 'pkg', (resolver) async {
      final lib = await resolver.libraryFor(AssetId.parse(input), allowSyntaxErrors: true);
      await runZoned(() => RealmObjectGenerator().generate(LibraryReader(lib), _DirectBuildStep(resolver)), zoneValues: {#buildLog: logger});
    });
  } finally {
    await subscription?.cancel();
  }
}

class _DirectBuildStep implements BuildStep {
  _DirectBuildStep(this.resolver);

  @override
  final Resolver resolver;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('only resolver is available here');
}

/// Generated outputs are hidden under the generated dir (testBuilder builds
/// with hidden output); map the logical id to where it is actually written.
String _readOutput(TestBuilderResult result, AssetId id) {
  final t = result.readerWriter.testing;
  if (t.exists(id)) return t.readString(id);
  return t.readString(AssetId(id.package, '.dart_tool/build/generated/${id.package}/${id.path}'));
}

final _endOfLine = RegExp(r'\r\n?|\n');

extension StringX on String {
  String normalizeLineEndings() => replaceAll(_endOfLine, '\n');
}
