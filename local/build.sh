#!/bin/bash
set -euo pipefail
#安装依赖环境
# 安装依赖环境
sudo apt-get update
sudo apt-get install -y \
    curl bison flex make binutils dwarves git lld pahole zip perl gcc python3 python-is-python3 \
    bc libssl-dev libelf-dev device-tree-compiler kmod rustc

wget -q https://github.com/llvm/llvm-project/releases/download/llvmorg-20.1.8/LLVM-20.1.8-Linux-X64.tar.xz
tar -Jxf LLVM-20.1.8-Linux-X64.tar.xz
mv LLVM-20.1.8-Linux-X64 llvm20

#下载谷歌构建工具
git clone https://android.googlesource.com/kernel/prebuilts/build-tools -b main-kernel-2025 --depth=1
git clone https://android.googlesource.com/platform/system/tools/mkbootimg -b main-kernel-2025 --depth=1

#下载内核以及补丁
git clone https://android.googlesource.com/kernel/common -b android14-6.1-2024-10 --depth=1
git clone https://github.com/xiaoxian8/ssg_patch.git --depth=1
git clone https://github.com/xiaoxian8/AnyKernel3.git --depth=1
git clone https://gitlab.com/simonpunk/susfs4ksu.git -b gki-android14-6.1 --depth=1
wget https://raw.githubusercontent.com/WildKernels/kernel_patches/refs/heads/main/common/unicode_bypass_fix_6.1%2B.patch

#自定义环境变量
export PATH=${PWD}/llvm20/bin:${PATH}
export AVBTOOL=${PWD}/build-tools/linux-x86/bin/avbtool
export MKBOOTIMG=${PWD}/mkbootimg/mkbootimg.py
export BOOT_SIGN_KEY_PATH=${PWD}/build-tools/linux-x86/share/avb/testkey_rsa2048.pem
export KERNEL_DIR=${PWD}/common
export OUT_DIR=${PWD}/out
export DEFCONFIG_FILE=${PWD}/common/arch/arm64/configs/gki_defconfig

#删除abi符号以及-dirty后缀
rm -rf ${KERNEL_DIR}/android/abi_gki_protected_exports_*
if grep -q " -dirty" "$KERNEL_DIR/scripts/setlocalversion"; then
	sed -i 's/ -dirty//g' "$KERNEL_DIR/scripts/setlocalversion"
	echo "已删除 -dirty"
else
	echo "-dirty 不存在，不执行修改"
fi
sed -i '$c\echo "-xiaoxian"' "$KERNEL_DIR/scripts/setlocalversion"


echo "正在打入susfs补丁"
cp susfs4ksu/kernel_patches/* ${KERNEL_DIR} -r
patch -p1 -F3 -d ${KERNEL_DIR} < susfs4ksu/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch

#curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s dev
#patch -p1 -d ${PWD}/KernelSU-Next < next-susfs.patch

curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s main
patch p1 -d -F3 ${PWD}/KernelSU < susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch


#curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s main
#patch -p1 -d ${PWD}/KernelSU < susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch

cp ssg_patch/block ${KERNEL_DIR} -r
patch -p1 -d ${KERNEL_DIR} < ssg_patch/ssg.patch

patch -p1 -d ${KERNEL_DIR} < unicode_bypass_fix_6.1+.patch

#添加KernelSU默认配置
cat >> "${DEFCONFIG_FILE}" <<EOF
# KernelSU
CONFIG_KSU=y
CONFIG_KSU_DEBUG=n

# KernelSU - SUSFS
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
EOF

#添加内核编译优化
cat >> "${DEFCONFIG_FILE}" <<EOF
CONFIG_PM_DEBUG=n
CONFIG_PM_ADVANCED_DEBUG=n
CONFIG_PM_SLEEP_DEBUG=n
EOF

#添加LTO优化
cat >> "${DEFCONFIG_FILE}" <<EOF
CONFIG_LTO_CLANG=y
CONFIG_ARCH_SUPPORTS_LTO_CLANG=y
CONFIG_ARCH_SUPPORTS_LTO_CLANG_THIN=y
CONFIG_HAS_LTO_CLANG=y
CONFIG_LTO_CLANG_THIN=y
CONFIG_LTO=y
EOF

#添加ssg io调度
cat >> "${DEFCONFIG_FILE}" <<EOF
CONFIG_MQ_IOSCHED_SSG=y
CONFIG_MQ_IOSCHED_SSG_CGROUP=y
EOF

#Mountify支持
cat >> "${DEFCONFIG_FILE}" <<EOF
CONFIG_TMPFS_XATTR=y
CONFIG_TMPFS_POSIX_ACL=y
EOF

#添加网络优化
cat >> "${DEFCONFIG_FILE}" <<EOF
# BBR Support
CONFIG_TCP_CONG_ADVANCED=y
CONFIG_TCP_CONG_BBR=y
CONFIG_TCP_CONG_CUBIC=y
CONFIG_TCP_CONG_VEGAS=y
CONFIG_TCP_CONG_NV=y
CONFIG_TCP_CONG_WESTWOOD=y
CONFIG_TCP_CONG_HTCP=y
CONFIG_TCP_CONG_BRUTAL=y
CONFIG_DEFAULT_TCP_CONG=bbr

#NetWork Support
CONFIG_BPF_STREAM_PARSER=y
CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y
CONFIG_NETFILTER_XT_SET=y
CONFIG_IP_SET=y
CONFIG_IP_SET_MAX=65534
CONFIG_IP_SET_BITMAP_IP=y
CONFIG_IP_SET_BITMAP_IPMAC=y
CONFIG_IP_SET_BITMAP_PORT=y
CONFIG_IP_SET_HASH_IP=y
CONFIG_IP_SET_HASH_IPMARK=y
CONFIG_IP_SET_HASH_IPPORT=y
CONFIG_IP_SET_HASH_IPPORTIP=y
CONFIG_IP_SET_HASH_IPPORTNET=y
CONFIG_IP_SET_HASH_IPMAC=y
CONFIG_IP_SET_HASH_MAC=y
CONFIG_IP_SET_HASH_NETPORTNET=y
CONFIG_IP_SET_HASH_NET=y
CONFIG_IP_SET_HASH_NETNET=y
CONFIG_IP_SET_HASH_NETPORT=y
CONFIG_IP_SET_HASH_NETIFACE=y
CONFIG_IP_SET_LIST_SET=y
CONFIG_IP6_NF_NAT=y
CONFIG_IP6_NF_TARGET_MASQUERADE=y
EOF

# ===== 编译参数 =====
args=(-j$(nproc --all)
    O=${OUT_DIR}
    -C ${KERNEL_DIR}
    ARCH=arm64
	CROSS_COMPILE=aarch64-linux-gnu-
	CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
	CC=clang
	LD=ld.lld
	AR=llvm-ar 
	NM=llvm-nm
	AS=llvm-as
	STRIP=llvm-strip
	OBJCOPY=llvm-objcopy
	OBJDUMP=llvm-objdump
	READELF=llvm-readelf
	HOSTCC=clang
	HOSTCXX=clang++
	HOSTAR=llvm-ar
	HOSTLD=ld.lld
	RUSTC=rustc
    DEPMOD=depmod
    DTC=dtc)
	
#定义默认配置
make ${args[@]} gki_defconfig

#开始编译
make ${args[@]} Image.lz4 modules

#生成modules_install
make ${args[@]} INSTALL_MOD_PATH=modules modules_install

#打包AnyKernel3刷机包
cp -v ${OUT_DIR}/arch/arm64/boot/Image AnyKernel3/Image
cd AnyKernel3
zip -r9v ${OUT_DIR}/kernel.zip *
cd ..


$MKBOOTIMG \
    --kernel out/arch/arm64/boot/Image \
	--header_version 4 \
	-o out/boot.img
$AVBTOOL add_hash_footer \
	--partition_name boot \
	--partition_size $((64 * 1024 * 1024)) \
	--image out/boot.img \
	--algorithm SHA256_RSA2048 \
	--key $BOOT_SIGN_KEY_PATH
#预留，将来更新
#--ramdisk ramdisk.cpio.lz4 \
