#!/bin/bash
# build_opus.sh — Build Opus with FARGAN/LPCNet for iOS (arm64)
#
# Usage: ./Scripts/build_opus.sh <opus-source-dir> <output-dir>

set -e

OPUS_SRC="${1:?Usage: $0 <opus-source-dir> <output-dir>}"
OUTPUT_DIR="${2:?Usage: $0 <opus-source-dir> <output-dir>}"
IOS_DEPLOYMENT_TARGET="16.0"

# iOS SDK paths
SDKROOT=$(xcrun --sdk iphoneos --show-sdk-path)
CC=$(xcrun --sdk iphoneos --find clang)
CXX=$(xcrun --sdk iphoneos --find clang++)

mkdir -p "$OUTPUT_DIR"
cd "$OPUS_SRC"

# If Opus uses autotools:
if [ -f "configure.ac" ]; then
    autoreconf -fi
    
    # arm64 (iPhone/iPad)
    mkdir -p build-ios-arm64
    cd build-ios-arm64
    
    ../configure \
        --host=aarch64-apple-darwin \
        --prefix="$OUTPUT_DIR/arm64" \
        --enable-static \
        --disable-shared \
        --disable-doc \
        --disable-extra-programs \
        CC="$CC" \
        CXX="$CXX" \
        CFLAGS="-arch arm64 -isysroot $SDKROOT -mios-version-min=$IOS_DEPLOYMENT_TARGET -O2 -fembed-bitcode" \
        CXXFLAGS="-arch arm64 -isysroot $SDKROOT -mios-version-min=$IOS_DEPLOYMENT_TARGET -O2 -fembed-bitcode" \
        LDFLAGS="-arch arm64 -isysroot $SDKROOT"
    
    make -j$(sysctl -n hw.ncpu)
    make install
    cd ..
fi

# If Opus uses CMake:
if [ -f "CMakeLists.txt" ] && [ ! -f "configure.ac" ]; then
    mkdir -p build-ios-arm64
    cd build-ios-arm64
    
    cmake .. \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=$IOS_DEPLOYMENT_TARGET \
        -DCMAKE_INSTALL_PREFIX="$OUTPUT_DIR/arm64" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF
    
    make -j$(sysctl -n hw.ncpu)
    make install
    cd ..
fi

echo "Opus for iOS build complete: $OUTPUT_DIR"
