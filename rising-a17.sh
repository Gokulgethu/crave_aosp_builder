# RisingOS (Android 17 / seventeen) + OnePlus 11R (udon / CPH2487) | Gokulgethu trees
# Attempt 3 — per user request:
#   * depth-1 everywhere (repo init --depth=1 persists as repo.depth; current repo
#     removed --depth from sync - 301681 died on it, so sync lines no longer pass it)
#   * prebuilts/gcc target toolchains pinned back in (arm-linux-androideabi-4.9 +
#     x86_64-linux-android-4.9 from LineageOS mirrors, clone-depth=1) — also stops
#     repo's "Cannot remove project" conflict from 301391 since they're manifest members now
#   * self-healing sync loop kept (delete only the failing project dirs, retry, -j1 fallback)
# Everything else = the proven recipe (GMS cnb mirror + Rising soong seventeen + RELAX).
export BUILD_USERNAME=Gokulgethu
export BUILD_HOSTNAME=crave
git config --global user.name "Gokulgethu"
git config --global user.email "gokulgethu30@gmail.com"
set -e

echo "=== [1/6] repo init -> RisingOS seventeen (Android 17, depth-1) ==="
rm -rf .repo/local_manifests
repo init -u https://github.com/RisingOS-Revived/android -b seventeen --git-lfs --depth=1 || {
  echo "--- init failed, resetting manifest checkout and retrying once ---"
  rm -rf .repo/manifests .repo/manifest.xml .repo/local_manifests
  repo init -u https://github.com/RisingOS-Revived/android -b seventeen --git-lfs --depth=1
}

echo "=== [2/6] local manifests: Gokulgethu/local_manifests (my trees) ==="
rm -rf .repo/local_manifests
git clone --depth 1 https://github.com/Gokulgethu/local_manifests .repo/local_manifests
cat > .repo/local_manifests/zzz-udon-fixes.xml <<'FIXEOF'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <!-- Fix 1: vendor/gms from GitHub mirror (forgejo host blocks build-node IPs) -->
  <remote name="evo-gh" fetch="https://github.com/Evolution-X" />
  <remove-project path="vendor/gms" />
  <project path="vendor/gms" name="vendor_gms" remote="evo-gh" revision="refs/heads/cnb" clone-depth="1" />
  <!-- Fix 2: restore Rising's own build/soong (allows the 'data' PATH tool needed to
       compute AVB rollback indexes from PLATFORM_SECURITY_PATCH) -->
  <remote name="rising-gh" fetch="https://github.com/RisingOS-Revived" />
  <remove-project path="build/soong" />
  <project path="build/soong" name="android_build_soong" remote="rising-gh" revision="refs/heads/seventeen" />
  <!-- Fix 3 (user request): prebuilts/gcc target toolchains back in (A17 manifests only
       carry the host ones). Pinned from LineageOS mirrors, shallow. -->
  <remote name="los-gh" fetch="https://github.com/LineageOS" />
  <project path="prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9"
           name="android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9"
           remote="los-gh" clone-depth="1" />
  <project path="prebuilts/gcc/linux-x86/x86/x86_64-linux-android-4.9"
           name="android_prebuilts_gcc_linux-x86_x86_x86_64-linux-android-4.9"
           remote="los-gh" clone-depth="1" />
</manifest>
FIXEOF
cat .repo/local_manifests/zzz-udon-fixes.xml

echo "=== [2b/6] pre-sync heal (from 301391 failure log) ==="
# tangled dirs from the failed passes: delete so the (now-pinned) projects re-clone cleanly
rm -rf prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9
rm -rf prebuilts/gcc/linux-x86/x86/x86_64-linux-android-4.9
rm -rf external/chromium-webview/patches
repo forall -j8 -c 'git checkout -- . 2>/dev/null || true; git clean -fd 2>/dev/null || true' || true

echo "=== [3/6] sync (depth-1, self-healing, up to 3 passes) ==="
SYNC_OK=0
for PASS in 1 2 3; do
  echo "--- sync pass $PASS ---"
  rm -f /tmp/sync.log
  repo sync -c -j$(nproc) --no-tags --prune -d --force-sync --no-clone-bundle --optimized-fetch > /tmp/sync.log 2>&1 && { SYNC_OK=1; break; }
  RC=$?
  echo "--- pass $PASS failed (rc=$RC): last errors ---"
  grep -E "^error:|SyncError|Cannot|fatal:|Usage:|no such option" /tmp/sync.log | tail -12
  echo "--- healing failing project dirs for next pass ---"
  grep -oE '^error: [A-Za-z0-9_./-]+: Cannot remove project' /tmp/sync.log | sed 's/^error: //; s/: Cannot remove project//' | sort -u | while read P; do
    echo "  rm -rf $P"; rm -rf "$P"
  done
  grep -oE '/tmp/src/android/[A-Za-z0-9_./-]+' /tmp/sync.log | sed 's|/tmp/src/android/||' | sort -u | while read P; do
    case "$P" in .repo*|""|.) continue ;; esac
    echo "  rm -rf $P"; rm -rf "$P"
  done
  repo forall -j8 -c 'git checkout -- . 2>/dev/null || true; git clean -fd 2>/dev/null || true' || true
done
if [ "$SYNC_OK" != "1" ]; then
  echo "=== final fallback: repo sync -j1 --fail-fast (surface the first real error) ==="
  repo forall -j8 -c 'git checkout -- . 2>/dev/null || true' || true
  repo sync -c -j1 --fail-fast --no-tags --prune -d --force-sync --no-clone-bundle 2>&1 | tail -40
  RC=${PIPESTATUS[0]}
  [ $RC -eq 0 ] || { echo "FATAL: sync failed after all passes - see errors above"; exit 1; }
fi

[ -f device/oneplus/udon/AndroidProducts.mk ] || { echo "FATAL: udon tree missing after sync"; exit 1; }
echo "device/oneplus now: $(ls device/oneplus)"
echo "prebuilts/gcc/linux-x86/arm: $(ls prebuilts/gcc/linux-x86/arm 2>/dev/null)"

echo "=== [4/6] lunch + build ==="
set +e
source build/envsetup.sh
riseup udon userdebug || {
  echo "--- riseup failed, trying lunch fallbacks ---"
  lunch rising_udon-userdebug || lunch lineage_udon-userdebug || { echo "=== FAILED: no lunch target"; exit 1; }
}
export RELAX_USES_LIBRARY_CHECK=true
rise b || {
  echo "--- rise b failed, falling back to mka bacon ---"
  mka bacon -j$(nproc)
}
RC=$?
echo "=== artifacts in out/target/product/udon ==="
ls -la out/target/product/udon/ 2>/dev/null | tail -35
if [ $RC -ne 0 ]
 then
  echo "=== BUILD FAILED — tail of out/error.log ==="
  tail -c 20000 out/error.log 2>/dev/null
  exit $RC
fi

echo "=== [5/6] acceptance checks: boot + dtbo + vendor_boot + flashable zip ==="
P=out/target/product/udon
FAIL=0
test -f $P/boot.img        || { echo "FATAL: boot.img missing"; FAIL=1; }
test -f $P/dtbo.img        || { echo "FATAL: dtbo.img missing"; FAIL=1; }
test -f $P/vendor_boot.img || { echo "FATAL: vendor_boot.img missing"; FAIL=1; }
ZIP=$(ls -t $P/RisingOS_*.zip $P/rising*.zip $P/*udon*.zip 2>/dev/null | head -1)
[ -n "$ZIP" ] || { echo "FATAL: no flashable zip found in $P"; ls $P/*.zip 2>/dev/null; FAIL=1; }
if [ -f $P/dtbo.img ]; then
  M=$(od -A n -t x1 -N 4 $P/dtbo.img | tr -d ' ')
  [ "$M" = "d7b7ab1e" ] || { echo "FATAL: dtbo.img bad magic: $M"; FAIL=1; }
fi
if [ $FAIL -ne 0 ]; then echo "=== ACCEPTANCE FAILED ==="; exit 1; fi
echo "=== ACCEPTANCE OK: $(basename "$ZIP") with valid dtbo/boot/vendor_boot ==="
ls -la "$ZIP"
md5sum "$ZIP"

echo "=== [6/6] upload ROM: temp.sh -> gofile -> bashupload ==="
cd "$P"
ZF=$(basename "$ZIP")
echo "--- upload 1/3: temp.sh ---"
R=$(curl -sS --max-time 2400 -F "file=@$ZF" https://temp.sh/upload 2>&1)
echo "temp.sh response: $R"
echo "$R" | grep -oE 'https://temp\.sh/[A-Za-z0-9/.]+' | head -1
echo "--- upload 2/3: gofile (multi-server) ---"
SRVS=$(curl -s --max-time 30 https://api.gofile.io/servers | grep -oE '"name":"[^"]+"' | cut -d'"' -f4)
UP=0
for S in $SRVS; do
  R=$(curl -sS --max-time 2400 -F "file=@$ZF" "https://$S.gofile.io/contents/uploadfile" 2>&1)
  L=$(echo "$R" | grep -oE '"downloadPage":"[^"]+"' | cut -d'"' -f4)
  if [ -n "$L" ]; then echo "GOFILE_LINK: $L"; UP=1; break; fi
  echo "gofile $S failed: $(echo "$R" | head -c 150)"
done
echo "--- upload 3/3: bashupload fallback (only if gofile failed) ---"
if [ "$UP" = "0" ]; then
  curl -T "$ZF" bashupload.com 2>&1 | head -8
fi
echo "=== upload step complete ==="
exit 0
