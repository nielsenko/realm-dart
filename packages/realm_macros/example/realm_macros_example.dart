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
    @PrimaryKey() // not working yet
    required String name,
  });

  @Backlink(#owner)
  Iterable<Dog> get dogs; // not working yet
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
  var dog = Dog(name: 'Sonja', owner: person);
  print(dog.owner!.name);
  print('${person.name} aged ${person.age}');
}
