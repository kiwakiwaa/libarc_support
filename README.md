# libarc_support

Provides ARC runtime entry points for old Objective-C runtimes.
It builds as `libarc_support.dylib` with a flat install name and exports the
ARC runtime symbols listed in `exports/libarc_support.exp`.


Use Xcode 4.2 on OS X 10.6.8:

```sh
ARCH=i386 CONFIGURATION=Debug ./scripts/test-arc-core.sh
ARCH=i386 CONFIGURATION=Release ./scripts/test-arc-core.sh
```

Use clang 3.4 and link BlocksRuntime directly on OS X 10.4:

```sh
ARCH=i386 CONFIGURATION=Debug \
ARC_BUILD_SYSTEM=manual \
ARC_CC=/opt/local/bin/clang \
ARC_BLOCKS_CC=/opt/local/bin/clang \
SDKROOT=/Developer/SDKs/MacOSX10.4u.sdk \
./scripts/test-arc-core.sh
```

If MacPorts `libblocksruntime` is unavailable, build the fallback runtime:

```sh
./scripts/build-tiger-blocksruntime.sh
```

## Using the dylib

The dylib build default is a flat install name: `libarc_support.dylib`.

For an app bundle, copy the dylib to `Contents/Frameworks` and point the app's
load command at that copy:

```sh
install_name_tool -change libarc_support.dylib \
    @executable_path/../Frameworks/libarc_support.dylib \
    MyApp.app/Contents/MacOS/MyApp
```

For a system-wide install, use:

```sh
sudo install -m 755 build/Release/libarc_support.dylib /usr/local/lib/libarc_support.dylib
sudo install_name_tool -id /usr/local/lib/libarc_support.dylib /usr/local/lib/libarc_support.dylib
```

The public header is `include/libarc_support/arc_runtime.h`. Headers in `private/`
are internal build headers.
