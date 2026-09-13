# PixelOS udon ROM rescue — pull the zip built by job 299487 out of this workspace
# (temp.sh primary, gofile backup). Read-only on the workspace; uploads only.
set +e
echo "=== workspace state ==="
df -h /tmp | tail -1
ls /tmp/src/android/ 2>/dev/null | head -15
P=/tmp/src/android/out/target/product/udon
echo "=== looking for ROM in $P ==="
ls -la $P/ 2>&1 | head -40
ZIP=$(ls -t $P/PixelOS_*.zip $P/pixelos_*.zip $P/*udon*.zip 2>/dev/null | head -1)
if [ -z "$ZIP" ]; then
  echo "NO_ZIP_IN_PRIMARY - searching wider (any zip >500MB in workspace)"
  ZIP=$(find /tmp/src/android -maxdepth 6 -name '*.zip' -size +500M 2>/dev/null | head -1)
fi
if [ -z "$ZIP" ]; then
  echo "RESULT: NO ROM ZIP FOUND in this workspace"
  ls -la /tmp/src/android/out/target/product/ 2>&1 | head -10
  exit 3
fi
SZ=$(stat -c%s "$ZIP")
echo "ROM FOUND: $ZIP ($SZ bytes)"
[ "$SZ" -gt 1000000000 ] || { echo "zip too small ($SZ) - not the ROM, aborting"; exit 4; }
md5sum "$ZIP"
cd "$(dirname "$ZIP")"
ZF=$(basename "$ZIP")
echo "=== upload 1/2: temp.sh ==="
R=$(curl -sS --max-time 2400 -F "file=@$ZF" https://temp.sh/upload 2>&1)
echo "temp.sh response: $R"
echo "$R" | grep -oE 'https://temp\.sh/[A-Za-z0-9/.]+' | head -1
echo "=== upload 2/2: gofile (backup link) ==="
SRVS=$(curl -s --max-time 30 https://api.gofile.io/servers | grep -oE '"name":"[^"]+"' | cut -d'"' -f4)
echo "gofile servers: $SRVS"
for S in $SRVS; do
  R=$(curl -sS --max-time 2400 -F "file=@$ZF" "https://$S.gofile.io/contents/uploadfile" 2>&1)
  L=$(echo "$R" | grep -oE '"downloadPage":"[^"]+"' | cut -d'"' -f4)
  if [ -n "$L" ]; then echo "GOFILE_LINK: $L"; break; fi
  echo "gofile $S failed: $(echo "$R" | head -c 150)"
done
echo "=== rescue complete ==="
exit 0
