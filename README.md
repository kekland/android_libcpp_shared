# android_libcpp_shared

Dart / flutter package for Android to add the libc++_shared.so STL C++ shared runtime library to your app

# Usage

Add the package to your pubspec.yaml dependencies:

```yaml
dependencies:
  android_libcpp_shared: ^0.1.0
```

You don't need to import anything into your Dart code, the dependency is sufficient to bundle the native library with your app.

# License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
Parts of the NDK locating code are adapted from the Dart native_toolchain_c package, which is licensed under a BSD-style license. See the [NATIVE_LICENSE](NATIVE_LICENSE) file for details.
