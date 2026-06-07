import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final code = input.config.code;
    final packageRoot = input.packageRoot;
    final zigTarget = _zigTarget(code);
    final libName = _libName(code.targetOS);

    final prefix = Directory.fromUri(input.outputDirectory.resolve('zig/'));
    await prefix.create(recursive: true);

    await _zigBuild(packageRoot: packageRoot, zigTarget: zigTarget, code: code, installPrefix: prefix.path);

    // zig installs shared libraries to lib/ (bin/ for Windows DLLs).
    final subdir = code.targetOS == OS.windows ? 'bin' : 'lib';
    final builtLib = File.fromUri(prefix.uri.resolve('$subdir/$libName'));
    if (!builtLib.existsSync()) {
      throw Exception('zig build succeeded but ${builtLib.path} is missing');
    }

    // Keep the legacy loader working for plain Dart on the host.
    if (code.targetOS == OS.current && code.targetArchitecture == Architecture.current) {
      final legacyDir = Directory.fromUri(packageRoot.resolve('binary/${code.targetOS.name.toLowerCase()}/'));
      await legacyDir.create(recursive: true);
      await builtLib.copy('${legacyDir.path}/$libName');
    }

    output.assets.code.add(CodeAsset(package: input.packageName, name: 'realm_dart.dart', linkMode: DynamicLoadingBundled(), file: builtLib.uri));
  });
}

String _zigTarget(CodeConfig code) {
  final arch = code.targetArchitecture;
  final cpu = switch (arch) {
    Architecture.x64 => 'x86_64',
    Architecture.arm64 => 'aarch64',
    Architecture.arm => 'arm',
    _ => throw UnsupportedError('Unsupported architecture: $arch'),
  };
  return switch (code.targetOS) {
    OS.macOS => '$cpu-macos',
    OS.linux => '$cpu-linux-gnu',
    OS.windows => '$cpu-windows-gnu',
    OS.android => arch == Architecture.arm ? 'arm-linux-androideabi.${code.android.targetNdkApi}' : '$cpu-linux-android.${code.android.targetNdkApi}',
    OS.iOS => code.iOS.targetSdk == IOSSdk.iPhoneSimulator ? '$cpu-ios-simulator' : '$cpu-ios',
    _ => throw UnsupportedError('Target OS not supported: ${code.targetOS}'),
  };
}

String _libName(OS os) => switch (os) {
  OS.macOS || OS.iOS => 'librealm_dart.dylib',
  OS.linux || OS.android => 'librealm_dart.so',
  OS.windows => 'realm_dart.dll',
  _ => throw UnsupportedError('Target OS not supported: $os'),
};

Future<void> _zigBuild({required Uri packageRoot, required String zigTarget, required CodeConfig code, required String installPrefix}) async {
  final targetOS = code.targetOS;
  final zig = await _zigLauncher(packageRoot);
  final args = [
    ...zig.skip(1),
    'build',
    '-Dtarget=$zigTarget',
    '--release=fast',
    '-p',
    installPrefix,
    if (targetOS == OS.macOS || targetOS == OS.iOS) ...['--sysroot', await _appleSdkPath(code)],
    if (targetOS == OS.android) '-Dandroid-ndk=${_ndkPath(code)}',
  ];

  final result = await Process.run(zig.first, args, workingDirectory: packageRoot.toFilePath());
  if (result.exitCode != 0) {
    throw Exception(
      'zig build failed (${result.exitCode}):\n'
      '${zig.join(' ')} ${args.join(' ')}\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
}

/// Resolves the zig launch command, honoring the version pinned in
/// .zig-version. Falls back to `zigup run <version>` when the zig on PATH
/// does not match.
Future<List<String>> _zigLauncher(Uri packageRoot) async {
  final pinned = (await File.fromUri(packageRoot.resolve('.zig-version')).readAsString()).trim();

  final zig = await _tryRun('zig', ['version']);
  if (zig == pinned) return ['zig'];

  final zigup = await _tryRun('zigup', ['fetch', pinned]);
  if (zigup != null) return ['zigup', 'run', pinned];

  throw Exception(
    'zig $pinned not found '
    '(${zig == null ? 'no zig on PATH' : 'found zig $zig'}).\n'
    'Install zig $pinned, or install zigup '
    '(https://github.com/marler8997/zigup) and the hook will fetch it.',
  );
}

Future<String?> _tryRun(String exe, List<String> args) async {
  try {
    final result = await Process.run(exe, args);
    if (result.exitCode != 0) return null;
    return (result.stdout as String).trim();
  } on ProcessException {
    return null;
  }
}

Future<String> _appleSdkPath(CodeConfig code) async {
  final sdkName = switch (code.targetOS) {
    OS.macOS => 'macosx',
    OS.iOS => code.iOS.targetSdk == IOSSdk.iPhoneSimulator ? 'iphonesimulator' : 'iphoneos',
    _ => throw StateError('Not an Apple target: ${code.targetOS}'),
  };
  final sdk = await _tryRun('xcrun', ['--sdk', sdkName, '--show-sdk-path']);
  if (sdk == null) {
    throw Exception('xcrun --sdk $sdkName --show-sdk-path failed - is Xcode installed?');
  }
  return sdk;
}

/// Locates the Android NDK: prefer the toolchain Flutter hands the hook
/// (the NDK clang lives at `<ndk>/toolchains/llvm/prebuilt/<host>/bin/`),
/// then ANDROID_NDK_HOME, then the newest NDK under the SDK root.
String _ndkPath(CodeConfig code) {
  final compiler = code.cCompiler?.compiler;
  if (compiler != null) {
    final segments = compiler.toFilePath().split(Platform.pathSeparator);
    final i = segments.indexOf('toolchains');
    if (i > 0) {
      return segments.sublist(0, i).join(Platform.pathSeparator);
    }
  }

  final ndkHome = Platform.environment['ANDROID_NDK_HOME'];
  if (ndkHome != null && Directory(ndkHome).existsSync()) return ndkHome;

  final sdkRoot =
      Platform.environment['ANDROID_HOME'] ??
      Platform.environment['ANDROID_SDK_ROOT'] ??
      switch (Platform.operatingSystem) {
        'macos' => '${Platform.environment['HOME']}/Library/Android/sdk',
        'linux' => '${Platform.environment['HOME']}/Android/Sdk',
        _ => '${Platform.environment['LOCALAPPDATA']}\\Android\\Sdk',
      };
  final ndkDir = Directory('$sdkRoot/ndk');
  if (ndkDir.existsSync()) {
    final versions = ndkDir.listSync().whereType<Directory>().map((d) => d.path).toList()..sort();
    if (versions.isNotEmpty) return versions.last;
  }

  throw Exception(
    'Android NDK not found. Set ANDROID_NDK_HOME or install one via '
    'Android Studio.',
  );
}
