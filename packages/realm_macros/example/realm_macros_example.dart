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
    @MapTo('alder') @PrimaryKey() required int age,
    required String name,
  });

  Person.foo() : this(name: 'John', age: 20);

  Person.bar() {
    name = 'Kiro';
    age = 35;
  }
}

void main() {
  var model = TestModel();
  model.id = 123;
  print(model.id);
  print(model);

  var person = Person.bar();
  print('${person.name} aged ${person.age}');
}
