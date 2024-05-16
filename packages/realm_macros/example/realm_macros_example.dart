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
    Person? spouse,
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

  final kasper = Person(name: 'Kasper', age: 0x32);
  final ann = Person(name: 'Ann', age: 0x32, spouse: kasper);
  kasper.spouse = ann;
  var sonja = Dog(name: 'Sonja', owner: kasper);
  final realm = Realm(Configuration.inMemory([kasper.objectSchema, sonja.objectSchema]));
  realm.write(() {
    realm.add(sonja);
  });
  // stored a dog, but by transitive closure also two persons
  for (final p in realm.all<Person>()) {
    print('${p.name} is ${p.age} years old');
  }

  Realm.shutdown(); // <-- needed not to hang
}
