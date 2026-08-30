#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 Infiniti151

set -euo pipefail

# --- Color codes ---
CYAN='\033[36m'
YELLOW='\033[33m'
GREEN='\033[32m'
RED='\033[31m'
NC='\033[0m'

# --- Configuration ---
WORK_DIR="${GITHUB_WORKSPACE:-/workspace}"
INSTALL_DIR="$WORK_DIR/output"
CACHE_DIR="$WORK_DIR/cache"
NDK_VERSION="r29"
NDK_SRC="$CACHE_DIR/android-ndk-$NDK_VERSION"
NDK="/opt/android-ndk-$NDK_VERSION"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
API="${API:-28}"
GENERATE_APT_REPO="${GENERATE_APT_REPO:-true}"

echo -e "${CYAN}=== [1/5] Staging NDK $NDK_VERSION to native container storage (/opt) ===${NC}"
mkdir -p "$WORK_DIR" "$INSTALL_DIR/lib" "$INSTALL_DIR/bin" "$CACHE_DIR"

# --- Download NDK if not cached ---
if [ ! -d "$NDK_SRC" ]; then
    echo -e "${YELLOW}Downloading Android NDK ($NDK_VERSION)...${NC}"
    wget -q --show-progress \
      "https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip" \
      -O "$CACHE_DIR/ndk.zip"
    unzip -q "$CACHE_DIR/ndk.zip" -d "$CACHE_DIR"
    rm -f "$CACHE_DIR/ndk.zip"
fi

# --- Copy NDK into /opt ---
if [ ! -d "$NDK" ]; then
    echo -e "${YELLOW}Copying NDK from cache volume to /opt...${NC}"
    cp -a "$NDK_SRC" /opt/
fi

echo -e "${YELLOW}Granting execution permissions to toolchain binaries...${NC}"
chmod -R +x "$TOOLCHAIN/bin/"

# Validate that clang can actually execute on this filesystem
if ! "$TOOLCHAIN/bin/clang" --version > /dev/null 2>&1; then
    echo -e "${RED}Error: Clang binary is not executable.${NC}"
    file "$TOOLCHAIN/bin/clang" || true
    exit 1
fi

echo -e "${YELLOW}NDK environment validated successfully in /opt.${NC}\n"

# Export cross-compilation environment for Android ARM64
export CC="$TOOLCHAIN/bin/aarch64-linux-android${API}-clang"
export CXX="$TOOLCHAIN/bin/aarch64-linux-android${API}-clang++"
export AR="$TOOLCHAIN/bin/llvm-ar"
export RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
export LD="$TOOLCHAIN/bin/ld.lld"

echo -e "${YELLOW}Adding compiler wrappers...${NC}\n"
# 1. Update compiler wrappers to include the NDK sysroot and strip x86-specific flags
cat > /tmp/android-clang << EOF
#!/bin/bash
filtered_args=()
for arg in "\$@"; do
    case "\$arg" in
        -msse2|-maes) ;; # Strip x86-specific SIMD/crypto flags
        *) filtered_args+=("\$arg") ;;
    esac
done
exec "${TOOLCHAIN}/bin/clang" --target=aarch64-linux-android${API} --sysroot="${TOOLCHAIN}/sysroot" "\${filtered_args[@]}"
EOF

cat > /tmp/android-clang++ << EOF
#!/bin/bash
filtered_args=()
for arg in "\$@"; do
    case "\$arg" in
        -msse2|-maes) ;; # Strip x86-specific SIMD/crypto flags
        *) filtered_args+=("\$arg") ;;
    esac
done
exec "${TOOLCHAIN}/bin/clang++" --target=aarch64-linux-android${API} --sysroot="${TOOLCHAIN}/sysroot" "\${filtered_args[@]}"
EOF

chmod +x /tmp/android-clang /tmp/android-clang++

echo -e "${CYAN}=== [2/5] Cross-Compiling wxWidgets (Static wxBase) for Android ARM64 ===${NC}"
cd "$WORK_DIR"

WX_VERSION="3.2.11"

if [ ! -d "wxWidgets" ]; then
    echo -e "${YELLOW}Downloading wxWidgets v${WX_VERSION}...${NC}"
    wget -q "https://github.com/wxWidgets/wxWidgets/releases/download/v${WX_VERSION}/wxWidgets-${WX_VERSION}.tar.bz2"
    tar -xf "wxWidgets-${WX_VERSION}.tar.bz2"
    mv "wxWidgets-${WX_VERSION}" wxWidgets
    rm -f "wxWidgets-${WX_VERSION}.tar.bz2"
fi

cd "$WORK_DIR/wxWidgets"

# Neutralize legacy Android config AND chkconf files before configure/build
echo "/* Bypassed for autoconf build */" > include/wx/android/config_android.h
echo "/* Bypassed for autoconf build */" > include/wx/android/chkconf.h

# Force English names when intl is disabled
sed -i 's/wxUILocale::GetCurrent().GetMonthName/GetEnglishMonthName/g' src/common/datetime.cpp
sed -i 's/wxUILocale::GetCurrent().GetWeekDayName/GetEnglishWeekDayName/g' src/common/datetime.cpp

# Clean previous build artifacts
make distclean || true
rm -rf config.cache config.status lib/

# Re-configure wxWidgets
./configure \
  --host=aarch64-linux-android \
  --build=x86_64-pc-linux-gnu \
  --disable-gui \
  --disable-intl \
  --disable-shared \
  --disable-tests \
  --enable-unicode \
  --enable-cmdline \
  --with-zlib=builtin \
  --with-regex=builtin \
  CC="/tmp/android-clang" \
  CXX="/tmp/android-clang++" \
  AR="${TOOLCHAIN}/bin/llvm-ar" \
  RANLIB="${TOOLCHAIN}/bin/llvm-ranlib" \
  CFLAGS="-O2 -fPIC -D_GNU_SOURCE -DHAVE_UNISTD_H -Wno-error=implicit-function-declaration" \
  CXXFLAGS="-O2 -fPIC -D_GNU_SOURCE -DHAVE_UNISTD_H -Wno-error=implicit-function-declaration -std=c++14 -DwxUSE_INTL=0" \
  CPPFLAGS="-DHAVE_UNISTD_H"

# Kill utilities
sed -i 's|^UTILS_SUBDIRS *=.*|UTILS_SUBDIRS =|' Makefile
mkdir -p utils/wxrc
echo -e 'all:\n\t@true\nclean:\ninstall:' > utils/Makefile
echo -e 'all:\n\t@true\nclean:\ninstall:' > utils/wxrc/Makefile

# Build wxWidgets
make -j$(nproc)

echo -e "\n${CYAN}=== [3/5] Cross-Compiling VeraCrypt ===${NC}"
cd "$WORK_DIR"

VERACRYPT_VERSION="1.26.29"

if [ ! -d "VeraCrypt" ]; then
    echo -e "${YELLOW}Downloading VeraCrypt v${VERACRYPT_VERSION}...${NC}"
    wget -q "https://github.com/veracrypt/VeraCrypt/archive/refs/tags/VeraCrypt_${VERACRYPT_VERSION}.tar.gz"
    tar -xf "VeraCrypt_${VERACRYPT_VERSION}.tar.gz"
    mv "VeraCrypt-VeraCrypt_${VERACRYPT_VERSION}" VeraCrypt
    rm -f "VeraCrypt_${VERACRYPT_VERSION}.tar.gz"

    cd VeraCrypt

    echo -e "${YELLOW}Applying Termux overrides...${NC}"

    # 1a. Inject the missing unistd.h header at line 1 of SCardLoader.cpp for access() and F_OK
    sed -i '1i #include <unistd.h>' src/Common/SCardLoader.cpp

    # 1b. Override PCSC-lite path in SCardLoader.cpp
    sed -i 's|pcscPath = "libpcsclite.so";|// Termux-specific override\n            pcscPath = "/data/data/com.termux/files/usr/lib/libpcsclite_real.so";\n            if (access(pcscPath.c_str(), F_OK) != 0)\n                pcscPath = "/data/data/com.termux/files/usr/lib/libpcsclite.so";|g' src/Common/SCardLoader.cpp

    # 2. Hardcode Termux dmsetup path in CoreLinux.cpp
    sed -i 's|"dmsetup"|"/data/data/com.termux/files/usr/bin/dmsetup"|g' src/Core/Unix/Linux/CoreLinux.cpp

    cd ..
fi

cd VeraCrypt

mkdir -p "$INSTALL_DIR/lib" "$INSTALL_DIR/include" "$INSTALL_DIR/bin"
echo 'INPUT(-lc)' > "$INSTALL_DIR/lib/libpthread.so"

# Configure Termux Package Paths (FUSE 3 & PCSC-lite)
TERMUX_FUSE3_PREFIX="/opt/termux-fuse3/data/data/com.termux/files/usr"
TERMUX_PCSC_PREFIX="/opt/termux-pcsclite/data/data/com.termux/files/usr"

unset PKG_CONFIG_SYSROOT_DIR
unset PKG_CONFIG_LIBDIR

export PKG_CONFIG_PATH="$TERMUX_FUSE3_PREFIX/lib/pkgconfig:$TERMUX_PCSC_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

if [ -f "$TERMUX_FUSE3_PREFIX/lib/pkgconfig/fuse3.pc" ] && [ ! -f "$TERMUX_FUSE3_PREFIX/lib/pkgconfig/fuse.pc" ]; then
    ln -s "$TERMUX_FUSE3_PREFIX/lib/pkgconfig/fuse3.pc" "$TERMUX_FUSE3_PREFIX/lib/pkgconfig/fuse.pc"
fi

VERACRYPT_SRC_DIR="$WORK_DIR/VeraCrypt/src"

cd "$VERACRYPT_SRC_DIR"

echo -e "\n${YELLOW}=== Compiling VeraCrypt CLI ===${NC}"

make clean || true

# Define complete library search paths
LINK_FLAGS="-L$TERMUX_FUSE3_PREFIX/lib -L$TERMUX_PCSC_PREFIX/lib -L$INSTALL_DIR/lib"

if [ -d "$TERMUX_FUSE3_PREFIX/lib/aarch64-linux-gnu" ]; then
    LINK_FLAGS="$LINK_FLAGS -L$TERMUX_FUSE3_PREFIX/lib/aarch64-linux-gnu"
fi

ARM_FLAGS="-march=armv8-a+crypto"
WX_FLAGS="$("$WORK_DIR/wxWidgets/wx-config" --cxxflags)"

# Intercept hardcoded 'strip' calls by forcing the system to find llvm-strip first
ln -sf "$TOOLCHAIN/bin/llvm-strip" /tmp/strip
export PATH="/tmp:$PATH"

# Prevent the Makefile from attempting to execute the ARM64 binary on the x86_64 host
sed -i 's|./$(APPNAME)|true|g' Main/Main.make

make -j$(nproc) \
    SOURCE_DATE_EPOCH="$(date +%s)" \
    NOGUI=1 \
    WXSTATIC=1 \
    WITHFUSE3=1 \
    ARCH=aarch64 \
    PLATFORM_ARCH=aarch64 \
    WX_ROOT="$WORK_DIR/wxWidgets" \
    WX_CONFIG="$WORK_DIR/wxWidgets/wx-config" \
    CC="/tmp/android-clang" \
    CXX="/tmp/android-clang++" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    LFLAGS="$LINK_FLAGS" \
    LDFLAGS="$LINK_FLAGS" \
    EXTRA_LDFLAGS="$LINK_FLAGS" \
    TC_EXTRA_CFLAGS="$WX_FLAGS $ARM_FLAGS -I$TERMUX_FUSE3_PREFIX/include -I$TERMUX_FUSE3_PREFIX/include/fuse3 -I$TERMUX_PCSC_PREFIX/include -I$TERMUX_PCSC_PREFIX/include/PCSC -I$INSTALL_DIR/include" \
    TC_EXTRA_CXXFLAGS="$WX_FLAGS $ARM_FLAGS -D'_(s)=wxString(s)' -I$TERMUX_FUSE3_PREFIX/include -I$TERMUX_FUSE3_PREFIX/include/fuse3 -I$TERMUX_PCSC_PREFIX/include -I$TERMUX_PCSC_PREFIX/include/PCSC -I$INSTALL_DIR/include" \
    TC_EXTRA_LDFLAGS="$LINK_FLAGS"

# Copy binary
cp -a Main/veracrypt "$INSTALL_DIR/bin/"
chmod 755 "$INSTALL_DIR/bin/veracrypt"

echo -e "\n${YELLOW}=== Verifying FUSE linkage ===${NC}"
readelf -d "$INSTALL_DIR/bin/veracrypt" | grep NEEDED || true

echo -e "\n${GREEN}VeraCrypt binary built: $INSTALL_DIR/bin/veracrypt${NC}"

if [ "$GENERATE_APT_REPO" = "false" ]; then
    echo -e "\n${GREEN}=== Skipping APT repository generation (local build) ===${NC}"
    exit 0
fi

echo -e "\n${CYAN}=== [4/5] Generating APT Repository ===${NC}"

TERMUX_PREFIX="/data/data/com.termux/files/usr"
PKG_STAGE="$WORK_DIR/pkg-staging"

APT_REPO_DIR="$WORK_DIR/output/apt-repo"
REPO_NAME="veracrypt-android"

DIST="stable"
COMPONENT="main"
ARCH="aarch64"

APT_DIST_DIR="$APT_REPO_DIR/dists/$DIST"
APT_BINARY_DIR="$APT_DIST_DIR/$COMPONENT/binary-$ARCH"
APT_POOL_DIR="$APT_REPO_DIR/pool/$COMPONENT/v/veracrypt"

echo -e "\n${YELLOW}Package version: $VERACRYPT_VERSION${NC}"

# ---------------------------------------------------------------------------
# Clean previous package/repository output
# ---------------------------------------------------------------------------

echo -e "\n${YELLOW}=== Preparing package and APT repository directories ===${NC}"

rm -rf "$PKG_STAGE"

mkdir -p \
    "$PKG_STAGE/$TERMUX_PREFIX/bin" \
    "$PKG_STAGE/$TERMUX_PREFIX/lib" \
    "$PKG_STAGE/$TERMUX_PREFIX/share/doc/veracrypt" \
    "$PKG_STAGE/DEBIAN" \
    "$APT_BINARY_DIR" \
    "$APT_POOL_DIR"

# Copy the license into the package
cp "$WORK_DIR/VeraCrypt/License.txt" "$PKG_STAGE/$TERMUX_PREFIX/share/doc/veracrypt/copyright"

# ---------------------------------------------------------------------------
# Copy binaries
# ---------------------------------------------------------------------------

echo -e "\n${YELLOW}=== Copying binaries ===${NC}"

cp -a \
    "$INSTALL_DIR/bin"/veracrypt* \
    "$PKG_STAGE/$TERMUX_PREFIX/bin/"

# ---------------------------------------------------------------------------
# Permissions
# ---------------------------------------------------------------------------

echo -e "\n${YELLOW}=== Setting permissions ===${NC}"

chmod 755 \
    "$PKG_STAGE/$TERMUX_PREFIX/bin/"*

# ---------------------------------------------------------------------------
# Debian control file
# ---------------------------------------------------------------------------

echo -e "\n${YELLOW}=== Creating package control file ===${NC}"

INSTALLED_SIZE="$(du -sk --apparent-size "$PKG_STAGE" | cut -f1)"

cat > "$PKG_STAGE/DEBIAN/control" <<EOF
Package: veracrypt
Version: $VERACRYPT_VERSION
Architecture: $ARCH
Maintainer: Infiniti151
Installed-Size: $INSTALLED_SIZE
Depends: libfuse3, libpcsclite, libdevmapper
Section: utils
Priority: optional
Homepage: https://github.com/veracrypt/VeraCrypt
Description: VeraCrypt disk encryption manager for Termux
 VeraCrypt is a free, open-source disk encryption software based on
 TrueCrypt 7.1a, providing strong on-the-fly encryption.
 .
 This package provides a custom cross-compiled CLI version of VeraCrypt
 adapted for the Android Termux environment. It includes built-in path
 override for device-mapper (dmsetup) and FUSE3 integration designed
 to work within Android sandbox constraints.
EOF

# ---------------------------------------------------------------------------
# Build .deb
# ---------------------------------------------------------------------------

echo -e "\n${YELLOW}=== Building .deb ===${NC}"

DEB_FILE_NAME="veracrypt_${VERACRYPT_VERSION}_${ARCH}.deb"
DEB_FILE="$APT_POOL_DIR/$DEB_FILE_NAME"

dpkg-deb \
    --build \
    "$PKG_STAGE" \
    "$DEB_FILE"

echo "Successfully built:"
echo "$DEB_FILE"

echo "DEB_FILE=$DEB_FILE" >> "$GITHUB_ENV"

# ---------------------------------------------------------------------------
# Generate Packages index
# ---------------------------------------------------------------------------

echo -e "\n${YELLOW}=== Generating Packages index ===${NC}"

(
    cd "$APT_REPO_DIR"

    dpkg-scanpackages \
        --arch "$ARCH" \
        pool \
        /dev/null \
        > "$APT_BINARY_DIR/Packages"
)

gzip -9 -c \
    "$APT_BINARY_DIR/Packages" \
    > "$APT_BINARY_DIR/Packages.gz"

# ---------------------------------------------------------------------------
# Generate Release metadata
# ---------------------------------------------------------------------------

echo -e "\n${YELLOW}=== Generating Release file ===${NC}"

cat > "$WORK_DIR/apt-release.conf" <<EOF
APT::FTPArchive::Release::Origin "$REPO_NAME";
APT::FTPArchive::Release::Label "$REPO_NAME";
APT::FTPArchive::Release::Suite "$DIST";
APT::FTPArchive::Release::Codename "$DIST";
APT::FTPArchive::Release::Architectures "$ARCH";
APT::FTPArchive::Release::Components "$COMPONENT";
APT::FTPArchive::Release::Description "VeraCrypt APT repository for Termux Android ARM64";
EOF

apt-ftparchive \
    -c "$WORK_DIR/apt-release.conf" \
    release \
    "$APT_DIST_DIR" \
    > "$APT_DIST_DIR/Release"

echo -e "\n${YELLOW}=== Release file ===${NC}"
cat "$APT_DIST_DIR/Release"

echo
echo -e "\n${YELLOW}=== APT repository tree ===${NC}"
find "$APT_REPO_DIR" -type f -print | sort

echo
echo -e "\n${YELLOW}=== Packages index ===${NC}"
cat "$APT_BINARY_DIR/Packages"

echo -e "${CYAN}=== [5/5] Signing APT repository ===${NC}"

if [ -z "${GPG_KEY:-}" ]; then
    echo -e "${RED}Error: GPG_KEY is not set.${NC}"
    exit 1
fi

if [ -z "${GPG_PASSPHRASE:-}" ]; then
    echo -e "${RED}Error: GPG_PASSPHRASE is not set.${NC}"
    exit 1
fi

echo -e "\n${YELLOW}=== Available signing keys ===${NC}"
gpg --batch --list-secret-keys

echo -e "\n${YELLOW}=== Signing Release file ===${NC}"

gpg --batch --yes \
    --pinentry-mode loopback \
    --passphrase "$GPG_PASSPHRASE" \
    --local-user "$GPG_KEY" \
    --armor \
    --detach-sign \
    --output "$APT_DIST_DIR/Release.gpg" \
    "$APT_DIST_DIR/Release"

echo -e "\n${YELLOW}=== Creating InRelease ===${NC}"

gpg --batch --yes \
    --pinentry-mode loopback \
    --passphrase "$GPG_PASSPHRASE" \
    --local-user "$GPG_KEY" \
    --clearsign \
    --output "$APT_DIST_DIR/InRelease" \
    "$APT_DIST_DIR/Release"

echo -e "\n${YELLOW}=== Verifying Release.gpg ===${NC}"

gpg --batch --verify \
    "$APT_DIST_DIR/Release.gpg" \
    "$APT_DIST_DIR/Release"

echo -e "\n${YELLOW}=== Verifying InRelease ===${NC}"

gpg --batch --verify \
    "$APT_DIST_DIR/InRelease"

echo -e "${GREEN}
====================================================
Build complete!

Signed APT repository generated at:
$APT_REPO_DIR
====================================================
${NC}"
