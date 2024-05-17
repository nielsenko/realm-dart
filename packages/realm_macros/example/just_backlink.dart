import 'dart:core';
import 'package:realm_macros/backlink_macro.dart';

class Foo {
  @BacklinkMacro('owner')
  Iterable<int> get dogs => [1, 2, 3];
}

void main() {
  var foo = Foo();
  print(foo.dogs);
}
