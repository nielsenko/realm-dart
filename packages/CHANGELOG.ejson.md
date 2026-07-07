## vNext (TBD)

- **Breaking:** `ejson_lint` is now a native analyzer plugin (the new
  `analysis_server_plugin` based system, Dart >= 3.10) instead of a
  `custom_lint` plugin. Enable it with a top-level `plugins:` section in the
  `analysis_options.yaml` at the root of your package or workspace:
  ```yaml
  plugins:
    ejson_lint:
      path: <your checkout of this repo>/packages/ejson_lint
  ```
  and remove `custom_lint` from `dev_dependencies` and from
  `analyzer: plugins:`.
- Upgrade to analyzer 12.1 (13.x is blocked on
  [dart-lang/sdk#63538](https://github.com/dart-lang/sdk/issues/63538), which
  hangs the analysis server when loading plugins built against
  analysis_server_plugin 0.3.15+).

## 0.4.1

- Upgrade min Dart SDK to 3.6.0, update all dependencies to latest stable version, and tighten lower bounds.
- Avoid name conflict on `LinkCode`.

## 0.4.0

- `fromEJson<T>` now accepts a `defaultValue` argument that is returned if
  `null` is passed as `ejson`.
- `register<T>` takes an optional `superTypes` argument to specify the super
  types of `T` if needed.

## 0.3.1

- Update sane_uuid dependency to ^1.0.0 (compensate for breaking change)

## 0.3.0

- Rename `Key` class to `BsonKey` to avoid common conflict with flutter

## 0.2.0-pre.1

- First published version.

## 0.1.0

- Initial version.
