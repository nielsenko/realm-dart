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

  // ignore: unused_element
  Person._(); // should be added by macro

  static final schema = () {
    RealmObjectBase.registerFactory(Person._);
    return SchemaObject(ObjectType.realmObject, Person, 'Person', [
      nameProperty.schema,
      ageProperty.schema,
    ]);
  }();
}

@RealmModelMacro()
class Dog extends RealmObjectMacrosBase {
  external Dog({required String name, Person? owner});

  // ignore: unused_element
  Dog._(); // should be added by macro

  static final schema = () {
    RealmObjectBase.registerFactory(Dog._);
    return SchemaObject(ObjectType.realmObject, Dog, 'Dog', [
      nameProperty.schema,
      ownerProperty.schema,
    ]);
  }();
}

void main() {
  var model = TestModel();
  model.id = 123;
  print(model.id);
  print(model);

  var person = Person(name: 'Kasper', age: 0x32);
  var dog = Dog(name: 'Sonja', owner: person);
  final realm = Realm(Configuration.inMemory([Person.schema]));
  realm.write(() {
    realm.add(person);
    ;
  });
  final person2 = realm.all<Person>().first;
  print(person2.name);

  Realm.shutdown(); // <-- needed not to hang
}
