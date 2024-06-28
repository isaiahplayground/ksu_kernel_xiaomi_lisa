#!/bin/bash
#
# Compile script for QuicksilveR kernel
# Copyright (C) 2020-2021 Adithya R.

SECONDS=0 # builtin bash timer
TC_DIR="$HOME/tc/clang-r450784d"
AK3_DIR="$HOME/AnyKernel3"
DEFCONFIG="lisa_defconfig"

ZIPNAME="QuicksilveR-lisa-$(date '+%Y%m%d-%H%M').zip"

# Telegram Integration Variables
CHAT_ID="1865106728"
PUBCHAT_ID="-1001865106728"
BOT_ID="7478955642:AAGGCsWTxY9VXYrzi_I0biNuZLMMf_2DDPk"

function publicinfo() {
    curl -s -X POST "https://api.telegram.org/bot${BOT_ID}/sendMessage" \
        -d chat_id="$PUBCHAT_ID" \
        -d "disable_web_page_preview=true" \
        -d "parse_mode=html" \
        -d text="<b>Automated build started for ${DEVICE} (${CODENAME})</b>"
}
function sendinfo() {
    curl -s -X POST "https://api.telegram.org/bot${BOT_ID}/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d "disable_web_page_preview=true" \
        -d "parse_mode=html" \
        -d text="<b>Laboratory Machine: Build Triggered</b>%0A<b>Docker: </b><code>$DISTRO</code>%0A<b>Build Date: </b><code>${DATE}</code>%0A<b>Device: </b><code>${DEVICE} (${CODENAME})</code>%0A<b>Kernel Version: </b><code>$(make kernelversion 2>/dev/null)</code>%0A<b>Build Type: </b><code>${TYPE}</code>%0A<b>Compiler: </b><code>${COMPILER_NAME}</code>%0A<b>Linker: </b><code>${LINKER_NAME}</code>%0A<b>Zip Name: </b><code>${KVERSION}</code>%0A<b>Branch: </b><code>$(git rev-parse --abbrev-ref HEAD)</code>%0A<b>Last Commit Details: </b><a href='${REPO_URL}/commit/${COMMIT_HASH}'>${COMMIT_HASH}</a> <code>($(git log --pretty=format:'%s' -1))</code>"
}

if test -z "$(git rev-parse --show-cdup 2>/dev/null)" &&
   head=$(git rev-parse --verify HEAD 2>/dev/null); then
	ZIPNAME="${ZIPNAME::-4}-$(echo $head | cut -c1-8).zip"
fi

MAKE_PARAMS="O=out ARCH=arm64 CC=clang CLANG_TRIPLE=aarch64-linux-gnu- LLVM=1 LLVM_IAS=1 \
	CROSS_COMPILE=$TC_DIR/bin/llvm-"

export PATH="$TC_DIR/bin:$PATH"

if [[ $1 = "-r" || $1 = "--regen" ]]; then
	make $MAKE_PARAMS $DEFCONFIG savedefconfig
	cp out/defconfig arch/arm64/configs/$DEFCONFIG
	echo -e "\nSuccessfully regenerated defconfig at $DEFCONFIG"
	exit
fi

if [[ $1 = "-c" || $1 = "--clean" ]]; then
	rm -rf out
	echo "Cleaned output folder"
fi

mkdir -p out
make $MAKE_PARAMS $DEFCONFIG

echo -e "\nStarting compilation...\n"
make -j$(nproc --all) $MAKE_PARAMS || exit $?
make -j$(nproc --all) $MAKE_PARAMS INSTALL_MOD_PATH=modules INSTALL_MOD_STRIP=1 modules_install

kernel="out/arch/arm64/boot/Image"
dtb="out/arch/arm64/boot/dts/vendor/qcom/yupik.dtb"
dtbo="out/arch/arm64/boot/dts/vendor/qcom/lisa-sm7325-overlay.dtbo"

if [ ! -f "$kernel" ] || [ ! -f "$dtb" ] || [ ! -f "$dtbo" ]; then
	echo -e "\nCompilation failed!"
	exit 1
fi

echo -e "\nKernel compiled succesfully! Zipping up...\n"
if [ -d "$AK3_DIR" ]; then
	cp -r $AK3_DIR AnyKernel3
	git -C AnyKernel3 checkout lisa &> /dev/null
elif ! git clone -q https://github.com/likkai/AnyKernel3 -b lisa; then
	echo -e "\nAnyKernel3 repo not found locally and couldn't clone from GitHub! Aborting..."
	exit 1
fi

publicinfo
sendinfo
cp $kernel AnyKernel3
cp $dtb AnyKernel3/dtb
python2 scripts/dtc/libfdt/mkdtboimg.py create AnyKernel3/dtbo.img --page_size=4096 $dtbo
cp $(find out/modules/lib/modules/5.4* -name '*.ko') AnyKernel3/modules/vendor/lib/modules/
cp out/modules/lib/modules/5.4*/modules.{alias,dep,softdep} AnyKernel3/modules/vendor/lib/modules
cp out/modules/lib/modules/5.4*/modules.order AnyKernel3/modules/vendor/lib/modules/modules.load
sed -i 's/\(kernel\/[^: ]*\/\)\([^: ]*\.ko\)/\/vendor\/lib\/modules\/\2/g' AnyKernel3/modules/vendor/lib/modules/modules.dep
sed -i 's/.*\///g' AnyKernel3/modules/vendor/lib/modules/modules.load
rm -rf out/arch/arm64/boot out/modules
cd AnyKernel3
zip -r9 "../$ZIPNAME" * -x .git README.md *placeholder
cd ..
rm -rf AnyKernel3
echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
echo "Zip: $ZIPNAME"
