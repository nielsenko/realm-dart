import 'dart:core';
import 'package:realm_macros/backlink_macro.dart';

class Foo {
  @BacklinkMacro('owner')
  Iterable<int> get dogs => [1, 2, 3];
}

void main() {
  var foo = Foo();

  final schema = Foo.dogsProperty.schema;
  print('name               : ${schema.name}');
  print('propertyType       : ${schema.propertyType}');
  print('optional           : ${schema.optional}');
  print('mapTo              : ${schema.mapTo}');
  print('primaryKey         : ${schema.primaryKey}');
  print('indexType          : ${schema.indexType}');
  print('linkTarget         : ${schema.linkTarget}');
  print('linkOriginProperty : ${schema.linkOriginProperty}');
  print('collectionType     : ${schema.collectionType}');

  print(foo.dogs);
}
