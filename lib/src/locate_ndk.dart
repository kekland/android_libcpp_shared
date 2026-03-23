import 'dart:convert';
import 'dart:io';

import 'package:glob/glob.dart';
import 'package:android_libcpp_shared/src/process.dart';
import 'package:glob/list_local_fs.dart';
import 'package:hooks/hooks.dart';
import 'package:code_assets/code_assets.dart';

enum HostArch {
  x64,
  arm64,
  armv7;

  @override
  String toString() {
    switch (this) {
      case HostArch.x64:
        return 'x86_64';
      case HostArch.arm64:
        return 'arm64';
      case HostArch.armv7:
        return 'armv7';
    }
  }

  static HostArch? fromString(String str) {
    switch (str) {
      case 'x86_64':
        return HostArch.x64;
      case 'arm64':
        return HostArch.arm64;
      case 'armv7':
        return HostArch.armv7;
      default:
        return null;
    }
  }
}

enum HostOS {
  linux,
  macos,
  windows;

  @override
  String toString() {
    switch (this) {
      case HostOS.linux:
        return 'linux';
      case HostOS.macos:
        return 'darwin';
      case HostOS.windows:
        return 'windows';
    }
  }

  static HostOS? fromString(String str) {
    switch (str) {
      case 'linux':
        return HostOS.linux;
      case 'darwin':
      case 'macos':
        return HostOS.macos;
      case 'windows':
        return HostOS.windows;
      default:
        return null;
    }
  }
}

enum LibArch {
  arm,
  arm64,
  x86,
  riscv64,
  x86_64;

  String toTriple() {
    switch (this) {
      case LibArch.arm:
        return 'arm-linux-androideabi';
      case LibArch.arm64:
        return 'aarch64-linux-android';
      case LibArch.x86:
        return 'i686-linux-android';
      case LibArch.riscv64:
        return 'riscv64-linux-android';
      case LibArch.x86_64:
        return 'x86_64-linux-android';
    }
  }

  String toLlvmTriple() {
    switch (this) {
      case LibArch.arm:
        return 'armv7-none-linux-androideabi';
      case LibArch.arm64:
        return 'aarch64-none-linux-android';
      case LibArch.x86:
        return 'i686-none-linux-android';
      case LibArch.riscv64:
        return 'riscv64-none-linux-android';
      case LibArch.x86_64:
        return 'x86_64-none-linux-android';
    }
  }

  static LibArch? fromString(String str) {
    switch (str) {
      case 'arm':
      case 'armeabi-v7a':
      case 'armv7':
        return LibArch.arm;
      case 'arm64':
      case 'arm64-v8a':
      case 'aarch64':
        return LibArch.arm64;
      case 'x86':
      case 'i686':
        return LibArch.x86;
      case 'riscv64':
        return LibArch.riscv64;
      case 'x86_64':
      case 'amd64':
      case 'x64':
        return LibArch.x86_64;
      default:
        return null;
    }
  }

  static LibArch? fromLlvmTriple(String str) {
    switch (str) {
      case 'armv7-none-linux-androideabi':
        return LibArch.arm;
      case 'aarch64-none-linux-android':
        return LibArch.arm64;
      case 'i686-none-linux-android':
        return LibArch.x86;
      case 'riscv64-none-linux-android':
        return LibArch.riscv64;
      case 'x86_64-none-linux-android':
        return LibArch.x86_64;
      default:
        return null;
    }
  }

  static LibArch? fromTriple(String str) {
    switch (str) {
      case 'arm-linux-androideabi':
        return LibArch.arm;
      case 'aarch64-linux-android':
        return LibArch.arm64;
      case 'i686-linux-android':
        return LibArch.x86;
      case 'riscv64-linux-android':
        return LibArch.riscv64;
      case 'x86_64-linux-android':
        return LibArch.x86_64;
      default:
        return null;
    }
  }
}

final class NKDVersion {
  final int major;
  final int minor;
  final int patch;
  final String flavor;

  NKDVersion(this.major, this.minor, this.patch, [this.flavor = '']);

  factory NKDVersion.parse(String version) {
    final regex = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:-(.+))?$');
    final match = regex.firstMatch(version);
    if (match == null) {
      throw FormatException('Invalid NDK version format: $version');
    }
    return NKDVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      match.group(4) ?? '',
    );
  }

  int compareTo(NKDVersion other) {
    if (major != other.major) {
      return major.compareTo(other.major);
    }
    if (minor != other.minor) {
      return minor.compareTo(other.minor);
    }
    if (patch != other.patch) {
      return patch.compareTo(other.patch);
    }
    return flavor.compareTo(other.flavor);
  }

  @override
  String toString() =>
      '$major.$minor.$patch${flavor.isNotEmpty ? '-$flavor' : ''}';
}

final class NDKApiLevel {
  final int level;
  final Uri sysrootLibPath;

  NDKApiLevel(this.level, this.sysrootLibPath);

  @override
  String toString() => 'android-$level';
}

final class NDKTargetArchitecture {
  final LibArch arch;
  final Uri sysrootLibPath;
  final List<NDKApiLevel> _apiLevels;

  NDKTargetArchitecture(
    this.arch,
    this.sysrootLibPath, {
    List<NDKApiLevel>? apiLevels,
  }) : _apiLevels = apiLevels ?? [];

  NDKApiLevel? highestMatching(int minApiLevel) {
    final suitableApiLevels =
        _apiLevels.where((api) => api.level >= minApiLevel).toList()
          ..sort((a, b) => b.level.compareTo(a.level));
    return suitableApiLevels.isNotEmpty ? suitableApiLevels.first : null;
  }

  void _addApiLevel(NDKApiLevel apiLevel) {
    _apiLevels.add(apiLevel);
  }

  List<NDKApiLevel> get apiLevels => List.unmodifiable(_apiLevels);

  @override
  String toString() => arch.toTriple();
}

final class NDKHostArchitecture {
  final HostOS os;
  final HostArch arch;
  final Uri llvmToolchainPath;
  final List<NDKTargetArchitecture> _targetArchitectures;

  NDKHostArchitecture(
    this.os,
    this.arch,
    this.llvmToolchainPath, {
    List<NDKTargetArchitecture>? targetArchitectures,
  }) : _targetArchitectures = targetArchitectures ?? [];

  NDKTargetArchitecture? findTarget(LibArch targetArch) {
    try {
      return _targetArchitectures.firstWhere((t) => t.arch == targetArch);
    } catch (e) {
      return null;
    }
  }

  void _addTargetArchitecture(NDKTargetArchitecture targetArch) {
    _targetArchitectures.add(targetArch);
  }

  List<NDKTargetArchitecture> get targetArchitectures =>
      List.unmodifiable(_targetArchitectures);

  @override
  String toString() => '$os-$arch';
}

final class NDKInfo {
  final Uri path;
  final NKDVersion version;
  final List<NDKHostArchitecture> hostArchitectures;

  NDKInfo({
    required this.path,
    required this.version,
    required this.hostArchitectures,
  });

  NDKHostArchitecture? findHost(HostOS hostOS) {
    try {
      return hostArchitectures.firstWhere((h) => h.os == hostOS);
    } catch (e) {
      return null;
    }
  }
}

class NDKLocator {
  static final _searchPaths = [
    if (Platform.isLinux) ...[
      '\$HOME/.androidsdkroot/ndk/*/', // Firebase Studio
      '\$HOME/Android/Sdk/ndk/*/',
      '\$HOME/Android/Sdk/ndk-bundle/',
    ],
    if (Platform.isMacOS) ...['\$HOME/Library/Android/sdk/ndk/*/'],
    if (Platform.isWindows) ...['\$HOME/AppData/Local/Android/Sdk/ndk/*/'],
  ];

  static final _ndkEnvVars = [
    'ANDROID_NDK',
    'ANDROID_NDK_HOME',
    'ANDROID_NDK_LATEST_HOME',
    'ANDROID_NDK_ROOT',
  ];

  static final _androidHomeEnvVars = [
    'ANDROID_HOME',
    'ANDROID_SDK_ROOT',
    'ANDROID_SDK_HOME',
  ];

  static final _pathExe = Platform.isWindows ? 'ndk-build.cmd' : 'ndk-build';

  static List<FileSystemEntity> expandPath(String pathTemplate) {
    final path = pathTemplate.replaceAll(
      '\$HOME',
      Platform.environment['HOME']!,
    );
    final glob = Glob(path);
    final matches = glob.listSync();
    return matches;
  }

  static Future<NDKInfo> _getNDKInfo(Uri ndkPath) async {
    final sourceProps = File('${ndkPath.toFilePath()}/source.properties');
    if (!sourceProps.existsSync()) {
      throw Exception(
        'NDK at ${ndkPath.toFilePath()} is missing source.properties',
      );
    }
    final propsContent = await sourceProps.readAsString();
    final props = <String, String>{};
    for (final line in LineSplitter.split(propsContent)) {
      final parts = line.split('=');
      if (parts.length == 2) {
        props[parts[0].trim()] = parts[1].trim();
      }
    }
    final versionStr = props['Pkg.Revision'];
    if (versionStr == null) {
      throw Exception(
        'NDK at ${ndkPath.toFilePath()} is missing Pkg.Revision in source.properties',
      );
    }
    final version = NKDVersion.parse(versionStr);

    // The toolchains directory contain subdirectories for each host arch
    final toolchainsDir = Directory(
      '${ndkPath.toFilePath()}/toolchains/llvm/prebuilt/',
    );
    if (!toolchainsDir.existsSync()) {
      throw Exception(
        'NDK at ${ndkPath.toFilePath()} is missing toolchains directory',
      );
    }
    final hostArchitectures = <NDKHostArchitecture>[];
    for (final hostDir in toolchainsDir.listSync().whereType<Directory>()) {
      print('Checking host directory: ${hostDir.uri.toFilePath()}');
      final hostName = hostDir.uri.pathSegments.lastWhere(
        (segment) => segment.isNotEmpty,
      );
      final parts = hostName.split('-');
      if (parts.length >= 2) {
        final osPart = parts[0];
        final archPart = parts.sublist(1).join('-');
        final os = HostOS.fromString(osPart);
        final arch = HostArch.fromString(archPart);
        if (os != null && arch != null) {
          hostArchitectures.add(NDKHostArchitecture(os, arch, hostDir.uri));
        }
      }
    }

    // The host arch directory contains
    // sysroot/usr/lib/<target arch> directories for each target arch
    for (final host in hostArchitectures) {
      final sysrootLibDir = Directory(
        '${host.llvmToolchainPath.toFilePath()}/sysroot/usr/lib/',
      );
      if (sysrootLibDir.existsSync()) {
        for (final targetDir
            in sysrootLibDir.listSync().whereType<Directory>()) {
          final targetName = targetDir.uri.pathSegments.lastWhere(
            (segment) => segment.isNotEmpty,
          );
          final targetArch = LibArch.fromTriple(targetName);
          if (targetArch != null) {
            host._addTargetArchitecture(
              NDKTargetArchitecture(targetArch, targetDir.uri),
            );
          }
        }
      }
    }

    // The target arch lib directories contain subdirectories for each API level
    // e.g. sysroot/usr/lib/arm-linux-androideabi/21/
    for (final host in hostArchitectures) {
      for (final target in host.targetArchitectures) {
        final targetLibDir = Directory(
          '${target.sysrootLibPath.toFilePath()}/',
        );
        if (targetLibDir.existsSync()) {
          for (final apiLevelDir
              in targetLibDir.listSync().whereType<Directory>()) {
            final apiLevelName = apiLevelDir.uri.pathSegments.lastWhere(
              (segment) => segment.isNotEmpty,
            );
            final apiLevelNum = int.tryParse(apiLevelName);
            if (apiLevelNum != null) {
              target._addApiLevel(NDKApiLevel(apiLevelNum, apiLevelDir.uri));
            }
          }
        }
      }
    }

    return NDKInfo(
      path: ndkPath,
      version: version,
      hostArchitectures: hostArchitectures,
    );
  }

  /// Returns the path to the Android NDK, or `null` if it cannot be found.
  static Future<List<NDKInfo>> locate() async {
    final ndkPaths = <Uri>{};
    // first see if the exe is in path using which
    final whichResult = await which(_pathExe);
    if (whichResult != null) {
      final ndkDir = whichResult.resolve('../');
      if (ndkDir.toFilePath() != whichResult.toFilePath()) {
        ndkPaths.add(ndkDir);
      }
    }

    // then check environment variables
    for (final envVar in _ndkEnvVars) {
      final envValue = Platform.environment[envVar];
      if (envValue != null) {
        final ndkDir = Directory(envValue);
        if (ndkDir.existsSync()) {
          ndkPaths.add(ndkDir.uri);
        }
      }
    }

    // try common install locations
    for (final pathTemplate in _searchPaths) {
      for (final match in expandPath(pathTemplate)) {
        if (match is Directory) {
          ndkPaths.add(match.uri);
        }
      }
    }

    // finally, if we have an ANDROID_HOME, check for the NDK there
    for (final envVar in _androidHomeEnvVars) {
      final envValue = Platform.environment[envVar];
      if (envValue != null) {
        final androidHome = expandPath(envValue);
        if (androidHome.isNotEmpty) {
          final ndkDir = Directory('${androidHome.first.path}/ndk');
          if (ndkDir.existsSync()) {
            for (final match in expandPath('${ndkDir.path}/*/')) {
              if (match is Directory) {
                ndkPaths.add(match.uri);
              }
            }
          }
        }
      }
    }

    final List<NDKInfo> ndkInfos = [];
    for (final ndkPath in ndkPaths) {
      try {
        final info = await _getNDKInfo(ndkPath);
        ndkInfos.add(info);
      } catch (e, st) {
        // ignore invalid NDK directories
        print(
          'Warning: Failed to get info for NDK at ${ndkPath.toFilePath()}: $e',
        );
        print(st);
      }
    }
    return ndkInfos;
  }
}

extension FindNDKInfo on Iterable<NDKInfo> {
  NDKInfo? forBuildConfig(BuildConfig config) {
    final sorted = toList()..sort((a, b) => b.version.compareTo(a.version));
    final hostOS = HostOS.fromString(Platform.operatingSystem);
    final targetArch = LibArch.fromString(
      config.code.targetArchitecture.toString(),
    );
    final minApiLevel = config.code.android.targetNdkApi;
    for (final ndk in sorted) {
      final host = ndk.findHost(hostOS!);
      if (host != null) {
        final target = host.findTarget(targetArch!);
        if (target != null) {
          final apiLevel = target.highestMatching(minApiLevel);
          if (apiLevel != null) {
            // Return the filtered version.
            return NDKInfo(
              path: ndk.path,
              version: ndk.version,
              hostArchitectures: [
                NDKHostArchitecture(
                  host.os,
                  host.arch,
                  host.llvmToolchainPath,
                  targetArchitectures: [
                    NDKTargetArchitecture(
                      target.arch,
                      target.sysrootLibPath,
                      apiLevels: [apiLevel],
                    ),
                  ],
                ),
              ],
            );
          }
        }
      }
    }
  }
}
