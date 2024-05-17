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

    final realmObjectBaseMethods = (await builder.methodsOf(
            await builder.typeDeclarationOf(await builder.resolveIdentifier(
                Uri.parse('package:realm_dart/src/realm_object.dart'),
                'RealmObjectBase'))))
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

    final streamId =
        await builder.resolveIdentifier(Uri.parse('dart:async'), 'Stream');

    final realmObjectChangesId = await builder.resolveIdentifier(
        Uri.parse('package:realm_dart/src/realm_object.dart'),
        'RealmObjectChanges');

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

    final listId =
        await builder.resolveIdentifier(Uri.parse('dart:core'), 'List');
    final stringId =
        await builder.resolveIdentifier(Uri.parse('dart:core'), 'String');

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

    final realmObjectBaseMethods = (await builder.methodsOf(
            await builder.typeDeclarationOf(await builder.resolveIdentifier(
                Uri.parse('package:realm_dart/src/realm_object.dart'),
                'RealmObjectBase'))))
        .byName();

    final registerFactoryMethod = realmObjectBaseMethods['registerFactory']!;
    final privateEmptyCtor = ctors['_']!;

    final schemaObjectId = await builder.resolveIdentifier(
        Uri.parse('package:realm_dart/src/configuration.dart'), 'SchemaObject');

    final objectTypeRealmObjectId = await builder.resolveIdentifier(
      Uri.parse('package:realm_macros/realm_model_macro.dart'),
      'objectTypeRealmObject',
    );

    // final backlinkId = await builder.resolveIdentifierByType<Backlink>(Uri.parse('package:realm_common/src/realm_common_base.dart'));
    // for (final m in methods) {
    //   if (m.metadata.any((a) => a is IdentifierMetadataAnnotation && a.identifier == backlinkId)) {
    //     throw ArgumentError('Backlink not supported yet');
    //   }
    // }

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

    final baseT = await introspector.resolveByType<RealmObjectBase?>(
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
  Future<StaticType> resolveByType<T>(Uri uri) async {
    final identifier = await resolveIdentifierByType<T>(uri);
    var typeCode = NamedTypeAnnotationCode(name: identifier);
    return resolve(isNullable<T>() ? typeCode.asNullable : typeCode);
  }
}

extension on TypePhaseIntrospector {
  Future<Identifier> resolveIdentifierByType<T>(Uri uri) async {
    var typeString = T.toString();
    if (isNullable<T>())
      typeString = typeString.substring(0, typeString.length - 1);
    return await resolveIdentifier(uri, typeString);
  }
}

extension on Builder {
  void debug(String message) {
    report(Diagnostic(DiagnosticMessage(message), Severity.info));
  }
}

extension<T extends Declaration> on Iterable<T> {
  Map<String, T> byName() => {for (final t in this) t.identifier.name: t};
}
