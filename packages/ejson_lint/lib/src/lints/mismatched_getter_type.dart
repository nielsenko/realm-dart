// Copyright 2024 MongoDB, Inc.
// SPDX-License-Identifier: Apache-2.0

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:ejson_analyzer/ejson_analyzer.dart';

class MismatchedGetterType extends AnalysisRule {
  static const LintCode code = LintCode(
    'mismatched_getter_type',
    'Type of getter does not match type of constructor parameter',
    severity: DiagnosticSeverity.ERROR,
  );

  MismatchedGetterType() : super(name: 'mismatched_getter_type', description: 'Type of getter does not match type of constructor parameter.');

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addConstructorDeclaration(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;

  _Visitor(this.rule);

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final ctor = node.declaredFragment?.element;
    if (ctor == null) return; // not resolved
    if (!isEJsonAnnotated(ctor)) return;
    final cls = ctor.enclosingElement;
    for (final param in node.parameters.parameters) {
      final element = param.declaredFragment?.element;
      final name = element?.name;
      if (element == null || name == null) continue;
      final getter = cls.getGetter(name);
      if (getter == null) continue;
      if (getter.returnType != element.type) {
        // For an implicit getter nonSynthetic is the backing field.
        final getterNameOffset = getter.nonSynthetic.firstFragment.nameOffset;
        if (getterNameOffset != null) {
          rule.reportAtOffset(getterNameOffset, name.length);
        }
        final paramName = param.name;
        if (paramName != null) {
          rule.reportAtToken(paramName);
        }
      }
    }
  }
}
