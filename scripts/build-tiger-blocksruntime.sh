#!/bin/sh
set -eu

: "${ARC_CC:=/opt/local/bin/clang}"
: "${ARCH:=i386}"
: "${SDKROOT:=/Developer/SDKs/MacOSX10.4u.sdk}"
: "${MACOSX_DEPLOYMENT_TARGET:=10.4}"
: "${COMPILER_RT_TARBALL:=/opt/local/var/macports/distfiles/llvm/compiler-rt-3.4.src.tar.gz}"

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_ROOT="${TMPDIR:-/tmp}/libarc-support-blocksruntime"
SRC="$BUILD_ROOT/compiler-rt-3.4/BlocksRuntime"
OUT="$ROOT/vendor/blocks-runtime-tiger"

rm -rf "$BUILD_ROOT" "$OUT"
mkdir -p "$BUILD_ROOT" "$OUT/src" "$OUT/include" "$OUT/lib"
tar -xzf "$COMPILER_RT_TARBALL" -C "$BUILD_ROOT" compiler-rt-3.4/BlocksRuntime

cp "$SRC/runtime.c" "$SRC/data.c" "$SRC/Block.h" "$SRC/Block_private.h" "$OUT/src/"
cp "$SRC/Block.h" "$OUT/include/Block.h"

cat > "$OUT/src/config.h" <<'EOF'
#define HAVE_AVAILABILITY_MACROS_H 1
#define HAVE_TARGET_CONDITIONALS_H 1
#define HAVE_SYNC_BOOL_COMPARE_AND_SWAP_INT 1
#define HAVE_SYNC_BOOL_COMPARE_AND_SWAP_LONG 1
EOF

"$ARC_CC" \
    -arch "$ARCH" \
    -isysroot "$SDKROOT" \
    -mmacosx-version-min="$MACOSX_DEPLOYMENT_TARGET" \
    -I"$OUT/src" \
    -c "$OUT/src/runtime.c" \
    -o "$OUT/lib/runtime.o"

"$ARC_CC" \
    -arch "$ARCH" \
    -isysroot "$SDKROOT" \
    -mmacosx-version-min="$MACOSX_DEPLOYMENT_TARGET" \
    -I"$OUT/src" \
    -c "$OUT/src/data.c" \
    -o "$OUT/lib/data.o"

ar cr "$OUT/lib/libBlocksRuntime.a" "$OUT/lib/runtime.o" "$OUT/lib/data.o"
ranlib "$OUT/lib/libBlocksRuntime.a"

echo "$OUT/lib/libBlocksRuntime.a"
