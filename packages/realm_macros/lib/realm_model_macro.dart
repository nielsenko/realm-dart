import 'dart:async';

import 'package:collection/collection.dart';
import 'package:macros/macros.dart';
import 'package:realm_dart/realm.dart';

class Property<T extends Object> {
  final SchemaProperty schema;

  const Property(this.schema);

  String get name => schema.name;
  Type get type => T;

  T getValue(RealmObjectBase object) =>
      RealmObjectBase.get<T>(object, name) as T;
  void setValue(RealmObjectBase object, T value) =>
      RealmObjectBase.set<T>(object, name, value);
}

macro class RealmModelMacro
    implements ClassDeclarationsMacro, ClassDefinitionMacro {
  const RealmModelMacro();

  @override
  FutureOr<void> buildDeclarationsForClass(
      ClassDeclaration clazz, MemberDeclarationBuilder builder) async {
    final ctors = await builder.constructorsOf(clazz);
    final unnamedCtor = ctors.firstWhereOrNull((ctor) => ctor.isUnnamed);
    if (unnamedCtor == null) {
      // TODO: Is unnamed even a requirement?
      builder.report(
          Diagnostic(DiagnosticMessage('no unnamed ctor'), Severity.error));
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
        final schemaPropertyType = await builder.typeDeclarationOf(
            // ignore: deprecated_member_use
            await builder.resolveIdentifier(
          Uri.parse('package:realm_dart/src/realm_property.dart'),
          'SchemaProperty',
        ));

        // TODO: support collections
        final realmPropertyType = await realmPropertyTypeOf(
            builder, await builder.resolve(type.code));
        if (realmPropertyType == null) {
          builder.report(Diagnostic(
            DiagnosticMessage('Unsupported realm property type for "$name"'),
            Severity.error,
          ));
          continue;
        }

        // Fly-weight property
        builder.declareInType(DeclarationCode.fromParts([
          'static const ',
          name,
          'Property = ',
          propertyType.identifier,
          '<',
          typeCode,
          '>(',
          schemaPropertyType.identifier,
          "('$name', ",
          realmPropertyType,
          '));',
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
  FutureOr<void> buildDefinitionForClass(
      ClassDeclaration clazz, TypeDefinitionBuilder builder) async {
    final ctors = await builder.constructorsOf(clazz);
    final unnamedCtor = ctors.firstWhere((ctor) => ctor.isUnnamed);
    final ctorBuilder = await builder.buildConstructor(unnamedCtor.identifier);
    ctorBuilder.augment(
        body: FunctionBodyCode.fromParts([
      '{\n',
      for (final param in unnamedCtor.parameters)
        'this.${param.identifier.name} = ${param.identifier.name};\n',
      '}'
    ]));
  }
}

extension on ConstructorDeclaration {
  bool get isUnnamed => identifier.name.isEmpty;

  Iterable<FormalParameterDeclaration> get parameters sync* {
    yield* positionalParameters;
    yield* namedParameters;
  }
}

Future<Identifier?> realmPropertyTypeOf(
    DeclarationPhaseIntrospector introspector, StaticType t) async {
  final enumValues =
      await introspector.fieldsOf(await introspector.typeDeclarationOf(
          // ignore: deprecated_member_use
          await introspector.resolveIdentifier(
    Uri.parse('package:realm_common/src/realm_types.dart'),
    'RealmPropertyType',
  )));

  List<({String lib, String dartType, String realmType})> mappings = [
    (lib: 'dart:core', dartType: 'int', realmType: 'int'),
    (lib: 'dart:core', dartType: 'double', realmType: 'double'),
    (lib: 'dart:core', dartType: 'bool', realmType: 'bool'),
    (lib: 'dart:core', dartType: 'String', realmType: 'string'),
    (lib: 'dart:core', dartType: 'DateTime', realmType: 'timestamp'),
    (lib: 'dart:typed_data', dartType: 'Uint8List', realmType: 'binary'),
    (
      lib: 'package:objectid/src/objectid/objectid.dart',
      dartType: 'ObjectId',
      realmType: 'objectid'
    ),
    (
      lib: 'package:realm_common/src/realm_types.dart',
      dartType: 'RealmValue',
      realmType: 'mixed'
    ),
    (
      lib: 'package:realm_common/src/realm_types.dart',
      dartType: 'Decimal128',
      realmType: 'decimal128'
    ),
    (
      lib: 'package:realm_dart/src/realm_object.dart',
      dartType: 'RealmObject',
      realmType: 'object'
    ),
    (
      lib: 'package:sane_uuid/src/uuid_base.dart',
      dartType: 'Uuid',
      realmType: 'uuid'
    ),
  ];
  for (final mapping in mappings) {
    final maybeT = await introspector.resolve(NamedTypeAnnotationCode(
        // ignore: deprecated_member_use
        name: await introspector.resolveIdentifier(
            Uri.parse(mapping.lib), mapping.dartType)));
    if (await t.isExactly(maybeT)) {
      return enumValues
          .firstWhere((e) => e.identifier.name == mapping.realmType)
          .identifier;
    }
  }

  return null;
}
