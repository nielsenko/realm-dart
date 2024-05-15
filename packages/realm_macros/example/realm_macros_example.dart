import 'package:realm_dart/realm.dart';
import 'package:realm_macros/realm_macros.dart';
import 'package:realm_macros/realm_model_macro.dart';

@RealmModel2()
class TestModel extends RealmObjectMacrosBase {
  int? _id;
//  String name;
}

class PersonManual extends RealmObjectMacrosBase {
  static const nameProperty = Property<String>(
    SchemaProperty(
      'name',
      RealmPropertyType.string,
    ),
  );
  String get name => nameProperty.getValue(this);
  set name(String value) => nameProperty.setValue(this, value);

  static const ageProperty = Property<int>(
    SchemaProperty(
      'age',
      RealmPropertyType.int,
    ),
  );
  int get age => ageProperty.getValue(this);
  set age(int value) => ageProperty.setValue(this, value);

  static final schema = () {
    RealmObjectBase.registerFactory(PersonManual._);
    return SchemaObject(
      ObjectType.realmObject,
      PersonManual,
      'Person',
      [
        nameProperty.schema,
        ageProperty.schema,
      ],
    );
  }();

  @override
  SchemaObject get objectSchema => RealmObjectBase.getSchema(this) ?? schema;

  PersonManual({required String name, required int age}) {
    this.name = name;
    this.age = age;
  }

  PersonManual._();
}

//@RealmModelMacro()
class Person extends RealmObjectMacrosBase {
  external Person({
    @MapTo('alder') @PrimaryKey() required int age,
    required String name,
  });
}

void main() {
  var model = TestModel();
  model.id = 123;
  print(model.id);
  print(model);

  final realm = Realm(Configuration.inMemory([PersonManual.schema]));
  realm.write(() {
    realm.add(PersonManual(
      name: 'Kasper',
      age: 0x32,
    ));
  });

  final person = realm.all<PersonManual>().first;
  print('${person.name} aged ${person.age}');

  Realm.shutdown();
}
