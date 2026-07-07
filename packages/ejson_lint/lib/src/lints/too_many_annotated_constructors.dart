// Copyright 2024 MongoDB, Inc.
// SPDX-License-Identifier: Apache-2.0

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:ejson_analyzer/ejson_analyzer.dart';

class TooManyAnnotatedConstructors extends AnalysisRule {
  static const LintCode code = LintCode('too_many_annotated_constructors', 'Only one constructor can be annotated', severity: DiagnosticSeverity.ERROR);

  TooManyAnnotatedConstructors() : super(name: 'too_many_annotated_constructors', description: 'Only one constructor can be annotated.');

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addClassDeclaration(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;

  _Visitor(this.rule);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final annotatedConstructors = node.body.members.whereType<ConstructorDeclaration>().where((ctor) {
      final element = ctor.declaredFragment?.element;
      return element != null && isEJsonAnnotated(element);
    });
    if (annotatedConstructors.length > 1) {
      for (final ctor in annotatedConstructors) {
        rule.reportAtToken(ctor.name ?? ctor.typeName?.token ?? ctor.beginToken);
      }
    }
  }
}
