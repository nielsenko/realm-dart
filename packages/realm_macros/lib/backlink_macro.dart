// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:macros/macros.dart';
import 'package:realm_dart/realm.dart';
import 'package:realm_macros/realm_model_macro.dart'; // ignore: unused_import

import 'property.dart';
import 'utils.dart';

macro
class BacklinkMacro implements MethodDeclarationsMacro, MethodDefinitionMacro {
  final String fieldName;

  const BacklinkMacro(this.fieldName);

  @override
  FutureOr<void> buildDeclarationsForMethod(
    MethodDeclaration method,
    MemberDeclarationBuilder builder,
  ) async {
    if (method.isGetter) {
      final returnTypeAnnotation = method.returnType as NamedTypeAnnotation;
      // generic type arguments are currently ignored so 
      // builder.resolveByType<Iterable<RealmObjectBase>>() 
      // won't work as expected
      final iterableType = await builder.resolveByType<Iterable>();
      final returnType = await builder.resolve(returnTypeAnnotation.code);

      if (await returnType.isSubtypeOf(iterableType)) {
        // returnType is an Iterable<T> so get the T as a NamedTypeAnnotation
        final sourceTypeAnnotation = returnTypeAnnotation.typeArguments.first as NamedTypeAnnotation;
        final sourceType = await builder.resolve(sourceTypeAnnotation.code);

        if (await sourceType.isSubtypeOf(await builder.resolveByType<RealmObjectBase>())) {
          // now we know that returnType is a subtype of Iterable<RealmObjectBase>

          final sourceTypeDeclaration = await builder.typeDeclarationOf(sourceTypeAnnotation.identifier);
          final methods = await builder.methodsOf(sourceTypeDeclaration);
          final linkOriginProperty = methods.byName()[fieldName];
          if (linkOriginProperty != null && linkOriginProperty.isGetter) {
            // matching "fieldName" getter found on sourceType 🎉
            // Everything in place to add a Property<T> with a backlink SchemaProperty
            builder.declareInType(DeclarationCode.fromParts([
              'static const ',
              method.identifier.name,
              'Property = ',
              (await builder.typeAnnotationOf<Property>()).code,
              '<',
              returnTypeAnnotation.code,
              '>',
              '(',
              (await builder.typeAnnotationOf<SchemaProperty>()).code,
              '(',
              "'${method.identifier.name}', ",
              await builder.resolveIdentifier(
                Uri.parse('package:realm_macros/realm_model_macro.dart'),
                'realmPropertyTypeLinkingObjects',
              ),
              ", linkOriginProperty: '$fieldName'",
              ', collectionType: ',
              await builder.resolveIdentifier(
                Uri.parse('package:realm_macros/realm_model_macro.dart'),
                'realmCollectionTypeList',
              ),
              ", linkTarget: '",
              sourceTypeAnnotation.identifier.name,
              "'));\n",
            ]));
          }
        }
      }
    }
  }

  @override
  FutureOr<void> buildDefinitionForMethod(MethodDeclaration method, FunctionDefinitionBuilder builder) {
    builder.augment(FunctionBodyCode.fromParts([
      '=> ',
      method.identifier.name,
      'Property.getValue(this);'
    ]));
  }
}
