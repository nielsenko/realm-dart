import 'package:realm_dart/realm.dart';
import 'package:realm_macros/realm_macros.dart';

@RealmModel2()
class TestModel extends RealmObjectMacrosBase {
  final int id;
}

void main() {
  var model = TestModel(id: 1);
  print(model);
}
