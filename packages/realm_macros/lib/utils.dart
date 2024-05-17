// ignore_for_file: deprecated_member_use

import 'package:macros/macros.dart';
import 'package:realm_dart/realm.dart';
import 'package:realm_macros/property.dart';

final _typeToUri = <Type, Uri>{
  typeOf<Property?>(): Uri.parse('package:realm_macros/property.dart'),
  typeOf<RealmObjectBase?>(): Uri.parse('package:realm_dart/src/realm_object.dart'),
  typeOf<RealmObjectChanges?>(): Uri.parse('package:realm_dart/src/realm_object.dart'),
  typeOf<SchemaObject?>(): Uri.parse('package:realm_dart/src/configuration.dart'),
  typeOf<SchemaProperty?>(): Uri.parse('package:realm_dart/src/realm_property.dart'),
  typeOf<Stream?>(): Uri.parse('dart:async'),
};

final _dartCore = Uri.parse('dart:core');

Uri uriOf<T>() => _typeToUri[nullableOf<T>()] ?? _dartCore;

Type typeOf<T>() => T;

Type nullableOf<T>() => typeOf<T?>();

bool isNullable<T>() => null is T;

extension DeclarationPhaseIntrospectorEx on DeclarationPhaseIntrospector {
  Future<StaticType> resolveByType<T>([Uri? uri]) async {
    final identifier = await resolveIdentifierByType<T>(uri);
    var typeCode = NamedTypeAnnotationCode(name: identifier);
    return resolve(isNullable<T>() ? typeCode.asNullable : typeCode);
  }

  Future<TypeAnnotation> typeAnnotationOf<T>([Uri? uri]) async {
    var identifier = await resolveIdentifierByType<T>(uri);
    return NamedTypeAnnotationCode(name: identifier);
  }

  Future<TypeDeclaration> typeDeclarationOfType<T>([Uri? uri]) async {
    var identifier = await resolveIdentifierByType<T>(uri);
    return await typeDeclarationOf(identifier);
  }

  Future<TypeDeclaration> typeDeclarationOfExpression<T>(T Function() exp, [Uri? uri]) => typeDeclarationOfType<T>(uri);
}

extension TypePhaseIntrospectorEx on TypePhaseIntrospector {
  Future<Identifier> resolveIdentifierByType<T>([Uri? uri]) async {
    uri ??= uriOf<T>();
    var typeString = T.toString();
    var end = typeString.indexOf('<');
    if (end < 0) end = typeString.indexOf('?');
    if (end >= 0) typeString = typeString.substring(0, end);
    return await resolveIdentifier(uri, typeString);
  }
}

extension BuilderEx on Builder {
  void debug(String message) {
    report(Diagnostic(DiagnosticMessage(message), Severity.info));
  }
}

extension IterableEx<T extends Declaration> on Iterable<T> {
  Map<String, T> byName() => {for (final t in this) t.identifier.name: t};
}
