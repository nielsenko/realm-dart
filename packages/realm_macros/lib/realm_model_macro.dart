import 'dart:async';

import 'package:collection/collection.dart';
import 'package:macros/macros.dart';
import 'package:realm_dart/realm.dart';

class Property<T extends Object> {
  final String name;
  const Property(this.name);
  T getValue(RealmObjectBase object) => RealmObjectBase.get<T>(object, name) as T;
  void setValue(RealmObjectBase object, T value) => RealmObjectBase.set<T>(object, name, value);
}

macro
class RealmModelMacro implements ClassDeclarationsMacro, ClassDefinitionMacro {
  const RealmModelMacro();

  @override
  FutureOr<void> buildDeclarationsForClass(ClassDeclaration clazz, MemberDeclarationBuilder builder) async {
    final ctors = await builder.constructorsOf(clazz);
    final unnamedCtor = ctors.firstWhereOrNull((ctor) => ctor.isUnnamed);
    if (unnamedCtor == null) {
      // TODO: Is unnamed even a requirement?
      builder.report(Diagnostic(DiagnosticMessage('no unnamed ctor'), Severity.error));
    } else {
      for (final param in unnamedCtor.parameters) {
        final type = param.type;
        final name = param.identifier.name;
        if (type is! NamedTypeAnnotation) {
          builder.report(Diagnostic(
            DiagnosticMessage('Parameter "$name" must have a type'),
            Severity.error,
            contextMessages: [],
          ));
          continue;
        }
        final typeCode = DeclarationCode.fromParts([
          type.code,
          if (!param.isRequired && !type.isNullable) '?',
        ]);

        final propertyType = await builder.typeDeclarationOf(
            // ignore: deprecated_member_use
            await builder.resolveIdentifier(
          Uri.parse('package:realm_macros/realm_model_macro.dart'),
          'Property',
        ));

        // Fly-weight property
        builder.declareInType(DeclarationCode.fromParts([
          'static const ',
          name,
          'Property = ',
          propertyType.identifier,
          '<',
          typeCode,
          ">('$name');",
        ]));

        // Setter
        builder.declareInType(DeclarationCode.fromParts([
          'set ',
          name,
          '(',
          typeCode,
          ' value) => ',
          name,
          'Property.setValue(this, value);',
        ]));

        // Getter
        builder.declareInType(DeclarationCode.fromParts([
          typeCode,
          ' get ',
          name,
          ' => ${name}Property.getValue(this);',
          '\n',
        ]));
      }
    }
  }

  @override
  FutureOr<void> buildDefinitionForClass(ClassDeclaration clazz, TypeDefinitionBuilder builder) async {
    final ctors = await builder.constructorsOf(clazz);
    final unnamedCtor = ctors.firstWhere((ctor) => ctor.isUnnamed);
    final ctorBuilder = await builder.buildConstructor(unnamedCtor.identifier);
    ctorBuilder.augment(
      body: FunctionBodyCode.fromParts([
        '{\n',
        for (final param in unnamedCtor.parameters)
          'this.${param.identifier.name} = ${param.identifier.name};\n',
        '}'
      ])
    );
  }
}

extension on ConstructorDeclaration {
  bool get isUnnamed => identifier.name.isEmpty;

  Iterable<FormalParameterDeclaration> get parameters sync* {
    yield* positionalParameters;
    yield* namedParameters;
  }
}
