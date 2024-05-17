// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:macros/macros.dart';
import 'package:realm_dart/realm.dart';

import 'property.dart';
import 'utils.dart';

macro class BacklinkMacro implements MethodDeclarationsMacro, MethodDefinitionMacro {
  final String fieldName;

  const BacklinkMacro(this.fieldName);

  @override
  FutureOr<void> buildDeclarationsForMethod(
      MethodDeclaration method, MemberDeclarationBuilder builder) async {
    if (method.isGetter) {
      final iterableType =
          await builder.resolveByType<Iterable>(Uri.parse('dart:core'));
      final returnType = await builder.resolve(method.returnType.code);
      if (await returnType.isSubtypeOf(iterableType)) {
        final propertyType = await builder.resolveByType<Property>(
            Uri.parse('package:realm_macros/realm_model_macro.dart'));
        final schemaPropertyType = await builder.resolveByType<SchemaProperty>(
            Uri.parse('package:realm_dart/src/realm_property.dart'));
        builder.declareInType(DeclarationCode.fromParts([
          'static const ',
          method.identifier.name,
          'Property = ',
          propertyType,
          '(',
          schemaPropertyType,
          '(',
          "'${method.identifier.name}', ",
          await builder.resolveIdentifier(
            Uri.parse('package:realm_macros/realm_model_macro.dart'),
            'realmPropertyTypeLinkingObjects',
          ),
          ", linkOriginProperty: '$fieldName', ",
          ', collectionType: ',
          await builder.resolveIdentifier(
            Uri.parse('package:realm_macros/realm_model_macro.dart'),
            'realmCollectionTypeList',
          ),
          ", linkTarget: 'Source'",
          '));\n',
        ]));
      }
    }
  }

  @override
  FutureOr<void> buildDefinitionForMethod(
      MethodDeclaration method, FunctionDefinitionBuilder builder) {
    // TODO: implement buildDefinitionForMethod
    throw UnimplementedError();
  }
}
