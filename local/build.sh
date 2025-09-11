#!/bin/bash

#安装依赖环境
# 安装依赖环境
sudo apt-get update
sudo apt-get install -y \
    curl bison flex make binutils dwarves git lld pahole zip perl gcc python3 python-is-python3 \
    bc libssl-dev libelf-dev device-tree-compiler kmod

wget -q https://github.com/llvm/llvm-project/releases/download/llvmorg-21.1.1/LLVM-21.1.1-Linux-X64.tar.xz
tar -Jxf LLVM-21.1.1-Linux-X64.tar.xz
mv LLVM-21.1.1-Linux-X64 llvm21
#自定义环境变量
source local/build.env
export PATH=${PWD}/llvm21/bin:${PATH}
export OUT_DIR=${PWD}/out
export KERNEL_DIR=${PWD}/common
export DEFCONFIG_FILE=${KERNEL_DIR}/arch/arm64/configs/gki_defconfig
cp ../susfs4ksu/kernel_patches/* ./ -r
patch -p1 ${KERNEL_DIR} < $(find -name ${PWD}/susfs4ksu/kernel_patches/50_add_susfs*.patch)

# ===== 自动生成 GKI_VERSION =====
# 自动生成 GKI_VERSION
if [[ "$GKI_DEV" == *-* ]]; then
    # 有后缀（比如 -2024-10），去掉最后一段
    export GKI_VERSION="gki-${GKI_DEV%-*}"
else
    # 没有后缀，直接加 gki-
    export GKI_VERSION="gki-${GKI_DEV}"
fi
echo "GKI_DEV=$GKI_DEV"
echo "GKI_VERSION=$GKI_VERSION"

#下载内核以及补丁
git clone https://android.googlesource.com/kernel/common -b ${GKI_DEV} --depth=1
git clone https://github.com/KernelSU-Next/kernel_patches.git --depth=1
git clone https://gitlab.com/simonpunk/susfs4ksu.git -b ${GKI_VERSION} --depth=1
git clone https://github.com/SukiSU-Ultra/SukiSU_patch.git --depth=1
git clone https://github.com/xiaoxian8/ssg_patch.git --depth=1

# ===== KernelSU分支选择 =====
if [[ "$KSU_BRANCH" == "y" || "$KSU_BRANCH" == "Y" ]]; then
    KSU_TYPE="SukiSU Ultra"
else
    KSU_TYPE="KernelSU Next"
fi

# ===== 删除版本后缀 =====
echo ">>> 删除内核版本后缀..."
rm -rf ${DEFCONFIG_FILE}/android/abi_gki_protected_exports_*
sed -i 's/CONFIG_ZRAM=m/CONFIG_ZRAM=y/g'
sed -i 's/ -dirty//g' scripts/setlocalversion

# ===== 拉取 KSU 并设置版本号 =====
if [[ "$KSU_BRANCH" == "y" ]]; then
    echo ">>> 拉取 SukiSU-Ultra 并设置版本..."
    curl -LSs "https://raw.githubusercontent.com/ShirkNeko/SukiSU-Ultra/main/kernel/setup.sh" | bash -s susfs-main
    cd KernelSU
    KSU_VERSION=$(expr $(/usr/bin/git rev-list --count main) "+" 10606)
    export KSU_VERSION=$KSU_VERSION
    sed -i "s/DKSU_VERSION=12800/DKSU_VERSION=${KSU_VERSION}/" kernel/Makefile
else
    echo ">>> 拉取 KernelSU Next 并设置版本..."
    curl -LSs "https://raw.githubusercontent.com/pershoot/KernelSU-Next/next-susfs/kernel/setup.sh" | bash -s next
    cd KernelSU-Next
    KSU_VERSION=$(expr $(curl -sI "https://api.github.com/repos/pershoot/KernelSU-Next/commits?sha=next&per_page=1" | grep -i "link:" | sed -n 's/.*page=\([0-9]*\)>; rel="last".*/\1/p') "+" 10200)
    sed -i "s/DKSU_VERSION=11998/DKSU_VERSION=${KSU_VERSION}/" kernel/Makefile
fi

# ===== KernelSU默认配置 =====
cat >> "$DEFCONFIG_FILE" <<EOF
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
#CONFIG_KSU_SUSFS_SUS_OVERLAYFS is not set
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
EOF
echo "CONFIG_KSU_MANUAL_HOOK=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_KSU_SUSFS_SUS_SU=n" >>  "$DEFCONFIG_FILE"

# ===== 添加LTO优化 =====
echo ">>> 添加LTO优化..."
cat >> "$DEFCONFIG_FILE" <<EOF
CONFIG_LTO_CLANG=y
CONFIG_ARCH_SUPPORTS_LTO_CLANG=y
CONFIG_ARCH_SUPPORTS_LTO_CLANG_THIN=y
CONFIG_HAS_LTO_CLANG=y
CONFIG_LTO_CLANG_THIN=y
CONFIG_LTO=y
EOF

# ===== 添加网络优化 =====
echo ">>> 正在启用网络功能增强优化配置..."
echo "CONFIG_BPF_STREAM_PARSER=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_NETFILTER_XT_SET=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_IP_SET=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_IP_SET_MAX=65534" >> "$DEFCONFIG_FILE"
echo "CONFIG_IP_SET_BITMAP_IP=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_IP_SET_BITMAP_IPMAC=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_IP_SET_BITMAP_PORT=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_IP_SET_HASH_IP=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_IP_SET_HASH_IPMARK=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_IP_SET_HASH_IPPORT=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_IP_SET_HASH_IPPORTIP=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_IP_SET_HASH_IPPORTNET=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_IP_SET_HASH_IPMAC=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_IP_SET_HASH_MAC=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_IP_SET_HASH_NETPORTNET=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_IP_SET_HASH_NET=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_IP_SET_HASH_NETNET=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_IP_SET_HASH_NETPORT=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_IP_SET_HASH_NETIFACE=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_IP_SET_LIST_SET=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_IP6_NF_NAT=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_IP6_NF_TARGET_MASQUERADE=y" >> "$DEFCONFIG_FILE"

# ===== 是否启用ssg io调度 =====
if [[ "$APPLY_SSG" == "y" || "$APPLY_SSG" == "Y" ]]; then
    patch -p1 < ssg_patch/ssg.patch
    cp ssg_patch/* ./
    echo "CONFIG_MQ_IOSCHED_SSG=y" >> "$DEFCONFIG_FILE"
    echo "CONFIG_MQ_IOSCHED_SSG_CGROUP=y" >> "$DEFCONFIG_FILE"
else
echo ">>>没有启用ssg io调度"
fi

if [[ "$APPLY_LZ4KD" == "y" || "$APPLY_LZ4KD" == "Y" ]]; then
patch -p1 -F3 ${KERNEL_DIR} < SukiSU_patch/other/zram/zram_patch/6.1/lz4kd.patch
patch -p1 -F3 ${KERNEL_DIR} < SukiSU_patch/other/zram/zram_patch/6.1/lz4k_oplus.patch
cp SukiSU_patch/other/zram/lz4k/* ${KERNEL_DIR} -r
cp SukiSU_patch/other/zram/lz4k_oplus ${KERNEL_DIR}/lib -r
else
    echo ">>> 没有启用lz4kd"
fi

#应用hook补丁
if [[ "$KSU_BRANCH" == "y" ]]; then
    patch -p1 ${KERNEL_DIR} < SukiSU_patch/hooks/syscall_hooks.patch
    patch -p1 ${KERNEL_DIR} < SukiSU_patch/69_hide_stuff.patch
else
    patch -p1 -F3 ${PWD}/KernelSU-Next/ < kernel_patches/susfs/android14-6.1-v1.5.9-ksunext-12823.patch
    patch -p1 -F3 ${KERNEL_DIR} < kernel_patches/syscall_hook/min_scope_syscall_hooks_v1.4.patch
fi

# ===== 添加 BBR 等一系列拥塞控制算法 =====
if [[ "$APPLY_BBR" == "y" || "$APPLY_BBR" == "Y" || "$APPLY_BBR" == "d" || "$APPLY_BBR" == "D" ]]; then
    echo ">>> 正在添加 BBR 等一系列拥塞控制算法..."
    echo "CONFIG_TCP_CONG_ADVANCED=y" >> "${DEFCONFIG_FILE}"
    echo "CONFIG_TCP_CONG_BBR=y" >> "${DEFCONFIG_FILE}"
    echo "CONFIG_TCP_CONG_CUBIC=y" >> "${DEFCONFIG_FILE}"
    echo "CONFIG_TCP_CONG_VEGAS=y" >> "${DEFCONFIG_FILE}"
    echo "CONFIG_TCP_CONG_NV=y" >> "${DEFCONFIG_FILE}"
    echo "CONFIG_TCP_CONG_WESTWOOD=y" >> "${DEFCONFIG_FILE}"
    echo "CONFIG_TCP_CONG_HTCP=y" >> "${DEFCONFIG_FILE}"
    echo "CONFIG_TCP_CONG_BRUTAL=y" >> "${DEFCONFIG_FILE}"
    if [[ "$APPLY_BBR" == "d" || "$APPLY_BBR" == "D" ]]; then
        echo "CONFIG_DEFAULT_TCP_CONG=bbr" >> "$DEFCONFIG_FILE"
    else
        echo "CONFIG_DEFAULT_TCP_CONG=cubic" >> "$DEFCONFIG_FILE"
  fi
fi


# ===== 启用Re-Kernel =====
if [[ "$APPLY_REKERNEL" == "y" || "$APPLY_REKERNEL" == "Y" ]]; then
  echo ">>> 正在启用Re-Kernel..."
  echo "CONFIG_REKERNEL=y" >> "$DEFCONFIG_FILE"
fi

# ===== 启用kpm =====
if [[ "$USE_PATCH_LINUX" == "y" || "$USE_PATCH_LINUX" == "Y" ]]; then
  echo "CONFIG_KPM=y" >> "$DEFCONFIG_FILE"
fi
# ===== 编译参数 =====
args=(-j$(nproc --all)
    O=${OUT_DIR}
    -M ${KERNEL_DIR}
    ARCH=arm64
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
    LLVM=1
    LLVM_IAS=1
    DEPMOD=depmod
    DTC=dtc )

# ===== 开始编译 =====
make ${args[@]} mrproper
make ${args[@]} gki_defconfig
make ${args[@]} Image.lz4

if [[ "$USE_PATCH_LINUX" == "y" || "$USE_PATCH_LINUX" == "Y" ]]; then
    mv ${OUT_DIR}/arch/arm64/boot/Image ./Image
    chmod +x SukiSU_patch/kpm/patch_linux
    ./SukiSU_patch/kpm/patch_linux
    mv -v oImage AnyKernel3/Image
    cd AnyKernel3
    zip -r9v ../out/kernel.zip *
else
    mv ${OUT_DIR}/arch/arm64/boot/Image ./Image
    mv -v Image AnyKernel3/Image
    cd AnyKernel3
    zip -r9v ../out/kernel.zip *
fi
