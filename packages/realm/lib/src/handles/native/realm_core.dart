// Copyright 2021 MongoDB, Inc.
// SPDX-License-Identifier: Apache-2.0

import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:realm/realm.dart';
import 'package:realm/src/handles/native/realm_bindings.dart';

import 'convert_native.dart';
import 'error_handling.dart';
import 'ffi.dart';
import 'realm_library.dart';
import 'scheduler_handle.dart';

import '../realm_core.dart' as intf;

const realmCore = RealmCore();

class RealmCore implements intf.RealmCore {
  const RealmCore();

  // For debugging
  @override
  int get threadId => realm_dart_get_thread_id();

  @override
  void deleteRealmFiles(String path) {
    using((arena) {
      final realmDeleted = arena<Bool>();
      realm_delete_files(path.toCharPtr(arena), realmDeleted).raiseLastErrorIfFalse();
    });
  }

  @override
  List<String> getAllCategoryNames() {
    return using((arena) {
      final count = realm_get_category_names(0, nullptr);
      final outValues = arena<Pointer<Char>>(count);
      realm_get_category_names(count, outValues);
      return [for (int i = 0; i < count; i++) outValues[i].cast<Utf8>().toDartString()];
    });
  }

  @override
  String getAppDirectory() {
    try {
      if (!isFlutterPlatform || Platform.environment.containsKey('FLUTTER_TEST')) {
        return Directory.current.absolute.path; // dart or flutter test
      }

      // Flutter from here on..

      if (Platform.isIOS) {
        return _getFilesPath();
      }

      if (Platform.isAndroid) {
        final files = Directory(path.join(Directory.systemTemp.parent.path, 'files'));
        files.createSync(recursive: true);
        return files.path;
      }

      if (Platform.isLinux) {
        final appSupportDir = Platform.environment['XDG_DATA_HOME'] ?? Platform.environment['HOME'] ?? Directory.current.absolute.path;
        return path.join(appSupportDir, ".local/share", _applicationName());
      }

      if (Platform.isMacOS) {
        final home = Platform.environment['HOME'] ?? Directory.current.absolute.path;
        final appSupport = path.join(home, 'Library', 'Application Support');
        if (home.contains('/Library/Containers/')) {
          return appSupport; // sandboxed: container-scoped per app
        }
        return path.join(appSupport, _bundleIdentifier() ?? _applicationName());
      }

      if (Platform.isWindows) {
        final appData = Platform.environment['APPDATA'] ?? Directory.current.absolute.path;
        return path.join(appData, _applicationName());
      }

      throw UnsupportedError("Platform ${Platform.operatingSystem} is not supported");
    } catch (e) {
      throw RealmException('Cannot get app directory. Error: $e');
    }
  }

  @override
  void loggerAttach() => realm_dart_attach_logger(schedulerHandle.sendPort.nativePort);

  @override
  void loggerDetach() => realm_dart_detach_logger(schedulerHandle.sendPort.nativePort);

  @override
  void logMessage(LogCategory category, LogLevel logLevel, String message) {
    ensureRealmInit();
    return using((arena) {
      realm_dart_log(logLevel.nativeLevel(), category.toString().toCharPtr(arena), message.toCharPtr(arena));
    });
  }

  @override
  void setLogLevel(LogLevel level, {required LogCategory category}) {
    ensureRealmInit();
    using((arena) {
      realm_set_log_level_category(category.toString().toCharPtr(arena), level.nativeLevel());
    });
  }

  /// The executable name doubles as the application name on desktop; the
  /// Flutter tool names the binary after the pubspec package name.
  String _applicationName() => path.basenameWithoutExtension(Platform.resolvedExecutable);

  /// The CFBundleIdentifier of the surrounding .app bundle, if any.
  String? _bundleIdentifier() {
    try {
      // <name>.app/Contents/MacOS/<exe> -> <name>.app/Contents/Info.plist
      final plist = path.join(File(Platform.resolvedExecutable).parent.parent.path, 'Info.plist');
      if (!File(plist).existsSync()) return null;
      final result = Process.runSync('defaults', ['read', path.withoutExtension(plist), 'CFBundleIdentifier']);
      if (result.exitCode != 0) return null;
      final id = (result.stdout as String).trim();
      return id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  String _getFilesPath() {
    return realm_dart_get_files_path().cast<Utf8>().toRealmDartString()!;
  }

  @override
  int setAndGetRLimit(int limit) {
    return using((arena) {
      final outLimit = arena<Long>();
      realm_dart_set_and_get_rlimit(limit, outLimit).raiseLastErrorIfFalse();
      return outLimit.value;
    });
  }

  @override
  bool checkIfRealmExists(String path) {
    return File(path).existsSync(); // TODO: Should this not check that file is an actual realm file?
  }
}

extension on LogLevel {
  realm_log_level nativeLevel() => switch (this) {
    LogLevel.all => realm_log_level.RLM_LOG_LEVEL_ALL,
    LogLevel.debug => realm_log_level.RLM_LOG_LEVEL_DEBUG,
    LogLevel.detail => realm_log_level.RLM_LOG_LEVEL_DETAIL,
    LogLevel.trace => realm_log_level.RLM_LOG_LEVEL_TRACE,
    LogLevel.info => realm_log_level.RLM_LOG_LEVEL_INFO,
    LogLevel.warn => realm_log_level.RLM_LOG_LEVEL_WARNING,
    LogLevel.error => realm_log_level.RLM_LOG_LEVEL_ERROR,
    LogLevel.fatal => realm_log_level.RLM_LOG_LEVEL_FATAL,
    LogLevel.off => realm_log_level.RLM_LOG_LEVEL_OFF,
  };
}
