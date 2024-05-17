// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:macros/macros.dart';
import 'package:realm_dart/realm.dart';

import 'property.dart'; // ignore: unused_import
import 'utils.dart';

macro class RealmModelMacro implements ClassDeclarationsMacro, ClassDefinitionMacro {
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

        final propertyType = await builder.typeDeclarationOfType<Property>();
        final schemaPropertyType =
            await builder.typeDeclarationOfType<SchemaProperty>();

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

    final schemaObjectId =
        await builder.resolveIdentifierByType<SchemaObject>();

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

    final realmObjectBaseMethods = (await builder
            .methodsOf(await builder.typeDeclarationOfType<RealmObjectBase>()))
        .byName();
    final getSchemaMethod = realmObjectBaseMethods['getSchema']!;

    builder.declareInType(DeclarationCode.fromParts([
      overrideCode,
      schemaObjectId,
      ' get objectSchema => ',
      getSchemaMethod.identifier,
      '(this) ?? schema;'
    ]));

    final freezeObjectMethod = realmObjectBaseMethods['freezeObject']!;
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

    final streamId = await builder.resolveIdentifierByType<Stream>();

    final realmObjectChangesId =
        await builder.resolveIdentifierByType<RealmObjectChanges>();

    final getChangesMethod = realmObjectBaseMethods['getChanges']!;
    final changesRetType = DeclarationCode.fromParts([
      streamId,
      '<',
      realmObjectChangesId,
      '<',
      clazz.identifier,
      '>>',
    ]);

    builder.declareInType(DeclarationCode.fromParts([
      overrideCode,
      changesRetType,
      ' get changes => ',
      getChangesMethod.identifier,
      '<',
      clazz.identifier,
      '>',
      '(this);'
    ]));

    final listId = await builder.resolveIdentifierByType<List>();
    final stringId = await builder.resolveIdentifierByType<String>();

    final getChangesForMethod = realmObjectBaseMethods['getChangesFor']!;
    builder.declareInType(DeclarationCode.fromParts([
      overrideCode,
      changesRetType,
      ' changesFor([',
      listId,
      '<',
      stringId,
      '>? keyPaths]) => ',
      getChangesForMethod.identifier,
      '<',
      clazz.identifier,
      '>',
      '(this, keyPaths);'
    ]));
  }

  @override
  FutureOr<void> buildDefinitionForClass(
      ClassDeclaration clazz, TypeDefinitionBuilder builder) async {
    final ctors = (await builder.constructorsOf(clazz)).byName();
    final methods = (await builder.methodsOf(clazz)).byName();

    final unnamedCtor = ctors['']!;
    final ctorBuilder = await builder.buildConstructor(unnamedCtor.identifier);
    ctorBuilder.augment(
        body: FunctionBodyCode.fromParts([
      '{\n',
      for (final param in unnamedCtor.parameters)
        'this.${param.identifier.name} = ${param.identifier.name};\n',
      '}'
    ]));

    final schemaGetter = methods['schema']!;
    final schemaGetterBuilder =
        await builder.buildMethod(schemaGetter.identifier);

    final realmObjectBaseMethods = (await builder
            .methodsOf(await builder.typeDeclarationOfType<RealmObjectBase>()))
        .byName();

    final registerFactoryMethod = realmObjectBaseMethods['registerFactory']!;
    final privateEmptyCtor = ctors['_']!;

    final schemaObjectId =
        await builder.resolveIdentifierByType<SchemaObject>();

    final objectTypeRealmObjectId = await builder.resolveIdentifier(
      Uri.parse('package:realm_macros/realm_model_macro.dart'),
      'objectTypeRealmObject',
    );

    final fields = await builder.fieldsOf(clazz);
    schemaGetterBuilder.augment(
      FunctionBodyCode.fromParts([
        '{\n',
        registerFactoryMethod.identifier,
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
        for (final f in fields.where((f) => f.hasStatic && f.hasConst && f.identifier.name.endsWith('Property')))
          '${f.identifier.name}.schema,',
        ']',
        ');\n',
        '}',
      ]),
    );
  }
}

extension on ConstructorDeclaration {
  bool get isUnnamed => identifier.name.isEmpty;
  Iterable<FormalParameterDeclaration> get parameters =>
      positionalParameters.followedBy(namedParameters);
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
const realmPropertyTypeLinkingObjects = RealmPropertyType.linkingObjects;

const realmCollectionTypeList = RealmCollectionType.list;
const realmCollectionTypeSet = RealmCollectionType.set;
const realmCollectionTypeMap = RealmCollectionType.map;

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

    final baseT = await introspector.resolveByType<RealmObjectBase?>();
    if (await t.isSubtypeOf(baseT)) {
      return await introspector.resolveIdentifier(
        Uri.parse('package:realm_macros/realm_model_macro.dart'),
        'realmPropertyTypeObject',
      );
    }
  }

  return null;
}
