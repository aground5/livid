# Makefile for building static FFmpeg on macOS (Apple Silicon)
# Based on build_ffmpeg_static.sh

# ==============================================================================
# Configuration
# ==============================================================================
PROJECT_ROOT := $(shell pwd)
SRC_DIR      := $(PROJECT_ROOT)/src
BUILD_DIR    := $(PROJECT_ROOT)/build
BIN_DIR      := $(BUILD_DIR)/bin
LIB_DIR      := $(BUILD_DIR)/lib
INCLUDE_DIR  := $(BUILD_DIR)/include

# Parallel jobs used for make/ninja
JOBS := $(shell sysctl -n hw.ncpu)

# Environment Variables
export PATH := $(BIN_DIR):$(PATH)
export PKG_CONFIG_PATH := $(LIB_DIR)/pkgconfig:/opt/homebrew/lib/pkgconfig:$(PKG_CONFIG_PATH)

# Compiler Flags (macOS ARM64)
export CFLAGS   := -arch arm64 -fno-stack-check -I$(INCLUDE_DIR)
export CXXFLAGS := -arch arm64 -fno-stack-check -I$(INCLUDE_DIR)
export LDFLAGS  := -L$(LIB_DIR)

# Source Repositories
REPO_ZIMG       := https://github.com/sekrit-twc/zimg.git
REPO_X264       := https://code.videolan.org/videolan/x264.git
REPO_X265       := https://bitbucket.org/multicoreware/x265_git.git
REPO_DAV1D      := https://code.videolan.org/videolan/dav1d.git
REPO_LIBPLACEBO := https://github.com/haasn/libplacebo.git
REPO_FFMPEG     := https://git.ffmpeg.org/ffmpeg.git
REPO_YOUTUBEKIT := https://github.com/alexeichhorn/YouTubeKit.git
COMMIT_YOUTUBEKIT := 068403f2b7523c7620eab257e64402f722821e05

# ==============================================================================
# Targets
# ==============================================================================

.PHONY: all clean clean-all dirs zimg x264 x265 dav1d libplacebo ffmpeg copy-framework \
        clean-zimg clean-x264 clean-x265 clean-dav1d clean-libplacebo clean-ffmpeg \
        clean-xcode-cache resolve-deps build-xcode build-release release-dmg release-all appcast run

dirs:
	@mkdir -p $(SRC_DIR)
	@mkdir -p $(BUILD_DIR)

# ==============================================================================
# 1. zimg
# ==============================================================================
ZIMG_DIR := $(SRC_DIR)/zimg
ZIMG_LIB := $(LIB_DIR)/libzimg.a

$(ZIMG_DIR): | dirs
	@echo "📥 Cloning zimg..."
	cd $(SRC_DIR) && git clone --recursive $(REPO_ZIMG) zimg

$(ZIMG_LIB): | $(ZIMG_DIR)
	@echo "🏗️ Building zimg..."
	cd $(ZIMG_DIR) && git pull || true
	cd $(ZIMG_DIR) && if [ ! -f configure ]; then ./autogen.sh; fi
	cd $(ZIMG_DIR) && if [ ! -f Makefile ]; then \
		./configure --prefix="$(BUILD_DIR)" --enable-static --disable-shared --with-pic; \
	fi
	$(MAKE) -C $(ZIMG_DIR) -j$(JOBS)
	$(MAKE) -C $(ZIMG_DIR) install
	@echo "✅ zimg installed"

zimg: $(ZIMG_LIB)

# ==============================================================================
# 2. x264
# ==============================================================================
X264_DIR := $(SRC_DIR)/x264
X264_LIB := $(LIB_DIR)/libx264.a

$(X264_DIR): | dirs
	@echo "📥 Cloning x264..."
	cd $(SRC_DIR) && git clone $(REPO_X264) x264

$(X264_LIB): | $(X264_DIR)
	@echo "🏗️ Building x264..."
	cd $(X264_DIR) && git pull || true
	cd $(X264_DIR) && if [ ! -f config.mak ]; then \
		./configure --prefix="$(BUILD_DIR)" --enable-static --enable-pic --disable-cli; \
	fi
	$(MAKE) -C $(X264_DIR) -j$(JOBS)
	$(MAKE) -C $(X264_DIR) install
	@echo "✅ x264 installed"

x264: $(X264_LIB)

# ==============================================================================
# 3. x265 (Multilib: 10bit + 8bit)
# ==============================================================================
X265_DIR      := $(SRC_DIR)/x265_git
X265_BUILD_DIR := $(X265_DIR)/build/linux
X265_LIB      := $(LIB_DIR)/libx265.a

$(X265_DIR): | dirs
	@echo "📥 Cloning x265..."
	cd $(SRC_DIR) && git clone $(REPO_X265) x265_git

$(X265_LIB): | $(X265_DIR)
	@echo "🏗️ Building x265 (Multilib)..."
	cd $(X265_DIR) && git pull || true
	@mkdir -p $(X265_BUILD_DIR)/build_10bit
	@mkdir -p $(X265_BUILD_DIR)/build_8bit
	
	@echo "⚙️ Configuring & Building x265 10-bit..."
	cd $(X265_BUILD_DIR)/build_10bit && \
	cmake -G "Unix Makefiles" ../../../source \
		-DCMAKE_INSTALL_PREFIX="$(BUILD_DIR)" \
		-DENABLE_SHARED=OFF -DENABLE_CLI=OFF \
		-DHIGH_BIT_DEPTH=ON -DENABLE_HDR10_PLUS=ON -DEXPORT_C_API=OFF \
		-DCMAKE_ASM_FLAGS="-fPIC" \
		-DCMAKE_CXX_FLAGS="-arch arm64 -fPIC" \
		-DCMAKE_C_FLAGS="-arch arm64 -fPIC" && \
	$(MAKE) -j$(JOBS) && \
	cp libx265.a ../build_8bit/libx265_main10.a

	@echo "⚙️ Configuring & Building x265 8-bit linked with 10-bit..."
	cd $(X265_BUILD_DIR)/build_8bit && \
	cmake -G "Unix Makefiles" ../../../source \
		-DCMAKE_INSTALL_PREFIX="$(BUILD_DIR)" \
		-DENABLE_SHARED=OFF -DENABLE_CLI=OFF \
		-DEXTRA_LIB="x265_main10.a" -DEXTRA_LINK_FLAGS="-L." -DLINKED_10BIT=ON \
		-DCMAKE_ASM_FLAGS="-fPIC" \
		-DCMAKE_CXX_FLAGS="-arch arm64 -fPIC" \
		-DCMAKE_C_FLAGS="-arch arm64 -fPIC" && \
	$(MAKE) -j$(JOBS)

	@echo "🔗 Merging x265 libraries..."
	cd $(X265_BUILD_DIR)/build_8bit && \
	mv libx265.a libx265_main.a && \
	libtool -static -o libx265.a libx265_main.a libx265_main10.a && \
	$(MAKE) install
	@echo "✅ x265 installed"

x265: $(X265_LIB)

# ==============================================================================
# 4. dav1d
# ==============================================================================
DAV1D_DIR := $(SRC_DIR)/dav1d
DAV1D_LIB := $(LIB_DIR)/libdav1d.a

$(DAV1D_DIR): | dirs
	@echo "📥 Cloning dav1d..."
	cd $(SRC_DIR) && git clone $(REPO_DAV1D) dav1d

$(DAV1D_LIB): | $(DAV1D_DIR)
	@echo "🏗️ Building dav1d..."
	cd $(DAV1D_DIR) && git pull || true
	@mkdir -p $(DAV1D_DIR)/build
	cd $(DAV1D_DIR) && \
	if [ ! -f build/build.ninja ]; then \
		meson setup build --prefix="$(BUILD_DIR)" --buildtype=release \
		--default-library=static -Denable_asm=true -Denable_tools=false -Denable_tests=false; \
	fi
	ninja -C $(DAV1D_DIR)/build
	ninja -C $(DAV1D_DIR)/build install
	@echo "✅ dav1d installed"

dav1d: $(DAV1D_LIB)

# ==============================================================================
# 5. libplacebo
# ==============================================================================
PLACEBO_DIR := $(SRC_DIR)/libplacebo
PLACEBO_LIB := $(LIB_DIR)/libplacebo.a
PLACEBO_PC  := $(LIB_DIR)/pkgconfig/libplacebo.pc

$(PLACEBO_DIR): | dirs
	@echo "📥 Cloning libplacebo..."
	cd $(SRC_DIR) && git clone --recursive $(REPO_LIBPLACEBO) libplacebo

$(PLACEBO_LIB): | $(PLACEBO_DIR)
	@echo "🏗️ Building libplacebo..."
	cd $(PLACEBO_DIR) && git pull || true
	cd $(PLACEBO_DIR) && git submodule update --init --recursive
	@mkdir -p $(PLACEBO_DIR)/build
	cd $(PLACEBO_DIR) && \
	if [ ! -f build/build.ninja ]; then \
		meson setup build --prefix="$(BUILD_DIR)" --buildtype=release \
		--default-library=static -Dvulkan=enabled -Dshaderc=enabled \
		-Dlcms=enabled -Dd3d11=disabled -Ddemos=false -Dtests=false; \
	fi
	ninja -C $(PLACEBO_DIR)/build
	ninja -C $(PLACEBO_DIR)/build install
	
	@# Manual PC file creation if missing (sometimes meson issues with static)
	@if [ ! -f $(PLACEBO_PC) ]; then \
		echo "📝 Creating libplacebo.pc manually..."; \
		mkdir -p $(LIB_DIR)/pkgconfig; \
		echo "prefix=$(BUILD_DIR)" > $(PLACEBO_PC); \
		echo "exec_prefix=\$${prefix}" >> $(PLACEBO_PC); \
		echo "libdir=\$${exec_prefix}/lib" >> $(PLACEBO_PC); \
		echo "includedir=\$${prefix}/include" >> $(PLACEBO_PC); \
		echo "" >> $(PLACEBO_PC); \
		echo "Name: libplacebo" >> $(PLACEBO_PC); \
		echo "Description: GPU-accelerated video/image rendering" >> $(PLACEBO_PC); \
		echo "Version: 7.0.0" >> $(PLACEBO_PC); \
		echo "Libs: -L\$${libdir} -lplacebo" >> $(PLACEBO_PC); \
		echo "Libs.private: -lshaderc_shared -llcms2 -lc++" >> $(PLACEBO_PC); \
		echo "Cflags: -I\$${includedir}" >> $(PLACEBO_PC); \
	fi
	@echo "✅ libplacebo installed"

libplacebo: $(PLACEBO_LIB)

# ==============================================================================
# 6. FFmpeg
# ==============================================================================
FFMPEG_DIR := $(SRC_DIR)/ffmpeg
FFMPEG_BIN := $(BIN_DIR)/ffmpeg

FFMPEG_CONFIG_FLAGS := \
	--prefix="$(BUILD_DIR)" \
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
	--extra-cflags="-I$(INCLUDE_DIR) -I/opt/homebrew/include -fno-stack-check" \
	--extra-ldflags="-L$(LIB_DIR) -L/opt/homebrew/lib" \
	--extra-libs="-lplacebo -lshaderc_shared -llcms2 -lzimg -ldav1d -lx264 -lx265 -lc++ -framework Metal -framework CoreVideo -framework IOSurface -framework QuartzCore -framework Foundation"

$(FFMPEG_DIR): | dirs
	@echo "📥 Cloning FFmpeg..."
	cd $(SRC_DIR) && git clone $(REPO_FFMPEG) ffmpeg

$(FFMPEG_BIN): $(ZIMG_LIB) $(X264_LIB) $(X265_LIB) $(DAV1D_LIB) $(PLACEBO_LIB) | $(FFMPEG_DIR)
	@echo "🏗️ Building FFmpeg..."
	cd $(FFMPEG_DIR) && \
	if [ ! -f config.mak ]; then \
		echo "⚙️ Configuring FFmpeg..."; \
		./configure $(FFMPEG_CONFIG_FLAGS); \
	fi
	$(MAKE) -C $(FFMPEG_DIR) -j$(JOBS)
	$(MAKE) -C $(FFMPEG_DIR) install
	@echo "✅ FFmpeg installed"

ffmpeg: $(FFMPEG_BIN)

# ==============================================================================
# 7. Copy Frameworks
# ==============================================================================
FRAMEWORK_DEST := $(PROJECT_ROOT)/Packages/WebMSupport/Frameworks/FFmpeg.xcframework
REAL_DEST      := $(FRAMEWORK_DEST:.xcframework=)

copy-framework: ffmpeg
	@echo "📦 Copying libraries and headers to $(REAL_DEST)..."
	@mkdir -p "$(REAL_DEST)/lib"
	@mkdir -p "$(REAL_DEST)/include"
	@cp -f "$(LIB_DIR)/"*.a "$(REAL_DEST)/lib/"
	@cp -Rf "$(INCLUDE_DIR)/"* "$(REAL_DEST)/include/"
	@echo "✅ Copy complete!"

# ==============================================================================
# Clean
# ==============================================================================

clean-zimg:
	rm -f $(ZIMG_LIB)
	rm -rf $(ZIMG_DIR)/Makefile

clean-x264:
	rm -f $(X264_LIB)
	rm -rf $(X264_DIR)/config.mak

clean-x265:
	@echo "🧹 Cleaning x265 build..."
	rm -f $(X265_LIB)
	rm -rf $(X265_BUILD_DIR)/build_10bit
	rm -rf $(X265_BUILD_DIR)/build_8bit

clean-dav1d:
	rm -f $(DAV1D_LIB)
	rm -rf $(DAV1D_DIR)/build

clean-libplacebo:
	rm -f $(PLACEBO_LIB)
	rm -rf $(PLACEBO_DIR)/build

clean-ffmpeg:
	rm -f $(FFMPEG_BIN)
	rm -rf $(FFMPEG_DIR)/config.mak

clean:
	@echo "🧹 Cleaning main build artifacts..."
	rm -rf $(BUILD_DIR)
	rm -rf $(XCODE_BUILD_DIR)
	rm -f $(PROJECT_ROOT)/$(APP_NAME).dmg

clean-all: clean clean-xcode-cache
	@echo "🧹 Cleaning source directories..."
	rm -rf $(SRC_DIR)

# ==============================================================================
# 8. Xcode Application
# ==============================================================================

XCODE_PROJ_DIR := $(PROJECT_ROOT)/LiveWallpaperEnabler
XCODE_PROJ := $(XCODE_PROJ_DIR)/LiveWallpaperEnabler.xcodeproj
XCODE_SCHEME := LiveWallpaperEnabler
XCODE_BUILD_DIR := $(PROJECT_ROOT)/build_xcode
APP_NAME := Livid
DMG_BG := $(XCODE_PROJ_DIR)/dmg_background.png
RELEASE_APP_PATH := $(XCODE_BUILD_DIR)/Release/$(APP_NAME).app
DMG_OUT := $(RELEASES_DIR)/$(APP_NAME).dmg
RELEASES_DIR := $(PROJECT_ROOT)/releases
GEN_APPCAST := $(XCODE_PROJ_DIR)/build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast

clean-xcode-cache:
	@echo "🧹 Cleaning Xcode SPM cache..."
	rm -rf $(XCODE_PROJ)/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
	rm -rf $(XCODE_PROJ)/project.xcworkspace/xcshareddata/swiftpm/configuration

resolve-deps: clean-xcode-cache
	@echo "🔍 Checking YouTubeKit..."
	@if [ ! -d "$(PROJECT_ROOT)/Packages/YouTubeKit" ] || [ -z "$$(ls -A $(PROJECT_ROOT)/Packages/YouTubeKit)" ]; then \
		echo "📥 Cloning YouTubeKit..."; \
		rm -rf $(PROJECT_ROOT)/Packages/YouTubeKit; \
		git clone $(REPO_YOUTUBEKIT) $(PROJECT_ROOT)/Packages/YouTubeKit && \
		cd $(PROJECT_ROOT)/Packages/YouTubeKit && git checkout $(COMMIT_YOUTUBEKIT); \
	fi
	@echo "📦 Resolving Swift Package dependencies..."
	xcodebuild -resolvePackageDependencies -project $(XCODE_PROJ)

build-xcode: copy-framework resolve-deps
	@echo "🏗️ Building Xcode project (Debug)..."
	xcodebuild -project $(XCODE_PROJ) -scheme $(XCODE_SCHEME) -configuration Debug \
		-skipPackagePluginValidation -disableAutomaticPackageResolution \
		SYMROOT=$(XCODE_BUILD_DIR) build

build-release: copy-framework resolve-deps
	@echo "🏗️ Building Xcode project (Release)..."
	xcodebuild -project $(XCODE_PROJ) -scheme $(XCODE_SCHEME) -configuration Release \
		-skipPackagePluginValidation -disableAutomaticPackageResolution \
		SYMROOT=$(XCODE_BUILD_DIR) build

release-dmg: build-release
	@echo "📦 Bundling dynamic libraries with dylibbundler..."
	@mkdir -p $(RELEASE_APP_PATH)/Contents/Frameworks
	@dylibbundler -od -b -x "$(RELEASE_APP_PATH)/Contents/MacOS/$(APP_NAME)" -d "$(RELEASE_APP_PATH)/Contents/Frameworks/" -p @executable_path/../Frameworks/
	@echo "📦 Packaging DMG with create-dmg..."
	@rm -f $(PROJECT_ROOT)/$(APP_NAME).dmg
	@rm -rf /tmp/livid-dmg-source
	@mkdir -p /tmp/livid-dmg-source
	@mkdir -p $(RELEASES_DIR)
	@cp -R $(RELEASE_APP_PATH) /tmp/livid-dmg-source/
	@# Use create-dmg for professional styling (Background is 512x512 logical points)
	@create-dmg \
		--volname "$(APP_NAME)" \
		--background "$(DMG_BG)" \
		--window-pos 200 120 \
		--window-size 512 512 \
		--icon-size 96 \
		--icon "$(APP_NAME).app" 128 330 \
		--hide-extension "$(APP_NAME).app" \
		--app-drop-link 384 330 \
		--format UDZO \
		"$(PROJECT_ROOT)/$(APP_NAME).dmg" \
		"/tmp/livid-dmg-source/"
	@# Extract version for archive
	@VERSION=$$(defaults read $(RELEASE_APP_PATH)/Contents/Info.plist CFBundleShortVersionString); \
	ARCH=$$(uname -m); \
	FINAL_DMG=$(RELEASES_DIR)/livid-macos-$${ARCH}-$${VERSION}.dmg; \
	cp $(PROJECT_ROOT)/$(APP_NAME).dmg $$FINAL_DMG; \
	echo "✅ Done! Final DMGs generated:"; \
	echo "   - Archive: $$FINAL_DMG"; \
	echo "   - Latest:  $(PROJECT_ROOT)/$(APP_NAME).dmg"
	@rm -rf /tmp/livid-dmg-source

appcast:
	@echo "📡 Generating Sparkle appcast..."
	@mkdir -p $(RELEASES_DIR)
	@VERSION=$$(defaults read $(RELEASE_APP_PATH)/Contents/Info.plist CFBundleShortVersionString); \
	$(GEN_APPCAST) --download-url-prefix https://github.com/aground5/livid-community/releases/download/v$${VERSION}/ $(RELEASES_DIR)
	@echo "✅ Appcast updated in $(RELEASES_DIR)/appcast.xml"

release-all: release-dmg appcast
	@echo "🚀 Full release build & appcast generation completed!"

run: build-xcode
	@echo "🚀 Launching Livid..."
	open $(XCODE_BUILD_DIR)/Debug/$(APP_NAME).app
