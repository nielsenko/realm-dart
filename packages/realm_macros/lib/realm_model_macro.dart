// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:macros/macros.dart';
import 'package:realm_dart/realm.dart';

class Property<T> {
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

        final propertyType =
            await builder.typeDeclarationOf(await builder.resolveIdentifier(
          Uri.parse('package:realm_macros/realm_model_macro.dart'),
          'Property',
        ));
        final schemaPropertyType =
            await builder.typeDeclarationOf(await builder.resolveIdentifier(
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
          if (type.isNullable) ', optional: true',
          if (realmPropertyType.name == 'realmPropertyTypeObject')
            ", linkTarget: '${type.identifier.name}'",
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

    // add a private empty ctor to be used by RealmObjectBase.registerFactory
    builder.declareInType(
        DeclarationCode.fromParts([clazz.identifier.name, '._();']));

    final schemaObjectId = await builder.resolveIdentifier(
        Uri.parse('package:realm_dart/src/configuration.dart'), 'SchemaObject');

    // TODO: change this to a static variable computed at initialization
    // once augmenting variable declarations is supported
    // https://github.com/dart-lang/sdk/issues/44748
    builder.declareInType(DeclarationCode.fromParts(
        ['external static ', schemaObjectId, ' get schema;']));

    final overrideCode = DeclarationCode.fromParts([
      '@',
      await builder.resolveIdentifier(Uri.parse('dart:core'), 'override'),
      '\n',
    ]);

    final realmObjectBaseMethods = await builder.methodsOf(
        await builder.typeDeclarationOf(await builder.resolveIdentifier(
            Uri.parse('package:realm_dart/src/realm_object.dart'),
            'RealmObjectBase')));
    final getSchemaMethod = realmObjectBaseMethods
        .firstWhere((m) => m.identifier.name == 'getSchema');

    builder.declareInType(DeclarationCode.fromParts([
      overrideCode,
      schemaObjectId,
      ' get objectSchema => ',
      getSchemaMethod.identifier,
      '(this) ?? schema;'
    ]));

    final freezeObjectMethod = realmObjectBaseMethods
        .firstWhere((m) => m.identifier.name == 'freezeObject');

    builder.declareInType(DeclarationCode.fromParts([
      overrideCode,
      clazz.identifier,
      ' freeze() => ',
      freezeObjectMethod.identifier,
      '<',
      clazz.identifier,
      '>',
      '(this);'
    ]));

    final streamId =
        await builder.resolveIdentifier(Uri.parse('dart:async'), 'Stream');

    final realmObjectChangesId = await builder.resolveIdentifier(
        Uri.parse('package:realm_dart/src/realm_object.dart'),
        'RealmObjectChanges');

    final getChangesMethod = realmObjectBaseMethods
        .firstWhere((m) => m.identifier.name == 'getChanges');

    builder.declareInType(DeclarationCode.fromParts([
      overrideCode,
      streamId,
      '<',
      realmObjectChangesId,
      '<',
      clazz.identifier,
      '>> get changes => ',
      getChangesMethod.identifier,
      '<',
      clazz.identifier,
      '>',
      '(this);'
    ]));
  }

  @override
  FutureOr<void> buildDefinitionForClass(
      ClassDeclaration clazz, TypeDefinitionBuilder builder) async {
    final ctors = await builder.constructorsOf(clazz);
    final methods = await builder.methodsOf(clazz);

    final unnamedCtor = ctors.firstWhere((ctor) => ctor.isUnnamed);
    final ctorBuilder = await builder.buildConstructor(unnamedCtor.identifier);
    ctorBuilder.augment(
        body: FunctionBodyCode.fromParts([
      '{\n',
      for (final param in unnamedCtor.parameters)
        'this.${param.identifier.name} = ${param.identifier.name};\n',
      '}'
    ]));

    final schemaGetter =
        methods.firstWhere((method) => method.identifier.name == 'schema');
    final schemaGetterBuilder =
        await builder.buildMethod(schemaGetter.identifier);

    final realmObjectBaseMethods = await builder.methodsOf(
        await builder.typeDeclarationOf(await builder.resolveIdentifier(
            Uri.parse('package:realm_dart/src/realm_object.dart'),
            'RealmObjectBase')));

    final registerFactoryMethod = realmObjectBaseMethods
        .firstWhere((m) => m.identifier.name == 'registerFactory')
        .identifier;

    final privateEmptyCtor =
        ctors.firstWhere((ctor) => ctor.identifier.name == '_');

    final schemaObjectId = await builder.resolveIdentifier(
        Uri.parse('package:realm_dart/src/configuration.dart'), 'SchemaObject');

    final objectTypeRealmObjectId = await builder.resolveIdentifier(
      Uri.parse('package:realm_macros/realm_model_macro.dart'),
      'objectTypeRealmObject',
    );

    schemaGetterBuilder.augment(
      FunctionBodyCode.fromParts([
        '{\n',
        registerFactoryMethod,
        '(',
        privateEmptyCtor.identifier,
        ');\n',
        'return ',
        schemaObjectId,
        '(',
        objectTypeRealmObjectId,
        ', ',
        clazz.identifier,
        ", '${clazz.identifier.name}', ",
        '[',
        for (final param in unnamedCtor.parameters)
          '${param.identifier.name}Property.schema,',
        ']',
        ');\n',
        '}',
      ]),
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

const objectTypeRealmObject = ObjectType.realmObject;
const realmPropertyTypeInt = RealmPropertyType.int;
const realmPropertyTypeDouble = RealmPropertyType.double;
const realmPropertyTypeBool = RealmPropertyType.bool;
const realmPropertyTypeString = RealmPropertyType.string;
const realmPropertyTypeTimestamp = RealmPropertyType.timestamp;
const realmPropertyTypeBinary = RealmPropertyType.binary;
const realmPropertyTypeObjectid = RealmPropertyType.objectid;
const realmPropertyTypeMixed = RealmPropertyType.mixed;
const realmPropertyTypeDecimal128 = RealmPropertyType.decimal128;
const realmPropertyTypeObject = RealmPropertyType.object;
const realmPropertyTypeUuid = RealmPropertyType.uuid;

Future<Identifier?> realmPropertyTypeOf(
    DeclarationPhaseIntrospector introspector, StaticType t) async {
  List<({String lib, String dartType, String realmType})> mappings = [
    (lib: 'dart:core', dartType: 'int', realmType: 'realmPropertyTypeInt'),
    (
      lib: 'dart:core',
      dartType: 'double',
      realmType: 'realmPropertyTypeDouble'
    ),
    (lib: 'dart:core', dartType: 'bool', realmType: 'realmPropertyTypeBool'),
    (
      lib: 'dart:core',
      dartType: 'String',
      realmType: 'realmPropertyTypeString'
    ),
    (
      lib: 'dart:core',
      dartType: 'DateTime',
      realmType: 'realmPropertyTypeTimestamp'
    ),
    (
      lib: 'dart:typed_data',
      dartType: 'Uint8List',
      realmType: 'realmPropertyTypeBinary'
    ),
    (
      lib: 'package:objectid/src/objectid/objectid.dart',
      dartType: 'ObjectId',
      realmType: 'realmPropertyTypeObjectid'
    ),
    (
      lib: 'package:realm_common/src/realm_types.dart',
      dartType: 'RealmValue',
      realmType: 'realmPropertyTypeMixed'
    ),
    (
      lib: 'package:realm_common/src/realm_types.dart',
      dartType: 'Decimal128',
      realmType: 'realmPropertyTypeDecimal128'
    ),
    (
      lib: 'package:realm_dart/src/realm_object.dart',
      dartType: 'RealmObject',
      realmType: 'realmPropertyTypeObject'
    ),
    (
      lib: 'package:sane_uuid/src/uuid_base.dart',
      dartType: 'Uuid',
      realmType: 'realmPropertyTypeUuid'
    ),
  ];
  for (final mapping in mappings) {
    final maybeT = await introspector.resolve(NamedTypeAnnotationCode(
        name: await introspector.resolveIdentifier(
            Uri.parse(mapping.lib), mapping.dartType)));
    if (await t.isExactly(maybeT)) {
      return await introspector.resolveIdentifier(
        Uri.parse('package:realm_macros/realm_model_macro.dart'),
        mapping.realmType,
      );
    }

    final baseT = await introspector.resolveType<RealmObjectBase?>(
        Uri.parse('package:realm_dart/src/realm_object.dart'));
    if (await t.isSubtypeOf(baseT)) {
      return await introspector.resolveIdentifier(
        Uri.parse('package:realm_macros/realm_model_macro.dart'),
        'realmPropertyTypeObject',
      );
    }
  }

  return null;
}

bool isNullable<T>() => null is T;

extension on DeclarationPhaseIntrospector {
  Future<StaticType> resolveType<T>(Uri uri) async {
    var typeString = T.toString();
    if (isNullable<T>())
      typeString = typeString.substring(0, typeString.length - 1);

    final identifier = await resolveIdentifier(uri, typeString);
    var typeCode = NamedTypeAnnotationCode(name: identifier);
    return resolve(isNullable<T>() ? typeCode.asNullable : typeCode);
  }
}

extension on Builder {
  void debug(String message) {
    report(Diagnostic(DiagnosticMessage(message), Severity.info));
  }
}
