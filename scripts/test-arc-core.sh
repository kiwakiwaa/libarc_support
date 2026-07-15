#!/bin/sh
set -eu

: "${ARCH:=i386}"
: "${CONFIGURATION:=Debug}"
: "${ARC_BUILD_SYSTEM:=xcodebuild}"
: "${ARC_CC:=/Developer/usr/bin/llvm-gcc-4.2}"
: "${ARC_BLOCKS_CC:=$ARC_CC}"
: "${MACOSX_DEPLOYMENT_TARGET:=10.4}"

: "${SDKROOT:=}"

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$ROOT/build/$CONFIGURATION"
DYLIB="$BUILD_DIR/libarc_support.dylib"
EXPORTS_FILE="$ROOT/exports/libarc_support.exp"
TEST_EXE="${TMPDIR:-/tmp}/arc_core_lifetime-$ARCH"
RV_TEST_EXE="${TMPDIR:-/tmp}/arc_return_value_lifetime-$ARCH"
WEAK_TEST_EXE="${TMPDIR:-/tmp}/arc_weak_lifetime-$ARCH"
WEAK_PRUNE_TEST_EXE="${TMPDIR:-/tmp}/arc_weak_table_pruning-$ARCH"
WEAK_CONCURRENCY_TEST_EXE="${TMPDIR:-/tmp}/arc_weak_concurrency-$ARCH"
POOL_TEST_EXE="${TMPDIR:-/tmp}/arc_pool_lifetime-$ARCH"
BRIDGE_TEST_EXE="${TMPDIR:-/tmp}/arc_bridge_identity-$ARCH"
ALLOC_TEST_EXE="${TMPDIR:-/tmp}/arc_alloc_lifetime-$ARCH"
PROPERTY_TEST_EXE="${TMPDIR:-/tmp}/arc_property_runtime-$ARCH"
PROPERTY_CODEGEN_TEST_EXE="${TMPDIR:-/tmp}/arc_property_codegen-$ARCH"
BLOCK_CODEGEN_TEST_EXE="${TMPDIR:-/tmp}/arc_block_codegen-$ARCH"

if [ "${BLOCKS_RUNTIME_LDFLAGS+set}" != set ]; then
    BLOCKS_RUNTIME_LDFLAGS=
    for dir in /opt/local/lib /usr/local/lib "$ROOT/vendor/blocks-runtime-tiger/lib"; do
        if [ -e "$dir/libBlocksRuntime.dylib" ] || [ -e "$dir/libBlocksRuntime.a" ]; then
            BLOCKS_RUNTIME_LDFLAGS="-L$dir -lBlocksRuntime"
            break
        fi
    done
fi

cd "$ROOT"

SDK_FLAGS=
if [ -n "$SDKROOT" ]; then
    SDK_FLAGS="-isysroot $SDKROOT"
fi

COMMON_CFLAGS="-arch $ARCH $SDK_FLAGS -Iinclude -Iprivate -fvisibility=hidden -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"

build_with_xcodebuild()
{
    XCODE_SDKROOT="${SDKROOT:-macosx}"
    xcodebuild \
        -target libarc_support \
        -configuration "$CONFIGURATION" \
        ARCHS="$ARCH" \
        ONLY_ACTIVE_ARCH=NO \
        SDKROOT="$XCODE_SDKROOT" \
        MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
        BLOCKS_RUNTIME_LDFLAGS="$BLOCKS_RUNTIME_LDFLAGS" \
        OTHER_LDFLAGS="-lobjc -framework CoreFoundation -framework Foundation $BLOCKS_RUNTIME_LDFLAGS -exported_symbols_list exports/libarc_support.exp" \
        build
}

build_manually()
{
    mkdir -p "$BUILD_DIR"
    OBJECTS=
    for src in \
        src/arc_core.m \
        src/arc_alloc.m \
        src/arc_bridge.m \
        src/arc_pool.m \
        src/arc_weak_table.m \
        src/arc_weak_runtime.m
    do
        obj="$BUILD_DIR/$(basename "$src" .m).o"
        $ARC_CC $COMMON_CFLAGS -c "$src" -o "$obj"
        OBJECTS="$OBJECTS $obj"
    done

    $ARC_CC \
        -arch "$ARCH" \
        $SDK_FLAGS \
        -mmacosx-version-min="$MACOSX_DEPLOYMENT_TARGET" \
        -dynamiclib \
        -install_name "$(basename "$DYLIB")" \
        -exported_symbols_list "$EXPORTS_FILE" \
        $OBJECTS \
        -framework CoreFoundation \
        -framework Foundation \
        -lobjc \
        $BLOCKS_RUNTIME_LDFLAGS \
        -o "$DYLIB"
}

case "$ARC_BUILD_SYSTEM" in
    xcodebuild)
        build_with_xcodebuild
        ;;
    manual)
        build_manually
        ;;
    *)
        echo "unknown ARC_BUILD_SYSTEM: $ARC_BUILD_SYSTEM" >&2
        exit 1
        ;;
esac

exported_symbols()
{
    if nm -arch "$ARCH" -gU "$DYLIB" >/dev/null 2>&1; then
        nm -arch "$ARCH" -gU "$DYLIB" | awk 'NF == 3 && $2 ~ /^[A-Z]$/ && $2 != "U" {print $3}'
    else
        nm -arch "$ARCH" -g "$DYLIB" | awk 'NF == 3 && $2 ~ /^[A-Z]$/ && $2 != "U" {print $3}'
    fi
}

while IFS= read -r symbol; do
    exported_symbols | grep -qx "$symbol"
done < "$EXPORTS_FILE"

unexpected_symbols=$(exported_symbols | grep -vx -f "$EXPORTS_FILE" || true)
if [ -n "$unexpected_symbols" ]; then
    echo "unexpected exported symbols:" >&2
    echo "$unexpected_symbols" >&2
    exit 1
fi

$ARC_BLOCKS_CC \
    $COMMON_CFLAGS \
    -fblocks \
    tests/arc_core_lifetime.m \
    "$DYLIB" \
    -framework Foundation \
    -lobjc \
    $BLOCKS_RUNTIME_LDFLAGS \
    -o "$TEST_EXE"

DYLD_LIBRARY_PATH="$BUILD_DIR" "$TEST_EXE"

$ARC_CC \
    $COMMON_CFLAGS \
    tests/arc_return_value_lifetime.m \
    "$DYLIB" \
    -framework Foundation \
    -lobjc \
    $BLOCKS_RUNTIME_LDFLAGS \
    -o "$RV_TEST_EXE"

DYLD_LIBRARY_PATH="$BUILD_DIR" "$RV_TEST_EXE"

$ARC_CC \
    $COMMON_CFLAGS \
    tests/arc_weak_lifetime.m \
    "$DYLIB" \
    -framework Foundation \
    -lobjc \
    $BLOCKS_RUNTIME_LDFLAGS \
    -o "$WEAK_TEST_EXE"

DYLD_LIBRARY_PATH="$BUILD_DIR" "$WEAK_TEST_EXE"

$ARC_BLOCKS_CC \
    $COMMON_CFLAGS \
    -DARC_WEAK_TESTING=1 \
    -fblocks \
    -Isrc \
    -Iprivate \
    tests/arc_weak_table_pruning.m \
    src/arc_core.m \
    src/arc_weak_table.m \
    src/arc_weak_runtime.m \
    -framework Foundation \
    -framework CoreFoundation \
    -lobjc \
    $BLOCKS_RUNTIME_LDFLAGS \
    -o "$WEAK_PRUNE_TEST_EXE"

"$WEAK_PRUNE_TEST_EXE"

$ARC_CC \
    $COMMON_CFLAGS \
    tests/arc_weak_concurrency.m \
    "$DYLIB" \
    -framework Foundation \
    -lobjc \
    $BLOCKS_RUNTIME_LDFLAGS \
    -o "$WEAK_CONCURRENCY_TEST_EXE"

DYLD_LIBRARY_PATH="$BUILD_DIR" "$WEAK_CONCURRENCY_TEST_EXE"

$ARC_CC \
    $COMMON_CFLAGS \
    tests/arc_pool_lifetime.m \
    "$DYLIB" \
    -framework Foundation \
    -lobjc \
    $BLOCKS_RUNTIME_LDFLAGS \
    -o "$POOL_TEST_EXE"

DYLD_LIBRARY_PATH="$BUILD_DIR" "$POOL_TEST_EXE"

$ARC_CC \
    $COMMON_CFLAGS \
    tests/arc_bridge_identity.m \
    "$DYLIB" \
    -framework Foundation \
    -lobjc \
    $BLOCKS_RUNTIME_LDFLAGS \
    -o "$BRIDGE_TEST_EXE"

DYLD_LIBRARY_PATH="$BUILD_DIR" "$BRIDGE_TEST_EXE"

$ARC_CC \
    $COMMON_CFLAGS \
    tests/arc_alloc_lifetime.m \
    "$DYLIB" \
    -framework Foundation \
    -lobjc \
    $BLOCKS_RUNTIME_LDFLAGS \
    -o "$ALLOC_TEST_EXE"

DYLD_LIBRARY_PATH="$BUILD_DIR" "$ALLOC_TEST_EXE"

$ARC_CC \
    $COMMON_CFLAGS \
    tests/arc_property_runtime.m \
    "$DYLIB" \
    -framework Foundation \
    -lobjc \
    $BLOCKS_RUNTIME_LDFLAGS \
    -o "$PROPERTY_TEST_EXE"

DYLD_LIBRARY_PATH="$BUILD_DIR" "$PROPERTY_TEST_EXE"

if [ -n "${ARC_CODEGEN_CC:-}" ]; then
    $ARC_CODEGEN_CC \
        $COMMON_CFLAGS \
        -Xclang -fobjc-arc \
        -fobjc-runtime=macosx-fragile-10.7 \
        -Xclang -fobjc-runtime-has-weak \
        tests/arc_property_codegen.m \
        "$DYLIB" \
        -framework Foundation \
        -lobjc \
        $BLOCKS_RUNTIME_LDFLAGS \
        -o "$PROPERTY_CODEGEN_TEST_EXE"

    DYLD_LIBRARY_PATH="$BUILD_DIR" "$PROPERTY_CODEGEN_TEST_EXE"

    $ARC_CODEGEN_CC \
        $COMMON_CFLAGS \
        -Xclang -fobjc-arc \
        -fblocks \
        -fobjc-runtime=macosx-fragile-10.7 \
        -Xclang -fobjc-runtime-has-weak \
        tests/arc_block_codegen.m \
        "$DYLIB" \
        -framework Foundation \
        -lobjc \
        $BLOCKS_RUNTIME_LDFLAGS \
        -o "$BLOCK_CODEGEN_TEST_EXE"

    DYLD_LIBRARY_PATH="$BUILD_DIR" "$BLOCK_CODEGEN_TEST_EXE"
fi
