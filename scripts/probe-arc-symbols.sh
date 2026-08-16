#!/bin/sh
set -eu

: "${CC:=xcrun clang}"
: "${ARCH:=x86_64}"
: "${MINVER:=10.4}"
: "${OBJCFLAGS:=}"

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUTDIR="${TMPDIR:-/tmp}/libarc_support_arc_probe"
mkdir -p "$OUTDIR"

probe() {
    name=$1
    minver=$2
    src=$3
    obj="$OUTDIR/$name-$ARCH.o"

    $CC $OBJCFLAGS -fobjc-arc -fblocks -mmacosx-version-min="$minver" -arch "$ARCH" -c "$ROOT/$src" -o "$obj"
    nm -u "$obj" | sort
}

echo "== strong/block =="
probe strong-block "$MINVER" tests/fixtures/arc-strong-block-symbols.m

echo "== weak =="
probe weak 10.7 tests/fixtures/arc-weak-symbols.m

echo "== explicit runtime =="
probe explicit-runtime 10.7 tests/fixtures/arc-explicit-runtime-symbols.m
