// Build librealm_dart with zig instead of CMake.
//
// Scope: the local-database subset of realm-core (sync OFF - the sync
// server is discontinued; encryption OFF for now) plus the realm_dart
// wrapper, as a shared library for Dart/Flutter to load.
//
// The common source manifest (zig/sources.zig) is generated from the
// CMake ground truth by zig/gen_sources.py (harvested on macOS).
// Platform-conditional sources/libs below mirror:
//   src/realm-core/src/realm/CMakeLists.txt (sha-1/sha-2, system libs)
//   src/realm-core/src/realm/object-store/CMakeLists.txt (commit helper)
const std = @import("std");
const sources = @import("zig/sources.zig");

const realm_version = .{ .major = 14, .minor = 14, .patch = 0 };

// Files present in the (macOS-harvested) manifest that must only be
// compiled on Apple platforms.
const apple_only = [_][]const u8{
    "src/realm-core/src/realm/exceptions.mm",
    "src/realm-core/src/realm/object-store/impl/apple/external_commit_helper.cpp",
    "src/realm-core/src/realm/object-store/impl/apple/keychain_helper.cpp",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseFast,
    });
    const android_ndk = b.option(
        []const u8,
        "android-ndk",
        "Path to the Android NDK (required for Android targets)",
    );
    const strip = b.option(bool, "strip", "Strip debug info (used for release/published binaries)") orelse false;

    const os = target.result.os.tag;
    const is_apple = os.isDarwin();
    const is_windows = os == .windows;
    const is_android = target.result.abi.isAndroid();
    const is_linux_like = os == .linux; // includes android (os.tag == .linux)

    // Any explicit -Dtarget makes zig treat the build as non-native and
    // skip its automatic Apple SDK discovery - even when the target *is*
    // the host. Fall back to xcrun so plain
    // `zig build -Dtarget=aarch64-macos` works without --sysroot.
    if (is_apple and b.sysroot == null) {
        b.sysroot = detectAppleSdk(b, target);
    }

    const module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
        .strip = strip,
    });

    const lib = b.addLibrary(.{
        .name = "realm_dart",
        .linkage = .dynamic,
        .root_module = module,
    });

    for (sources.include_dirs) |dir| {
        module.addIncludePath(b.path(dir));
    }
    module.addIncludePath(generatedHeaders(b, .{
        .is_apple = is_apple,
        .is_linux_like = is_linux_like,
        .is_android = is_android,
        .is_glibc_linux = is_linux_like and !is_android and target.result.abi == .gnu,
    }));

    // Flags beyond what the manifest carries:
    // - exceptions stay ON (realm-core's error handling relies on them)
    // - zig cc enables UBSan-trap by default in debug; the frozen codebase
    //   is not UBSan-clean, so disable it
    // - hidden visibility matches the CMake build (only RLM_API is exported)
    const c_extra: []const []const u8 = &.{
        "-fno-sanitize=undefined",
    };
    const cpp_extra: []const []const u8 = &.{
        "-fno-sanitize=undefined",
        "-fvisibility=hidden",
        "-fvisibility-inlines-hidden",
        // s2 (vendored, frozen) specializes std::is_pod, which modern
        // libc++ rejects by default.
        "-Wno-invalid-specialization",
    };

    // Platform defines beyond the manifest (mirrors the CMake top level
    // and object-store/CMakeLists.txt).
    var platform_defines: std.ArrayList([]const u8) = .empty;
    if (is_windows) {
        appendAll(b, &platform_defines, &.{
            "-DWIN32_LEAN_AND_MEAN", "-DUNICODE", "-D_UNICODE",
            // realm/util/file.hpp gates its std::filesystem-based Windows
            // implementation on _MSVC_LANG (otherwise it falls back to
            // POSIX APIs that mingw lacks). libc++ has <filesystem>, so
            // claim the MSVC C++20 language level.
            "-D_MSVC_LANG=202002L",
            // mingw <math.h> hides M_PI etc. in strict-ANSI mode; the
            // vendored s2 needs them (MSVC builds use the same define).
            "-D_USE_MATH_DEFINES",
        });
    }
    if (is_linux_like) {
        appendAll(b, &platform_defines, &.{"-DREALM_HAVE_EPOLL=1"});
    }
    if (is_apple) {
        if (b.sysroot) |sysroot| {
            // Cross-compiling to another Apple arch/OS: zig only wires the
            // SDK up automatically for native builds. zig curates header
            // search paths itself, so a plain -isysroot is not enough -
            // inject the SDK headers/frameworks sysroot-relative (same
            // pattern as kubkon/zig-ios-example).
            appendAll(b, &platform_defines, &.{
                "-isysroot",               sysroot,
                "-iwithsysroot",           "/usr/include",
                "-iframeworkwithsysroot",  "/System/Library/Frameworks",
                // Recent SDKs split helper frameworks out (e.g. UIKit
                // references UIUtilities from here).
                "-iframeworkwithsysroot",  "/System/Library/SubFrameworks",
            });
        }
    }

    // Note: language is deliberately not forced - realm-core mixes
    // .cpp and .mm (Objective-C++) in the same target, so let zig
    // deduce it from the file extension.
    inline for (sources.groups) |group| {
        const extra = switch (group.language) {
            .c => c_extra,
            .cpp => cpp_extra,
        };
        module.addCSourceFiles(.{
            .files = filterFiles(b, group.files, is_apple),
            .flags = concat(b, group.flags ++ extra, platform_defines.items),
        });
    }

    // The realm-core C++ flag set, for platform-conditional C++ sources
    // (kept in sync with the biggest manifest group).
    const core_cpp_flags = concat(b, &[_][]const u8{
        "-std=c++20",
        "-DNDEBUG",
        "-D_LARGEFILE64_SOURCE",
        "-D_LARGEFILE_SOURCE",
        "-D_LIBCPP_REMOVE_TRANSITIVE_INCLUDES",
    } ++ cpp_extra, platform_defines.items);

    // The realm_dart wrapper flag set (matches its manifest group), for
    // the platform glue sources (android/platform.cpp, ios/platform.mm).
    const dart_cpp_flags = concat(b, &[_][]const u8{
        "-std=c++20",
        "-DNDEBUG",
        "-DRLM_NO_DLLIMPORT",
        "-DRealm_EXPORTS",
        "-Drealm_dart_EXPORTS",
    } ++ cpp_extra, platform_defines.items);

    // External commit helper variant (object-store/CMakeLists.txt).
    const commit_helper: ?[]const u8 = if (is_apple)
        null // already in the manifest
    else if (is_linux_like)
        "src/realm-core/src/realm/object-store/impl/epoll/external_commit_helper.cpp"
    else if (is_windows)
        "src/realm-core/src/realm/object-store/impl/windows/external_commit_helper.cpp"
    else
        "src/realm-core/src/realm/object-store/impl/generic/external_commit_helper.cpp";
    if (commit_helper) |file| {
        module.addCSourceFiles(.{ .files = &.{file}, .flags = core_cpp_flags });
    }

    // Bundled SHA implementations for platforms without a native one
    // (realm/CMakeLists.txt). Apple uses CommonCrypto, Windows uses
    // bcrypt for SHA-1/SHA-256 but still needs the bundled SHA-2 for
    // SHA-224; everything else (no OpenSSL yet) needs both.
    if (!is_apple) {
        module.addIncludePath(b.path("src/realm-core/src/external/sha-2"));
        module.addCSourceFiles(.{
            .files = &.{
                "src/realm-core/src/external/sha-2/sha224.cpp",
                "src/realm-core/src/external/sha-2/sha256.cpp",
            },
            .flags = core_cpp_flags,
        });
        if (!is_windows) {
            module.addIncludePath(b.path("src/realm-core/src/external/sha-1"));
            module.addCSourceFiles(.{
                .files = &.{"src/realm-core/src/external/sha-1/sha1.c"},
                .flags = concat(b, &[_][]const u8{"-DNDEBUG"} ++ c_extra, platform_defines.items),
            });
        }
    }

    // zlib: system library on Apple, built from source elsewhere.
    if (is_apple) {
        // When cross-compiling to another Apple arch/OS, zig does not
        // search the SDK on its own; wire it up from --sysroot
        // (e.g. `--sysroot $(xcrun --show-sdk-path)`).
        if (b.sysroot) |sysroot| {
            // zig prefixes include/library paths with the sysroot itself,
            // but (as of 0.15) not framework paths - give that one in full.
            module.addSystemIncludePath(.{ .cwd_relative = "/usr/include" });
            module.addLibraryPath(.{ .cwd_relative = "/usr/lib" });
            module.addFrameworkPath(.{ .cwd_relative = b.fmt("{s}/System/Library/Frameworks", .{sysroot}) });
        }
        module.linkSystemLibrary("z", .{});
        module.linkSystemLibrary("compression", .{});
        module.linkFramework("Foundation", .{});
        module.linkFramework("Security", .{});
        // Implied by Foundation on native links; needed explicitly when
        // cross-linking against the SDK.
        module.linkFramework("CoreFoundation", .{});
        // Dart's install_name_tool handling needs header padding.
        lib.headerpad_max_install_names = true;
        if (os == .ios) {
            // Unlike macOS, zig bundles no libc headers for iOS, so its
            // own libc++/libc++abi sub-compilations need the SDK headers
            // via a libc file.
            const sysroot = b.sysroot orelse @panic(
                "iOS targets require --sysroot $(xcrun --sdk iphoneos|iphonesimulator --show-sdk-path)",
            );
            lib.setLibCFile(appleLibcFile(b, sysroot));
            // iOS platform glue (file paths, device info, rlimits).
            module.addCSourceFiles(.{
                .files = &.{"src/ios/platform.mm"},
                .flags = dart_cpp_flags,
            });
            module.linkFramework("UIKit", .{});
        }
    } else {
        addZlib(b, module, c_extra, is_windows);
    }

    if (is_windows) {
        // realm/CMakeLists.txt: Version.lib psapi.lib; sha_crypto.cpp
        // uses bcrypt (its `#pragma comment(lib)` is MSVC-only, so link
        // it explicitly here).
        module.linkSystemLibrary("version", .{});
        module.linkSystemLibrary("psapi", .{});
        module.linkSystemLibrary("bcrypt", .{});
        // MSVC-only <safeint.h> shim; see zig/shim/safeint.h.
        module.addIncludePath(b.path("zig/shim"));
    }
    if (is_android) {
        // zig does not bundle bionic - point it at the NDK sysroot.
        // The API level comes from the target query (e.g.
        // -Dtarget=aarch64-linux-android.21).
        const ndk = android_ndk orelse {
            std.debug.panic("Android targets require -Dandroid-ndk=<path>", .{});
        };
        lib.setLibCFile(androidLibcFile(b, target, ndk));
        // The libc file covers headers/CRT; system libs (libandroid,
        // liblog) need an explicit search path into the NDK sysroot.
        module.addLibraryPath(.{ .cwd_relative = androidLibDir(b, target, ndk) });
        // Android platform glue (JNI: files dir, device info, bundle id).
        module.addCSourceFiles(.{
            .files = &.{"src/android/platform.cpp"},
            .flags = dart_cpp_flags,
        });
        module.linkSystemLibrary("android", .{});
        module.linkSystemLibrary("log", .{});
    }

    b.installArtifact(lib);
}

/// Locate the right Apple SDK for the target via xcrun.
fn detectAppleSdk(b: *std.Build, target: std.Build.ResolvedTarget) ?[]const u8 {
    const sdk = switch (target.result.os.tag) {
        .macos => "macosx",
        .ios => if (target.result.abi == .simulator) "iphonesimulator" else "iphoneos",
        else => return null,
    };
    const result = std.process.run(b.allocator, b.graph.io, .{
        .argv = &.{ "xcrun", "--sdk", sdk, "--show-sdk-path" },
    }) catch return null;
    if (result.term != .exited or result.term.exited != 0) return null;
    return std.mem.trimEnd(u8, result.stdout, "\n");
}

/// Point zig's libc at an Apple SDK (used for iOS, where zig has no
/// bundled libc headers).
fn appleLibcFile(b: *std.Build, sysroot: []const u8) std.Build.LazyPath {
    const wf = b.addWriteFiles();
    return wf.add("apple-libc.txt", b.fmt(
        \\include_dir={[sysroot]s}/usr/include
        \\sys_include_dir={[sysroot]s}/usr/include
        \\crt_dir=
        \\msvc_lib_dir=
        \\kernel32_lib_dir=
        \\gcc_dir=
        \\
    , .{ .sysroot = sysroot }));
}

fn ndkSysroot(b: *std.Build, ndk_path: []const u8) []const u8 {
    const host_tag = switch (@import("builtin").os.tag) {
        .macos => "darwin-x86_64", // also used by arm64 NDKs (fat binaries)
        .linux => "linux-x86_64",
        .windows => "windows-x86_64",
        else => @panic("Unsupported host OS for the Android NDK"),
    };
    return b.fmt("{s}/toolchains/llvm/prebuilt/{s}/sysroot", .{ ndk_path, host_tag });
}

fn ndkTriple(target: std.Build.ResolvedTarget) []const u8 {
    return switch (target.result.cpu.arch) {
        .x86_64 => "x86_64-linux-android",
        .aarch64 => "aarch64-linux-android",
        .arm, .thumb => "arm-linux-androideabi",
        else => @panic("Unsupported Android architecture"),
    };
}

/// The versioned NDK library directory (libandroid.so, liblog.so, CRT).
fn androidLibDir(b: *std.Build, target: std.Build.ResolvedTarget, ndk_path: []const u8) []const u8 {
    return b.fmt("{s}/usr/lib/{s}/{d}", .{
        ndkSysroot(b, ndk_path),
        ndkTriple(target),
        target.result.os.version_range.linux.android,
    });
}

/// Generate a zig libc configuration pointing into the Android NDK
/// sysroot (zig has no bundled bionic).
fn androidLibcFile(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    ndk_path: []const u8,
) std.Build.LazyPath {
    const sysroot = ndkSysroot(b, ndk_path);
    const triple = ndkTriple(target);
    const wf = b.addWriteFiles();
    return wf.add("android-libc.txt", b.fmt(
        \\include_dir={[sysroot]s}/usr/include
        \\sys_include_dir={[sysroot]s}/usr/include/{[triple]s}
        \\crt_dir={[sysroot]s}/usr/lib/{[triple]s}/{[api]d}
        \\msvc_lib_dir=
        \\kernel32_lib_dir=
        \\gcc_dir=
        \\
    , .{
        .sysroot = sysroot,
        .triple = triple,
        .api = target.result.os.version_range.linux.android,
    }));
}

/// Generate realm/util/config.h and realm/version_numbers.hpp, which the
/// CMake build produces with configure_file().
fn generatedHeaders(b: *std.Build, opts: struct {
    is_apple: bool,
    is_linux_like: bool,
    is_android: bool,
    is_glibc_linux: bool,
}) std.Build.LazyPath {
    const wf = b.addWriteFiles();
    _ = wf.add("realm/util/config.h", b.fmt(
        \\// Generated by build.zig (mirrors realm/util/config.h.in)
        \\#define REALM_VERSION ""
        \\
        \\#define REALM_HAVE_READDIR64 {[readdir64]d}
        \\#define REALM_HAVE_POSIX_FALLOCATE {[fallocate]d}
        \\#define REALM_USE_SYSTEM_OPENSSL_PATHS 0
        \\#define REALM_HAVE_OPENSSL 0
        \\#define REALM_HAVE_SECURE_TRANSPORT {[secure_transport]d}
        \\#define REALM_HAVE_PTHREAD_GETNAME {[pthread_getname]d}
        \\#define REALM_HAVE_PTHREAD_SETNAME {[pthread_setname]d}
        \\#define REALM_HAVE_BACKTRACE {[backtrace]d}
        \\#define REALM_INCLUDE_CERTS 0
        \\#define REALM_MAX_BPNODE_SIZE 1000
        \\#define REALM_BACKTRACE_HEADER <execinfo.h>
        \\#define REALM_ENABLE_ASSERTIONS 0
        \\#define REALM_ENABLE_ALLOC_SET_ZERO 0
        \\#define REALM_ENABLE_ENCRYPTION 0
        \\#define REALM_ENABLE_MEMDEBUG 0
        \\#define REALM_ENABLE_GEOSPATIAL 1
        \\#define REALM_VALGRIND 0
        \\#define REALM_ASAN 0
        \\#define REALM_TSAN 0
        \\
    , .{
        .readdir64 = @as(u1, if (opts.is_linux_like) 1 else 0),
        .fallocate = @as(u1, if (opts.is_linux_like) 1 else 0),
        .secure_transport = @as(u1, if (opts.is_apple) 1 else 0),
        // bionic only gained pthread_getname_np at API 26.
        .pthread_getname = @as(u1, if (opts.is_apple or (opts.is_linux_like and !opts.is_android)) 1 else 0),
        .pthread_setname = @as(u1, if (opts.is_apple or opts.is_linux_like) 1 else 0),
        // execinfo.h: Apple and glibc only (not bionic, not musl).
        .backtrace = @as(u1, if (opts.is_apple or opts.is_glibc_linux) 1 else 0),
    }));
    _ = wf.add("realm/version_numbers.hpp", b.fmt(
        \\#ifndef REALM_VERSION_NUMBERS_HPP
        \\#define REALM_VERSION_NUMBERS_HPP
        \\#define REALM_VERSION_MAJOR {[major]d}
        \\#define REALM_VERSION_MINOR {[minor]d}
        \\#define REALM_VERSION_PATCH {[patch]d}
        \\#define REALM_VERSION_EXTRA ""
        \\#define REALM_VERSION_STRING "{[major]d}.{[minor]d}.{[patch]d}"
        \\#endif
        \\
    , realm_version));
    return wf.getDirectory();
}

/// Build zlib from the hash-pinned source tarball (build.zig.zon) and
/// compile it into the library directly.
fn addZlib(b: *std.Build, module: *std.Build.Module, c_extra: []const []const u8, is_windows: bool) void {
    const zlib = b.dependency("zlib", .{});
    module.addIncludePath(zlib.path(""));
    const posix_flags: []const []const u8 = if (is_windows)
        &.{} // gz* files use Windows io.h via zconf.h
    else
        &.{"-DZ_HAVE_UNISTD_H"}; // gz* files need read/write/close/lseek
    module.addCSourceFiles(.{
        .root = zlib.path(""),
        .files = &.{
            "adler32.c", "compress.c", "crc32.c",    "deflate.c",
            "gzclose.c", "gzlib.c",    "gzread.c",   "gzwrite.c",
            "infback.c", "inffast.c",  "inflate.c",  "inftrees.c",
            "trees.c",   "uncompr.c",  "zutil.c",
        },
        .flags = concat(b, concat(b, &.{"-DHAVE_STDARG_H"}, posix_flags), c_extra),
    });
}

fn filterFiles(b: *std.Build, files: []const []const u8, is_apple: bool) []const []const u8 {
    if (is_apple) return files;
    var list: std.ArrayList([]const u8) = .empty;
    outer: for (files) |file| {
        for (apple_only) |excluded| {
            if (std.mem.eql(u8, file, excluded)) continue :outer;
        }
        list.append(b.allocator, file) catch @panic("OOM");
    }
    return list.items;
}

fn concat(b: *std.Build, head: []const []const u8, tail: []const []const u8) []const []const u8 {
    return std.mem.concat(b.allocator, []const u8, &.{ head, tail }) catch @panic("OOM");
}

fn appendAll(b: *std.Build, list: *std.ArrayList([]const u8), items: []const []const u8) void {
    list.appendSlice(b.allocator, items) catch @panic("OOM");
}
