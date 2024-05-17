// ignore_for_file: deprecated_member_use

import 'package:macros/macros.dart';

bool isNullable<T>() => null is T;

extension DeclarationPhaseIntrospectorEx on DeclarationPhaseIntrospector {
  Future<StaticType> resolveByType<T>(Uri uri) async {
    final identifier = await resolveIdentifierByType<T>(uri);
    var typeCode = NamedTypeAnnotationCode(name: identifier);
    return resolve(isNullable<T>() ? typeCode.asNullable : typeCode);
  }

  Future<TypeAnnotation> typeAnnotationOf<T>(Uri uri) async {
    var identifier = await resolveIdentifierByType<T>(uri);
    return NamedTypeAnnotationCode(name: identifier);
  }

  Future<TypeDeclaration> typeDeclarationOfType<T>(Uri uri) async {
    var identifier = await resolveIdentifierByType<T>(uri);
    return await typeDeclarationOf(identifier);
  }

  Future<TypeDeclaration> typeDeclarationOfExpression<T>(T Function() exp, Uri uri) 
    => typeDeclarationOfType<T>(uri);
}

extension TypePhaseIntrospectorEx on TypePhaseIntrospector {
  Future<Identifier> resolveIdentifierByType<T>(Uri uri) async {
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
