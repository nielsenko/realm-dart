// Copyright 2024 MongoDB, Inc.
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:build_test/build_test.dart' as bt;

/// Runs a [Builder] on a given [source] string, allowing exceptions to
/// propagate to tests.
///
/// This wraps the actual builder used in production so the output is
/// identical, but captures and re-throws exceptions for testing.
Future<String?> testBuilder(Builder builder, String source, {String package = 'pkg', String path = 'source.dart'}) async {
  Exception? capturedException;

  final wrappedBuilder = _ExceptionCapturingBuilder(builder, onException: (e) => capturedException = e);

  final rw = TestReaderWriter(rootPackage: package);
  await rw.testing.loadIsolateSources();

  final result = await bt.testBuilder(wrappedBuilder, {'$package|$path': source}, readerWriter: rw);

  // If an exception was captured, throw it now to allow tests to inspect it
  if (capturedException != null) {
    throw capturedException!;
  }

  // Read the output from the generated location
  final outputs = result.outputs;
  if (outputs.isEmpty) return null;

  final outputId = outputs.single;
  final mappedId = AssetId(package, '.dart_tool/build/generated/$package/${outputId.path}');

  if (rw.testing.exists(mappedId)) {
    final bytes = rw.testing.readBytes(mappedId);
    return String.fromCharCodes(bytes);
  }

  return null;
}

/// A builder wrapper that captures exceptions from the wrapped builder
/// instead of letting the build system catch them.
class _ExceptionCapturingBuilder implements Builder {
  final Builder wrappedBuilder;
  final void Function(Exception) onException;

  _ExceptionCapturingBuilder(this.wrappedBuilder, {required this.onException});

  @override
  Map<String, List<String>> get buildExtensions => wrappedBuilder.buildExtensions;

  @override
  Future<void> build(BuildStep buildStep) async {
    try {
      await wrappedBuilder.build(buildStep);
    } on Exception catch (e) {
      // Capture the exception to re-throw it outside the build system
      onException(e);
      // Re-throw so the build fails
      rethrow;
    }
  }
}
