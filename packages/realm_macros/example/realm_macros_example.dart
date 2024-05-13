//import 'package:macros/macros.dart';
import 'package:realm_macros/realm_macros.dart';

@RealmModel2()
class TestModel {
  final int id;
}

void main() {
  var model = TestModel(id: 1);
  print(model);
}
