#!/bin/bash

set -euo pipefail

# ===== 安装依赖环境 =====
sudo apt-get update
sudo apt-get install -y \
    curl bison flex make binutils dwarves git lld pahole zip perl gcc python3 python-is-python3 \
    bc libssl-dev libelf-dev device-tree-compiler kmod

wget -q https://github.com/llvm/llvm-project/releases/download/llvmorg-20.1.8/LLVM-20.1.8-Linux-X64.tar.xz
tar -Jxf LLVM-20.1.8-Linux-X64.tar.xz
mv LLVM-20.1.8-Linux-X64 llvm21
#===== 自定义环境变量 =====
source local/build.env
export PATH=${PWD}/llvm21/bin:${PATH}
export OUT_DIR=${PWD}/out
export KERNEL_DIR=${PWD}/common
export DEFCONFIG_FILE=${KERNEL_DIR}/arch/arm64/configs/gki_defconfig

#===== 下载内核以及补丁 =====
git clone https://android.googlesource.com/kernel/common -b ${GKI_DEV} --depth=1
git clone https://github.com/KernelSU-Next/kernel_patches.git --depth=1
git clone https://gitlab.com/simonpunk/susfs4ksu.git -b ${GKI_VERSION} --depth=1
git clone https://github.com/SukiSU-Ultra/SukiSU_patch.git --depth=1
git clone https://github.com/xiaoxian8/ssg_patch.git --depth=1
git clone https://github.com/xiaoxian8/AnyKernel3.git --depth=1
echo "正在打入susfs补丁"
cp susfs4ksu/kernel_patches/* ${KERNEL_DIR} -r
patch -p1 -d ${KERNEL_DIR} < susfs4ksu/kernel_patches/50_add_susfs_in_${GKI_VERSION}.patch

# ===== 删除版本后缀 =====
echo ">>> 删除内核版本后缀..."
rm -rf ${KERNEL_DIR}/android/abi_gki_protected_exports_*

# 判断 CONFIG_ZRAM=m 是否存在
if grep -q "^CONFIG_ZRAM=m" "${DEFCONFIG_FILE}"; then
    sed -i 's/CONFIG_ZRAM=m/CONFIG_ZRAM=y/g' "${DEFCONFIG_FILE}"
    echo "已将 CONFIG_ZRAM=m 修改为 CONFIG_ZRAM=y"
else
    echo "CONFIG_ZRAM=m 不存在，不执行修改"
fi

# 判断是否有 -dirty
if grep -q " -dirty" "${KERNEL_DIR}/scripts/setlocalversion"; then
    sed -i 's/ -dirty//g' "${KERNEL_DIR}/scripts/setlocalversion"
    echo "已删除 -dirty"
else
    echo "-dirty 不存在，不执行修改"
fi

# 判断是否自动配置文件名
if grep -q "^CONFIG_LOCALVERSION_AUTO=" "${DEFCONFIG_FILE}"; then
    echo "修改取消自动配置后缀"
    sed -i 's/^CONFIG_LOCALVERSION_AUTO=.*/CONFIG_LOCALVERSION_AUTO=n/' "${DEFCONFIG_FILE}"
else
    echo "添加取消自动配置后缀"
    echo "CONFIG_LOCALVERSION_AUTO=n" >> "${DEFCONFIG_FILE}"
fi

# ===== 拉取 KSU =====
if [[ "$KSU_BRANCH" == "y" || "$KSU_BRANCH" == "y" ]]; then
    echo ">>> 拉取 SukiSU-Ultra"
    curl -LSs "https://raw.githubusercontent.com/ShirkNeko/SukiSU-Ultra/main/kernel/setup.sh" | bash -s susfs-main
else
    echo ">>> 拉取 KernelSU-Next"
    curl -LSs "https://raw.githubusercontent.com/pershoot/KernelSU-Next/refs/heads/next-susfs/kernel/setup.sh" | bash -s next-susfs
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
CONFIG_ZRAM_DEF_COMP_LZ4=y
CONFIG_LOCALVERSION="-xiaoxian"
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

# ===== 启用kpm =====
if [[ "$APPLY_KPM" == "y" || "$APPLY_KPM" == "Y" ]]; then
    echo "CONFIG_KPM=y" >> "$DEFCONFIG_FILE"
else
    echo "没有开启kpm"
fi
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
    echo ">>> 正在打入ssg io补丁"
    patch -p1 -d ${KERNEL_DIR}< ssg_patch/ssg.patch
    cp ssg_patch/* ${KERNEL_DIR} -r
    echo "CONFIG_MQ_IOSCHED_SSG=y" >> "$DEFCONFIG_FILE"
    echo "CONFIG_MQ_IOSCHED_SSG_CGROUP=y" >> "$DEFCONFIG_FILE"
else
echo ">>>没有启用ssg io调度"
fi

#应用hook补丁
if [[ "$KSU_BRANCH" == "y" || "$KSU_BRANCH" == "Y" ]]; then
    echo ">>> 正在打入sukisu hook补丁"
    patch -p1 -d ${KERNEL_DIR} < SukiSU_patch/hooks/sukisu_tracepoint_hooks_v1.1.patch
    #patch -p1 -d ${KERNEL_DIR} < SukiSU_patch/69_hide_stuff.patch
else
    echo ">>> 正在打入ksun hook补丁"
    patch -p1 -F3 -d ${KERNEL_DIR} < kernel_patches/syscall_hook/min_scope_syscall_hooks_v1.5.patch
    echo ">>> 正在打入ksun susfs补丁"
    #patch -p1 -F3 -d ${PWD}/KernelSU-Next < kernel_patches/susfs/android14-6.1-v1.5.9-ksunext-12823.patch
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

# ===== 编译参数 =====
args=(-j$(nproc --all)
    O=${OUT_DIR}
    -C ${KERNEL_DIR}
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
make ${args[@]} Image.lz4 modules
make ${args[@]} INSTALL_MOD_PATH=modules modules_install

if [[ "$APPLY_KPM" == "y" || "$APPLY_KPM" == "Y" ]]; then
    mv ${OUT_DIR}/arch/arm64/boot/Image ./Image
    chmod +x SukiSU_patch/kpm/patch_linux
    ./SukiSU_patch/kpm/patch_linux
    mv -v oImage AnyKernel3/Image
    cd AnyKernel3
    zip -r9v ${OUT_DIR}/kernel.zip *
else
    mv ${OUT_DIR}/arch/arm64/boot/Image ./Image
    mv -v Image AnyKernel3/Image
    cd AnyKernel3
    zip -r9v ${OUT_DIR}/kernel.zip *
fi
