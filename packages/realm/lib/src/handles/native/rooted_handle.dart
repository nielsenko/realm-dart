// Copyright 2024 MongoDB, Inc.
// SPDX-License-Identifier: Apache-2.0

import 'dart:ffi';

import 'handle_base.dart';
import 'realm_handle.dart';

class FinalizationToken {
  final WeakReference<RealmHandle> root;
  final int id;

  FinalizationToken(RealmHandle handle, this.id) : root = WeakReference(handle);
}

final rootedHandleFinalizer = Finalizer<FinalizationToken>((token) {
  token.root.target?.removeChild(token.id);
});

abstract class RootedHandleBase<T extends NativeType> extends HandleBase<T> {
  final RealmHandle root;
  int? _id;

  bool get shouldRoot => root.isUnowned;

  RootedHandleBase(this.root, Pointer<T> pointer, int size) : super(pointer, size) {
    if (shouldRoot) {
      _id = root.addChild(this);
    }
  }

  @override
  void releaseCore() {
    if (_id != null) {
      root.removeChild(_id!);
    }
  }
}
