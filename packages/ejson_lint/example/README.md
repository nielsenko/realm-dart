This project is used to test the lint rules of the ejson_lint analyzer plugin.

The `expect_lint` comments in `bin/example.dart` are verified by the test in
`../test/lints_test.dart`, which runs
```shell
dart analyze
```
on this package. The plugin is enabled by the `plugins` section in the
workspace root `analysis_options.yaml`.
