#!/bin/bash
set -e
set -u

export OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

if [ $# -lt 1 ]
then
	echo "Using default directory ${OUTDIR} for output"
else
	export OUTDIR=$1
	echo "Using passed directory ${OUTDIR} for output"
fi

echo "-------------------------------"
echo "OUTDIR: $OUTDIR"
echo "ARCH: $ARCH"
echo "CROSS_COMPILE: $CROSS_COMPILE"
echo "-------------------------------"

mkdir -p ${OUTDIR}
cd ${OUTDIR}

### 1. Clone and Build Kernel (only if needed)
IMAGE_PATH=${OUTDIR}/Image
if [ ! -f "$IMAGE_PATH" ]; then
    if [ ! -d "${OUTDIR}/linux-stable" ]; then
        echo "📥 Cloning kernel ${KERNEL_VERSION}..."
        git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION} linux-stable
    fi
    cd linux-stable

    echo "🛠 Building kernel..."
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} mrproper
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig

    ./scripts/config --enable CONFIG_DEVTMPFS
    ./scripts/config --enable CONFIG_DEVTMPFS_MOUNT
    ./scripts/config --enable CONFIG_VT
    ./scripts/config --enable CONFIG_TTY

    make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} all
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} modules
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} dtbs

    if [ -f "arch/${ARCH}/boot/Image" ]; then
        cp "arch/${ARCH}/boot/Image" "${IMAGE_PATH}"
        echo "✅ Copied kernel image to ${IMAGE_PATH}"
    else
        echo "❌ Error: Kernel image not found."
        exit 1
    fi
else
    echo "✅ Kernel image already exists at ${IMAGE_PATH}, skipping kernel build."
fi

### 2. Prepare rootfs
echo "📦 Setting up root filesystem..."
cd ${OUTDIR}

# Fix permissions for existing rootfs - IMPROVED VERSION
if [ -d "rootfs" ]; then
    echo "🔍 Existing rootfs found, fixing permissions..."
    # Change ownership of entire rootfs back to current user
    sudo chown -R $(whoami):$(whoami) rootfs/ 2>/dev/null || true
    # Make sure we can write to all files
    sudo chmod -R u+w rootfs/ 2>/dev/null || true
    echo "✅ Permissions fixed"
fi

# Clean up rootfs completely to avoid conflicts
rm -rf rootfs
mkdir -p rootfs/{bin,dev,etc,home,lib,lib64,proc,sbin,sys,tmp,usr/{bin,sbin,lib},var/log}

### 3. Build BusyBox
cd ${OUTDIR}
BUSYBOX_VERSION_DOTTED=${BUSYBOX_VERSION//_/.}
BUSYBOX_ARCHIVE=busybox-${BUSYBOX_VERSION_DOTTED}.tar.bz2
BUSYBOX_DIR=busybox-${BUSYBOX_VERSION_DOTTED}

if [ ! -f "$BUSYBOX_ARCHIVE" ]; then
    echo "📥 Downloading BusyBox $BUSYBOX_VERSION_DOTTED..."
    wget https://busybox.net/downloads/$BUSYBOX_ARCHIVE || { echo "❌ Failed to download BusyBox."; exit 1; }
fi

if [ ! -d "busybox" ]; then
    echo "📦 Extracting BusyBox..."
    tar xf "$BUSYBOX_ARCHIVE"
    mv "$BUSYBOX_DIR" busybox
fi

cd busybox
make distclean
make defconfig

echo "⚙️ Configuring BusyBox..."

# Method 1: Use sed to disable CONFIG_TC directly in .config
echo "🔧 Disabling TC (Traffic Control) in BusyBox..."
sed -i 's/CONFIG_TC=y/# CONFIG_TC is not set/' .config
sed -i 's/CONFIG_FEATURE_TC_INGRESS=y/# CONFIG_FEATURE_TC_INGRESS is not set/' .config || true
sed -i 's/CONFIG_FEATURE_TC_CLASSIFY=y/# CONFIG_FEATURE_TC_CLASSIFY is not set/' .config || true

# Force static build (recommended for embedded systems)
echo "🔧 Enabling static linking..."
sed -i 's/.*CONFIG_STATIC.*/CONFIG_STATIC=y/' .config

# Verify the configuration
echo "🔍 Verifying TC is disabled..."
if grep -q "CONFIG_TC=y" .config; then
    echo "⚠️  Warning: TC is still enabled, trying alternative method..."
    if [ -f scripts/config ]; then
        ./scripts/config --disable CONFIG_TC
    else
        echo "# CONFIG_TC is not set" >> .config
        echo "# CONFIG_FEATURE_TC_INGRESS is not set" >> .config 
        echo "# CONFIG_FEATURE_TC_CLASSIFY is not set" >> .config
    fi
else
    echo "✅ TC successfully disabled"
fi

# Build BusyBox
echo "🔨 Building BusyBox..."
make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}

echo "📦 Installing BusyBox to rootfs..."
# Make sure rootfs has correct permissions before installing
chmod -R u+w ${OUTDIR}/rootfs/ 2>/dev/null || true
make CONFIG_PREFIX=${OUTDIR}/rootfs install

### 4. Check if statically linked
BUSYBOX_BIN=${OUTDIR}/rootfs/bin/busybox
if aarch64-linux-gnu-readelf -a $BUSYBOX_BIN | grep -q "Shared library"; then
    echo "⚠️ BusyBox uses shared libraries."
else
    echo "✅ BusyBox is statically linked."
fi

### 5. Create dev nodes
echo "🔧 Creating /dev/null and /dev/console"
sudo mknod -m 666 ${OUTDIR}/rootfs/dev/null c 1 3 2>/dev/null || true
sudo mknod -m 600 ${OUTDIR}/rootfs/dev/console c 5 1 2>/dev/null || true

### 6. Build writer app
echo "📝 Building user-space apps"
cd ${FINDER_APP_DIR}

# Debug information
echo "🔍 DEBUG: Current directory: $(pwd)"
echo "🔍 DEBUG: FINDER_APP_DIR: ${FINDER_APP_DIR}"
echo "🔍 DEBUG: Files in directory:"
ls -la

# Check if Makefile exists and has clean target
if [ -f "Makefile" ]; then
    echo "🧹 Cleaning previous build..."
    make clean 2>/dev/null || echo "⚠️  No clean target, skipping..."
else
    echo "⚠️  No Makefile found in ${FINDER_APP_DIR}"
fi

# Check if we can build
if [ -f "Makefile" ]; then
    echo "🔨 Building with cross-compiler..."
    make CROSS_COMPILE=${CROSS_COMPILE}
    echo "🔍 DEBUG: After make, files:"
    ls -la writer* 2>/dev/null || echo "No writer files found"
elif [ -f "writer.c" ]; then
    echo "🔨 Building writer.c directly..."
    ${CROSS_COMPILE}gcc -o writer writer.c
    echo "🔍 DEBUG: After gcc, files:"
    ls -la writer* 2>/dev/null || echo "No writer files found"
else
    echo "❌ No Makefile or writer.c found, skipping build"
    echo "🔍 DEBUG: Available C files:"
    ls -la *.c 2>/dev/null || echo "No C files found"
fi

# Copy files if they exist
echo "📋 Copying application files..."
mkdir -p ${OUTDIR}/rootfs/home/conf

# Copy files conditionally
[ -f "writer" ] && cp writer ${OUTDIR}/rootfs/home/ || echo "⚠️  writer binary not found"
[ -f "finder.sh" ] && cp finder.sh ${OUTDIR}/rootfs/home/ || echo "⚠️  finder.sh not found"
[ -f "finder-test.sh" ] && cp finder-test.sh ${OUTDIR}/rootfs/home/ || echo "⚠️  finder-test.sh not found"
[ -f "autorun-qemu.sh" ] && cp autorun-qemu.sh ${OUTDIR}/rootfs/home/ || echo "⚠️  autorun-qemu.sh not found"

# Copy config files if they exist
if [ -d "conf" ]; then
    [ -f "conf/username.txt" ] && cp conf/username.txt ${OUTDIR}/rootfs/home/conf/ || echo "⚠️  username.txt not found"
    [ -f "conf/assignment.txt" ] && cp conf/assignment.txt ${OUTDIR}/rootfs/home/conf/ || echo "⚠️  assignment.txt not found"
fi

# Fix finder-test.sh path if it exists
if [ -f "${OUTDIR}/rootfs/home/finder-test.sh" ]; then
    sed -i 's|../conf/assignment.txt|conf/assignment.txt|' ${OUTDIR}/rootfs/home/finder-test.sh
fi

#cd ~/Desktop/Dev/Cousera/Assignment3_part1/finder-app/
CURDIR=$(pwd)
echo "🔍 DEBUG: Current directory after copying files: ${CURDIR}"
cd ${CURDIR}

# Copy file vào rootfs
cp writer.sh ${OUTDIR}/rootfs/home/
chmod +x ${OUTDIR}/rootfs/home/writer.sh
chmod +x ${OUTDIR}/rootfs/home/finder.sh

# Only change ownership at the very end
sudo chown -R root:root ${OUTDIR}/rootfs/*

### 7. Create initramfs
echo "📦 Creating initramfs..."
cd ${OUTDIR}/rootfs
find . | cpio -H newc -ov --owner root:root > ${OUTDIR}/initramfs.cpio
gzip -f ${OUTDIR}/initramfs.cpio

echo "✅ Build completed successfully!"
echo "👉 Kernel image: ${OUTDIR}/Image"
echo "👉 Initramfs: ${OUTDIR}/initramfs.cpio.gz"