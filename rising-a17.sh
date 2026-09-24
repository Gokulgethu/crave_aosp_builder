# RisingOS Android 17 (seventeen) - udon (OnePlus 11R) | Gokulgethu
# Short build: crave resync.sh, GMS/soong/gcc fix pins, temp.sh-first upload.
export BUILD_USERNAME=Gokulgethu
export BUILD_HOSTNAME=crave
git config --global user.name "Gokulgethu"
git config --global user.email "gokulgethu30@gmail.com"
set -e

# 1) source
rm -rf .repo/local_manifests
repo init -u https://github.com/RisingOS-Revived/android -b seventeen --git-lfs --depth=1
git clone --depth 1 https://github.com/Gokulgethu/local_manifests .repo/local_manifests
cat > .repo/local_manifests/zzz-udon-fixes.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote name="evo-gh" fetch="https://github.com/Evolution-X" />
  <remove-project path="vendor/gms" />
  <project path="vendor/gms" name="vendor_gms" remote="evo-gh" revision="refs/heads/cnb" clone-depth="1" />
  <remote name="rising-gh" fetch="https://github.com/RisingOS-Revived" />
  <remove-project path="build/soong" />
  <project path="build/soong" name="android_build_soong" remote="rising-gh" revision="refs/heads/seventeen" />
  <remote name="los-gh" fetch="https://github.com/LineageOS" />
  <project path="prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9" name="android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9" remote="los-gh" clone-depth="1" />
  <project path="prebuilts/gcc/linux-x86/x86/x86_64-linux-android-4.9" name="android_prebuilts_gcc_linux-x86_x86_x86_64-linux-android-4.9" remote="los-gh" clone-depth="1" />
</manifest>
EOF

# 2) sync via crave's resync tool (updates repo, cleans, syncs with build cache)
rm -rf external/chromium-webview/patches
/opt/crave/resync.sh
[ -f device/oneplus/udon/AndroidProducts.mk ] || { echo "FATAL: udon tree missing"; exit 1; }

# 3) build
source build/envsetup.sh
riseup udon userdebug || lunch rising_udon-userdebug
export RELAX_USES_LIBRARY_CHECK=true
rise b || mka bacon -j$(nproc)

# 4) verify + upload
P=out/target/product/udon
ZIP=$(ls -t $P/RisingOS_*.zip $P/*udon*.zip 2>/dev/null | head -1)
[ -n "$ZIP" ] || { echo "BUILD FAILED - no zip"; ls $P 2>/dev/null; tail -c 8000 out/error.log 2>/dev/null; exit 1; }
ls -la $P/boot.img $P/dtbo.img $P/vendor_boot.img "$ZIP"
md5sum "$ZIP"
F=$(basename "$ZIP")
cd $P
echo "--- temp.sh ---"
curl -sS --max-time 2400 -F "file=@$F" https://temp.sh/upload; echo
echo "--- gofile ---"
S=$(curl -s https://api.gofile.io/servers | grep -oE '"name":"[^"]+"' | cut -d'"' -f4 | head -1)
G=$(curl -sS --max-time 2400 -F "file=@$F" "https://$S.gofile.io/contents/uploadfile" | grep -oE '"downloadPage":"[^"]+"' | cut -d'"' -f4)
if [ -n "$G" ]; then echo "GOFILE_LINK: $G"; else echo "--- bashupload ---"; curl -T "$F" bashupload.com; fi
echo "=== DONE: $F ==="
exit 0
