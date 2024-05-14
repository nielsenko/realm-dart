import 'package:realm_macros/realm_macros.dart';

@RealmModel2()
class TestModel extends RealmObjectMacrosBase {
  int? _id;
}

void main() {
  var model = TestModel();
  model.id = 123;
  print(model.id);
}
