import 'package:test/test.dart';
import 'package:android_libcpp_shared/src/locate_ndk.dart';

void main() {
  test('locate returns non-empty set of paths', () async {
    final ndkPaths = await NDKLocator.locate();
    expect(ndkPaths, isNotEmpty);
    print('Found NDK paths:');
    for (final ndkPath in ndkPaths) {
      print(' - ${ndkPath.path} (version: ${ndkPath.version})');
      // Available host archs:
      for (final hostArch in ndkPath.hostArchitectures) {
        print('   - Host architecture: ${hostArch.arch}');
        for (final targetArch in hostArch.targetArchitectures) {
          print('     - Target architecture: ${targetArch.arch}');
          for (final apiLevel in targetArch.apiLevels) {
            print('       - API level: $apiLevel');
          }
        }
      }
    }
  });
}
