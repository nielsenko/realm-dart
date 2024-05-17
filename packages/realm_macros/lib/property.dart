import 'package:realm_dart/realm.dart';

class Property<T> {
  final SchemaProperty schema;

  const Property(this.schema);

  String get name => schema.name;
  Type get type => T;

  T getValue(RealmObjectBase object) => RealmObjectBase.get<T>(object, name) as T;
  void setValue(RealmObjectBase object, T value) => RealmObjectBase.set<T>(object, name, value);
}
