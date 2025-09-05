// Copyright 2024 MongoDB, Inc.
// SPDX-License-Identifier: Apache-2.0

// ignore_for_file: implementation_imports

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_visitor.dart';

class PseudoType implements DartType {
  @override
  final NullabilitySuffix nullabilitySuffix;
  final String _name;

  PseudoType(this._name, {this.nullabilitySuffix = NullabilitySuffix.none});

  @override
  R acceptWithArgument<R, A>(TypeVisitorWithArgument<R, A> visitor, A argument) => throw UnimplementedError();

  @override
  Element? get element => null;

  @override
  R accept<R>(TypeVisitor<R> visitor) {
    throw UnimplementedError();
  }

  @override
  InstantiatedTypeAliasElement? get alias => throw UnimplementedError();

  @override
  InterfaceType? asInstanceOf(InterfaceElement element) {
    throw UnimplementedError();
  }

  @override
  InterfaceType? asInstanceOf2(InterfaceElement element) {
    throw UnimplementedError();
  }

  @override
  Element? get element3 => throw UnimplementedError();

  @override
  DartType get extensionTypeErasure => throw UnimplementedError();

  @override
  String getDisplayString({bool withNullability = true}) {
    if (withNullability && nullabilitySuffix == NullabilitySuffix.question) {
      return '$_name?';
    }
    return _name;
  }

  @override
  bool get isBottom => false;

  @override
  bool get isDartAsyncFuture => false;

  @override
  bool get isDartAsyncFutureOr => false;

  @override
  bool get isDartAsyncStream => false;

  @override
  bool get isDartCoreBool => false;

  @override
  bool get isDartCoreDouble => false;

  @override
  bool get isDartCoreEnum => false;

  @override
  bool get isDartCoreFunction => false;

  @override
  bool get isDartCoreInt => false;

  @override
  bool get isDartCoreIterable => false;

  @override
  bool get isDartCoreList => false;

  @override
  bool get isDartCoreMap => false;

  @override
  bool get isDartCoreNull => false;

  @override
  bool get isDartCoreNum => false;

  @override
  bool get isDartCoreObject => false;

  @override
  bool get isDartCoreRecord => false;

  @override
  bool get isDartCoreSet => false;

  @override
  bool get isDartCoreString => false;

  @override
  bool get isDartCoreSymbol => false;

  @override
  bool get isDartCoreType => false;

  @override
  String? get name => _name;

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
