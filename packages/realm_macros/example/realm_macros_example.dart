import 'package:realm_dart/realm.dart';
import 'package:realm_macros/realm_macros.dart';
import 'package:realm_macros/realm_model_macro.dart';

@RealmModel2()
class TestModel extends RealmObjectMacrosBase {
  int? _id;
//  String name;
}

@RealmModelMacro()
class Person extends RealmObjectMacrosBase {
  external Person({
    required int age,
    required String name,
    // List<Dog> dogs,
  });
}

@RealmModelMacro()
class Dog extends RealmObjectMacrosBase {
  external Dog({required String name, Person? owner});
}

void main() {
  var model = TestModel();
  model.id = 123;
  print(model.id);
  print(model);

  var person = Person(name: 'Kasper', age: 0x32);
  print('${person.name} aged ${person.age}');
}
