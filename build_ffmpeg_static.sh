#!/bin/bash
set -e

# Configuration
PROJECT_ROOT="/Users/k2zoo/Documents/coding/livid"
SRC_DIR="$PROJECT_ROOT/src"
BUILD_DIR="$PROJECT_ROOT/build"

# Ensure directories exist
mkdir -p "$SRC_DIR"
mkdir -p "$BUILD_DIR"

# Export paths for pkg-config and binaries
export PATH="$BUILD_DIR/bin:$PATH"
export PKG_CONFIG_PATH="$BUILD_DIR/lib/pkgconfig:/opt/homebrew/lib/pkgconfig:$PKG_CONFIG_PATH"

# Compiler flags for ARM64 macOS
export CFLAGS="-arch arm64 -fno-stack-check -I$BUILD_DIR/include"
export CXXFLAGS="-arch arm64 -fno-stack-check -I$BUILD_DIR/include"
export LDFLAGS="-L$BUILD_DIR/lib"

echo "🚀 Starting static FFmpeg build..."
echo "📂 Sources: $SRC_DIR"
echo "📂 Build Artifacts: $BUILD_DIR"

# ======================
# 1. Build libzimg
# ======================
echo "======================"
echo "Build libzimg"
echo "======================"
cd "$SRC_DIR"
if [ ! -d "zimg" ]; then
    echo "📥 Cloning zimg..."
    git clone --recursive https://github.com/sekrit-twc/zimg.git
fi
cd zimg
git pull || true

echo "🧹 Cleaning previous libzimg build..."
make distclean || true
./autogen.sh

echo "🏗️ Configuring libzimg (static)..."
./configure \
    --prefix="$BUILD_DIR" \
    --enable-static \
    --disable-shared \
    --with-pic

echo "⚙️ Building libzimg..."
make -j$(sysctl -n hw.ncpu)
make install

echo "✅ libzimg installed"

# ======================
# 2. Build x264
# ======================
echo "======================"
echo "Build x264"
echo "======================"
cd "$SRC_DIR"
if [ ! -d "x264" ]; then
    echo "📥 Cloning x264..."
    git clone https://code.videolan.org/videolan/x264.git
fi
cd x264
git pull || true

echo "🧹 Cleaning previous x264 build..."
make distclean || true

echo "🏗️ Configuring x264..."
./configure \
    --prefix="$BUILD_DIR" \
    --enable-static \
    --enable-pic \
    --disable-cli

echo "⚙️ Building x264..."
make -j$(sysctl -n hw.ncpu)
make install

echo "✅ x264 installed"

# ======================
# 3. Build x265 (Multilib: 8-bit + 10-bit)
# ======================
echo "======================"
echo "Build x265 (8-bit + 10-bit)"
echo "======================"
cd "$SRC_DIR"
if [ ! -d "x265_git" ]; then
    echo "📥 Cloning x265..."
    git clone https://bitbucket.org/multicoreware/x265_git.git
fi
cd x265_git/build/linux

echo "🧹 Cleaning previous x265 build..."
rm -rf build_10bit build_8bit
mkdir -p build_10bit build_8bit

# --- 1. Build 10-bit Static Library ---
echo "🏗️ Configuring x265 (10-bit)..."
cd build_10bit
cmake -G "Unix Makefiles" ../../../source \
    -DCMAKE_INSTALL_PREFIX="$BUILD_DIR" \
    -DENABLE_SHARED=OFF \
    -DENABLE_CLI=OFF \
    -DHIGH_BIT_DEPTH=ON \
    -DENABLE_HDR10_PLUS=ON \
    -DEXPORT_C_API=OFF \
    -DCMAKE_ASM_FLAGS="-fPIC" \
    -DCMAKE_CXX_FLAGS="-arch arm64 -fPIC" \
    -DCMAKE_C_FLAGS="-arch arm64 -fPIC"

echo "⚙️ Building x265 (10-bit)..."
make -j$(sysctl -n hw.ncpu)
cp libx265.a ../build_8bit/libx265_main10.a
cd ..

# --- 2. Build 8-bit Static Library & Link 10-bit ---
echo "🏗️ Configuring x265 (8-bit)..."
cd build_8bit
cmake -G "Unix Makefiles" ../../../source \
    -DCMAKE_INSTALL_PREFIX="$BUILD_DIR" \
    -DENABLE_SHARED=OFF \
    -DENABLE_CLI=OFF \
    -DEXTRA_LIB="x265_main10.a" \
    -DEXTRA_LINK_FLAGS="-L." \
    -DLINKED_10BIT=ON \
    -DCMAKE_ASM_FLAGS="-fPIC" \
    -DCMAKE_CXX_FLAGS="-arch arm64 -fPIC" \
    -DCMAKE_C_FLAGS="-arch arm64 -fPIC"

echo "⚙️ Building x265 (8-bit)..."
make -j$(sysctl -n hw.ncpu)

# --- 3. Merge Libraries for macOS (libtool) ---
# Since we are building static, we need to physically merge the archives 
# to ensure ffmpeg picks up both 8-bit and 10-bit symbols.
echo "🔗 Merging 8-bit and 10-bit libraries..."
mv libx265.a libx265_main.a
libtool -static -o libx265.a libx265_main.a libx265_main10.a

echo "📦 Installing x265..."
make install

echo "✅ x265 (Multilib) installed"

# ======================
# 4. Build libdav1d
# ======================
echo "======================"
echo "Build libdav1d"
echo "======================"
cd "$SRC_DIR"
if [ ! -d "dav1d" ]; then
    echo "📥 Cloning dav1d..."
    git clone https://code.videolan.org/videolan/dav1d.git
fi
cd dav1d
git pull || true

echo "🧹 Cleaning previous dav1d build..."
rm -rf build

echo "🏗️ Configuring dav1d with meson..."
meson setup build \
    --prefix="$BUILD_DIR" \
    --buildtype=release \
    --default-library=static \
    -Denable_asm=true \
    -Denable_tools=false \
    -Denable_tests=false

echo "⚙️ Building dav1d..."
ninja -C build
ninja -C build install

echo "✅ dav1d installed"

# ======================
# 5. Build libplacebo
# ======================
echo "======================"
echo "Build libplacebo"
echo "======================"
cd "$SRC_DIR"
if [ ! -d "libplacebo" ]; then
    echo "📥 Cloning libplacebo..."
    git clone --recursive https://github.com/haasn/libplacebo.git
fi
cd libplacebo
git pull || true
git submodule update --init --recursive

echo "🧹 Cleaning previous libplacebo build..."
rm -rf build

echo "🏗️ Configuring libplacebo with meson..."
meson setup build \
    --prefix="$BUILD_DIR" \
    --buildtype=release \
    --default-library=static \
    -Dvulkan=enabled \
    -Dshaderc=enabled \
    -Dlcms=enabled \
    -Dd3d11=disabled \
    -Ddemos=false \
    -Dtests=false

echo "⚙️ Building libplacebo..."
meson compile -C build
meson install -C build

echo "✅ libplacebo installed"

# Manually ensure .pc file exists if needed (meson usually handles it)
PLACEBO_PC="$BUILD_DIR/lib/pkgconfig/libplacebo.pc"
if [ ! -f "$PLACEBO_PC" ]; then
    echo "📝 Creating libplacebo.pc manually..."
    mkdir -p "$BUILD_DIR/lib/pkgconfig"
    cat > "$PLACEBO_PC" << EOF
prefix=$BUILD_DIR
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libplacebo
Description: Reusable library for GPU-accelerated video/image rendering
Version: 7.0.0
Libs: -L\${libdir} -lplacebo
Libs.private: -lshaderc_shared -llcms2 -lc++
Cflags: -I\${includedir}
EOF
fi

# ======================
# 6. Build FFmpeg
# ======================
echo "======================"
echo "Build FFmpeg"
echo "======================"
cd "$SRC_DIR"
if [ ! -d "ffmpeg" ]; then
    echo "📥 Cloning FFmpeg..."
    git clone https://git.ffmpeg.org/ffmpeg.git
fi
cd ffmpeg

echo "🧹 Cleaning up FFmpeg..."
make distclean || true

echo "🏗️ Configuring FFmpeg..."
./configure \
    --prefix="$BUILD_DIR" \
    --enable-static \
    --disable-shared \
    --enable-gpl \
    --enable-version3 \
    --enable-libx264 \
    --enable-libx265 \
    --enable-libzimg \
    --enable-libplacebo \
    --enable-libdav1d \
    --disable-doc \
    --disable-avdevice \
    --disable-swresample \
    --enable-avfilter \
    --disable-network \
    --disable-everything \
    --enable-decoder=vp9,vp8,av1,libdav1d,av1_videotoolbox,hevc,hevc_videotoolbox,h264,h264_videotoolbox \
    --enable-encoder=libx264,libx265,h264_videotoolbox,hevc_videotoolbox \
    --enable-demuxer=matroska,mov,m4v,mp4 \
    --enable-muxer=mov,mp4 \
    --enable-parser=vp9,av1,vp8,h264,hevc \
    --enable-filter=tonemap,colorspace,scale,format,setpts,zscale,libplacebo \
    --enable-bsf=vp9_superframe_split,vp9_superframe,h264_mp4toannexb,hevc_mp4toannexb \
    --enable-protocol=file \
    --enable-videotoolbox \
    --enable-pic \
    --enable-neon \
    --enable-asm \
    --pkg-config-flags="--static" \
    --extra-cflags="-I$BUILD_DIR/include -I/opt/homebrew/include -fno-stack-check" \
    --extra-ldflags="-L$BUILD_DIR/lib -L/opt/homebrew/lib" \
    --extra-libs="-lplacebo -lshaderc_shared -llcms2 -lzimg -ldav1d -lx264 -lx265 -lc++ -framework Metal -framework CoreVideo -framework IOSurface -framework QuartzCore -framework Foundation"

echo "⚙️ Building FFmpeg..."
make -j$(sysctl -n hw.ncpu)
make install

echo "✅ FFmpeg static build completed!"
echo "📍 Artifacts are in: $BUILD_DIR"
ls -lh "$BUILD_DIR/bin/"

# ======================
# 7. Copy to WebMSupport
# ======================
DEST_DIR="$PROJECT_ROOT/WebMSupport/Frameworks/FFmpeg.xcframework"
REAL_DEST_DIR="${DEST_DIR%.xcframework}"

echo "📦 Copying libraries and headers to $DEST_DIR..."
mkdir -p "$REAL_DEST_DIR/lib"
mkdir -p "$REAL_DEST_DIR/include"

# Copy static libraries
cp -f "$BUILD_DIR/lib/"*.a "$REAL_DEST_DIR/lib/"

# Copy headers
cp -Rf "$BUILD_DIR/include/"* "$REAL_DEST_DIR/include/"

echo "✅ FFmpeg static libraries copied to $REAL_DEST_DIR"