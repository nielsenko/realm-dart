// Copyright 2024 MongoDB, Inc.
// SPDX-License-Identifier: Apache-2.0

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart' as error;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:ejson_analyzer/ejson_analyzer.dart';

class MismatchedGetterType extends DartLintRule {
  MismatchedGetterType()
    : super(
        code: const LintCode(
          name: 'mismatched_getter_type',
          problemMessage: 'Type of getter does not match type of constructor parameter',
          errorSeverity: error.DiagnosticSeverity.ERROR,
        ),
      );

  @override
  void run(CustomLintResolver resolver, DiagnosticReporter reporter, CustomLintContext context) {
    context.registry.addConstructorDeclaration((node) {
      final ctor = node.declaredFragment;
      if (ctor == null) return; // not resolved;
      if (isEJsonAnnotated(ctor.element)) {
        final cls = ctor.enclosingFragment as ClassFragment;
        for (final param in ctor.formalParameters) {
          final getter = cls.element.getGetter(param.element.name!);
          if (getter == null) continue;
          if (getter.returnType != param.element.type) {
            reporter.atElement2(getter, code);
            reporter.atElement2(param.element, code);
          }
        }
      }
    });
  }
}
