import 'package:realm_macros/realm_macros.dart';
import 'package:realm_macros/realm_model_macro.dart';
//import augment 'serialized_augmentation.dart';

@RealmModel2()
class TestModel extends RealmObjectMacrosBase {
  int? _id;
//  String name;
}

@RealmModelMacro()
class Person extends RealmObjectMacrosBase {
  Person(
    int age, {
    required String name,
  });
}

void main() {
  var model = TestModel();
  model.id = 123;
  print(model.id);
  print(model);
}
