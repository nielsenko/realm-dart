import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final code = input.config.code;
    final packageRoot = input.packageRoot;
    final libName = _libName(code.targetOS);

    final prebuilt = File.fromUri(packageRoot.resolve('binary/${_platformDir(code)}/$libName'));
    final buildZig = File.fromUri(packageRoot.resolve('build.zig'));

    final Uri libUri;
    if (prebuilt.existsSync()) {
      // Published package: use the bundled prebuilt for this target.
      libUri = prebuilt.uri;
    } else if (buildZig.existsSync()) {
      // Source checkout: compile from source with the pinned zig toolchain.
      libUri = await _zigBuild(packageRoot: packageRoot, code: code, output: input.outputDirectory);
    } else {
      throw Exception(
        'No prebuilt realm binary for ${code.targetOS}/${code.targetArchitecture} '
        'at ${prebuilt.path}, and build.zig is absent so it cannot be built '
        'from source. This is likely a packaging bug - please report it.',
      );
    }

    output.assets.code.add(CodeAsset(package: input.packageName, name: 'realm_dart.dart', linkMode: DynamicLoadingBundled(), file: libUri));
  });
}

/// Directory under binary/ where the prebuilt for this target is bundled.
/// Must match the layout produced by the release workflow.
String _platformDir(CodeConfig code) {
  final arch = switch (code.targetArchitecture) {
    Architecture.x64 => 'x64',
    Architecture.arm64 => 'arm64',
    Architecture.arm => 'arm',
    _ => throw UnsupportedError('Unsupported architecture: ${code.targetArchitecture}'),
  };
  return switch (code.targetOS) {
    OS.macOS => 'macos-$arch',
    OS.linux => 'linux-$arch',
    OS.windows => 'windows-$arch',
    OS.android => 'android-$arch',
    OS.iOS => code.iOS.targetSdk == IOSSdk.iPhoneSimulator ? 'ios-$arch-simulator' : 'ios-$arch',
    _ => throw UnsupportedError('Target OS not supported: ${code.targetOS}'),
  };
}

String _libName(OS os) => switch (os) {
  OS.macOS || OS.iOS => 'librealm_dart.dylib',
  OS.linux || OS.android => 'librealm_dart.so',
  OS.windows => 'realm_dart.dll',
  _ => throw UnsupportedError('Target OS not supported: $os'),
};

/// Compiles librealm for [code]'s target with zig and returns the built file.
Future<Uri> _zigBuild({required Uri packageRoot, required CodeConfig code, required Uri output}) async {
  final libName = _libName(code.targetOS);
  final prefix = Directory.fromUri(output.resolve('zig/'));
  await prefix.create(recursive: true);

  final targetOS = code.targetOS;
  final ndk = targetOS == OS.android ? _ndkPath(code) : null;
  final zig = await _zigLauncher(packageRoot);
  final cliArgs = [
    'build',
    '-Dtarget=${_zigTarget(code)}',
    '--release=fast',
    '-Dstrip=true',
    '-p',
    prefix.path,
    if (targetOS == OS.macOS || targetOS == OS.iOS) ...['--sysroot', await _appleSdkPath(code)],
    if (ndk != null) '-Dandroid-ndk=$ndk',
  ];

  final result = await Process.run(
    zig,
    cliArgs,
    workingDirectory: packageRoot.toFilePath(),
    environment: {if (!Platform.environment.containsKey('ZIG_GLOBAL_CACHE_DIR')) 'ZIG_GLOBAL_CACHE_DIR': packageRoot.resolve('.zig-cache').toFilePath()},
  );
  if (result.exitCode != 0) {
    throw Exception(
      'zig build failed (${result.exitCode}):\n'
      '$zig ${cliArgs.join(' ')}\n'
      '${result.stdout}\n${result.stderr}',
    );
  }

  // zig installs shared libraries to lib/ (bin/ for Windows DLLs).
  final subdir = targetOS == OS.windows ? 'bin' : 'lib';
  final builtLib = File.fromUri(prefix.uri.resolve('$subdir/$libName'));
  if (!builtLib.existsSync()) {
    throw Exception('zig build succeeded but ${builtLib.path} is missing');
  }
  return builtLib.uri;
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

/// Resolves the zig executable, requiring the version pinned in .zig-version
/// (which must match build.zig.zon's minimum_zig_version). The `zig` on PATH
/// may be a matching standalone install or anyzig, which selects the version
/// per project from build.zig.zon (https://github.com/marler8997/anyzig).
Future<String> _zigLauncher(Uri packageRoot) async {
  final pinned = (await File.fromUri(packageRoot.resolve('.zig-version')).readAsString()).trim();

  // Probe from packageRoot so anyzig resolves the version from build.zig.zon.
  final zig = await _tryRun('zig', ['version'], workingDirectory: packageRoot);
  if (zig == pinned) return 'zig';

  throw Exception(
    'zig $pinned not found '
    '(${zig == null ? 'no zig on PATH' : 'found zig $zig'}).\n'
    'Install anyzig - one `zig` that selects the version from build.zig.zon '
    '(https://github.com/marler8997/anyzig) - or install zig $pinned directly.',
  );
}

Future<String?> _tryRun(String exe, List<String> args, {Uri? workingDirectory}) async {
  try {
    final result = await Process.run(exe, args, workingDirectory: workingDirectory?.toFilePath());
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
