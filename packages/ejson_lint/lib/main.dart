import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/lints/mismatched_getter_type.dart';
import 'src/lints/missing_getter.dart';
import 'src/lints/too_many_annotated_constructors.dart';

final plugin = EJsonLintPlugin();

class EJsonLintPlugin extends Plugin {
  @override
  String get name => 'ejson_lint';

  @override
  void register(PluginRegistry registry) {
    registry.registerWarningRule(TooManyAnnotatedConstructors());
    registry.registerWarningRule(MissingGetter());
    registry.registerWarningRule(MismatchedGetterType());
  }
}
