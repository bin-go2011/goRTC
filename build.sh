#!/usr/bin/env bash

PROJECT_DIR=$(pwd)
THIRD_PARTY_DIR="$PROJECT_DIR/third_party"
WEBRTC_REPO="https://webrtc.googlesource.com/src"
WEBRTC_DIR="$THIRD_PARTY_DIR/webrtc"
WEBRTC_SRC="$WEBRTC_DIR/src"
DEPOT_TOOLS_DIR="$THIRD_PARTY_DIR/depot_tools"
OS=$(go env GOOS)
ARCH=$(go env GOARCH)
CONFIG="Release"
COMMIT="c279861207c5b15fc51069e96595782350e0ac12"  # branch-heads/58

# Values are from,
#   https://github.com/golang/go/blob/master/src/go/build/syslist.go
#   https://chromium.googlesource.com/chromium/src/+/master/tools/gn/docs/reference.md

oses=",linux:linux,darwin:mac,windows:win,android:android,"
cpus=",386:x86,amd64:x64,arm:arm,"

get() {
	echo "$(expr "$1" : ".*,$2:\([^,]*\),.*")"
}

TARGET_OS=$(get $oses $OS)
TARGET_CPU=$(get $cpus $ARCH)
echo "Target OS: $TARGET_OS"
echo "Target CPU: $TARGET_CPU"

INCLUDE_DIR="$PROJECT_DIR/include"
LIB_DIR="$PROJECT_DIR/lib"

PATH="$PATH:$DEPOT_TOOLS_DIR"

mkdir -p $THIRD_PARTY_DIR

rm -rf $INCLUDE_DIR
rm -rf $LIB_DIR

mkdir -p $INCLUDE_DIR
mkdir -p $LIB_DIR

if [[ -d $DEPOT_TOOLS_DIR ]]; then
	echo "Syncing depot_tools ..."
	pushd $DEPOT_TOOLS_DIR >/dev/null
	git pull --rebase || exit 1
	popd >/dev/null
else
	echo "Getting depot_tools ..."
	mkdir -p $DEPOT_TOOLS_DIR
	git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git $DEPOT_TOOLS_DIR || exit 1
fi

if [[ -d $WEBRTC_DIR ]]; then
	echo "Syncing webrtc ..."

	pushd $WEBRTC_DIR >/dev/null
	# gclient sync || exit 1
	popd >/dev/null
else
	echo "Getting webrtc ..."
	mkdir -p $WEBRTC_DIR
	pushd $WEBRTC_DIR >/dev/null
    fetch --nohooks webrtc || exit 1
    gclient sync || exit 1
	popd >/dev/null
fi

if [ "$ARCH" = "arm" ]; then
	echo "Manually fetching arm sysroot"
	pushd $WEBRTC_SRC >/dev/null
	./build/linux/sysroot_scripts/install-sysroot.py --arch=arm || exit 1
	popd >/dev/null
fi

# echo "Cleaning webrtc ..."
# pushd $WEBRTC_SRC >/dev/null
# rm -rf out/$CONFIG
# popd >/dev/null

# echo "Building webrtc ..."
# pushd $WEBRTC_SRC >/dev/null
# gn gen out/$CONFIG --args="target_os=\"$TARGET_OS\" target_cpu=\"$TARGET_CPU\" is_debug=false" || exit 1
# ninja -C out/$CONFIG 
# popd >/dev/null

if [ $OS = 'mac' ]; then
    CP='gcp'
else
    CP='cp'
fi

echo "Copying headers ..."
pushd $WEBRTC_SRC >/dev/null
  find . -name '*.h' -exec $CP --parents '{}' $INCLUDE_DIR ';'
popd >/dev/null

echo "Concatenating libraries ..."
pushd $WEBRTC_SRC/out/$CONFIG/obj >/dev/null
if [ "$OS" = "darwin" ]; then
	find . -name '*.o' > filelist
	libtool -static -o libwebrtc-magic.a -filelist filelist
	strip -S -x -o libwebrtc-magic.a libwebrtc-magic.a
elif [ "$ARCH" = "arm" ]; then
	arm-linux-gnueabihf-ar crs libwebrtc-magic.a $(find . -name '*.o' -not -name '*.main.o')
else
	ar crs libwebrtc-magic.a $(find . -name '*.o' -not -name '*.main.o')
fi
OUT_LIBRARY=$LIB_DIR/libwebrtc-$OS-$ARCH-magic.a
mv libwebrtc-magic.a ${OUT_LIBRARY}
echo "Built ${OUT_LIBRARY}"

# find and copy libraries
find . -name '*.a' -exec $CP --parents '{}' $LIB_DIR ';'
popd >/dev/null

echo "Build complete."