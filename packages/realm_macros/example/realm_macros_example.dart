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

  // ignore: unused_element
  Person._(); // should be added by macro

  // should be added by macro
  static final schema = () {
    RealmObjectBase.registerFactory(Person._);
    return SchemaObject(ObjectType.realmObject, Person, 'Person', [
      nameProperty.schema,
      ageProperty.schema,
      // spouseProperty.schema,
      SchemaProperty('spouse', RealmPropertyType.object, optional: true, linkTarget: 'Person'),
    ]);
  }();
}

@RealmModelMacro()
class Dog extends RealmObjectMacrosBase {
  external Dog({required String name, Person? owner});

  // ignore: unused_element
  Dog._(); // should be added by macro

  // should be added by macro
  static final schema = () {
    RealmObjectBase.registerFactory(Dog._);
    return SchemaObject(ObjectType.realmObject, Dog, 'Dog', [
      nameProperty.schema,
      // ownerProperty.schema,
      SchemaProperty('owner', RealmPropertyType.object, linkTarget: 'Person', optional: true),
    ]);
  }();
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
  final realm = Realm(Configuration.inMemory([Person.schema, Dog.schema]));
  realm.write(() {
    realm.add(sonja);
  });
  // stored a dog, but by transitive closure also two persons
  for (final p in realm.all<Person>()) {
    print('${p.name} is ${p.age} years old');
  }

  Realm.shutdown(); // <-- needed not to hang
}
