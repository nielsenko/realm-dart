// Copyright 2024 MongoDB, Inc.
// SPDX-License-Identifier: Apache-2.0

import 'dart:ffi';

import 'package:ejson/ejson.dart';
import 'package:type_plus/type_plus.dart';

import '../../realm_class.dart';
import 'decimal128.dart' as impl;
import 'ffi.dart';
import 'realm_bindings.dart';

const bugInTheSdkMessage = "This is likely a bug in the Realm SDK - please file an issue at https://github.com/realm/realm-dart/issues";

// stamped into the library by the build system (see prepare-release.yml)
const libraryVersion = '20.2.0';

bool _initialized = false;

/// Idempotent one-time initialization of the native side: EJSON codecs,
/// the package-vs-native version handshake, the Dart API dynamic linking
/// and the debug logger.
///
/// The native library itself is located and loaded by the Dart/Flutter
/// native-assets machinery - the bindings are `@Native` externals bound
/// to the code asset built by hook/build.dart.
void ensureRealmInit() {
  if (_initialized) return;
  _initialized = true;

  register<impl.Decimal128>(encodeDecimal128, decodeDecimal128, superTypes: [Decimal128]);
  register<Decimal128>(encodeDecimal128, decodeDecimal128);
  register(encodeRealmValue, decodeRealmValue);

  final nativeLibraryVersion = realm_dart_library_version().cast<Utf8>().toDartString();
  if (libraryVersion != nativeLibraryVersion) {
    throw RealmError('Realm SDK package version does not match the native library version ($libraryVersion != $nativeLibraryVersion). $bugInTheSdkMessage');
  }

  realm_dart_initializeDartApiDL(NativeApi.initializeApiDLData);

  realm_dart_init_debug_logger();
}

EJsonValue encodeDecimal128(Decimal128 value) => {'\$numberDecimal': value.toString()};

impl.Decimal128 decodeDecimal128(EJsonValue ejson) => switch (ejson) {
  {'\$numberDecimal': String x} => impl.Decimal128.parse(x),
  _ => raiseInvalidEJson(ejson),
};

EJsonValue encodeRealmValue(RealmValue value) {
  final v = value.value;
  if (v is RealmObject) {
    final p = RealmObjectBase.get(v, v.objectSchema.primaryKey!.name);
    return DBRef(v.objectSchema.name, p).toEJson();
  }
  return toEJson(v);
}

RealmValue decodeRealmValue(EJsonValue ejson) {
  final decoded = fromEJson<dynamic>(ejson);
  if (decoded is DBRef) {
    final t = TypePlus.fromId(decoded.collection);
    final o = RealmObjectBase.createObject(t, null);
    o.dynamic.set(o.objectSchema.primaryKey!.name, decoded.id);
    return RealmValue.realmObject(o.cast());
  }
  return RealmValue.from(decoded);
}

extension<T> on T {
  U cast<U>() => this as U;
}
