#!/usr/bin/env bash
# Repack a stock Android 14 GSI system.img into a LombardOS GSI.
# This modifies the system partition image only; it is not a full AOSP build.
set -Eeuo pipefail
if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: sudo $0 <stock-system.img> <LombardSetup.apk> [out-dir]" >&2
  exit 2
fi
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run with sudo: mounting the image requires root." >&2
  exit 1
fi
ROOT="$(cd "$(dirname "$0")" && pwd)"
IN="$(realpath "$1")"
APK="$(realpath "$2")"
OUT="$(realpath -m "${3:-$ROOT/output}")"
GROW_MB="${GROW_MB:-1024}"
for tool in simg2img img2simg e2fsck resize2fs truncate setfattr file mount umount install sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing required tool: $tool (Ubuntu: android-sdk-libsparse-utils e2fsprogs attr)" >&2
    exit 1
  }
done
[[ -f "$APK" ]] || { echo "APK not found: $APK" >&2; exit 1; }
[[ -f "$ROOT/privapp-permissions-com.lombardos.setup.xml" ]] || {
  echo "Privileged permission XML not found in repository root." >&2
  exit 1
}
WORK="$(mktemp -d)"
MNT="$WORK/mnt"
RAW="$WORK/raw.img"
mkdir -p "$MNT" "$OUT"
cleanup() {
  mountpoint -q "$MNT" && umount "$MNT" || true
  rm -rf "$WORK"
}
trap cleanup EXIT
echo "[1/7] Converting GSI to raw image"
if file "$IN" | grep -qi sparse; then
  simg2img "$IN" "$RAW"
else
  cp --reflink=auto "$IN" "$RAW"
fi
file "$RAW" | grep -Eqi 'ext[234]' || {
  echo "The system image is not ext2/3/4. This script cannot modify EROFS images." >&2
  file "$RAW"
  exit 1
}
echo "[2/7] Expanding image and filesystem before unsharing blocks"
# e2fsck's unshare_blocks option needs free blocks to clone shared extents.
truncate -s "+${GROW_MB}M" "$RAW"
resize2fs "$RAW"
echo "[3/7] Unsharing ext4 blocks and checking filesystem"
set +e
e2fsck -f -y -E unshare_blocks "$RAW"
FSCK_STATUS=$?
set -e
if [[ "$FSCK_STATUS" -gt 1 ]]; then
  echo "e2fsck failed while unsharing blocks (exit $FSCK_STATUS)." >&2
  exit "$FSCK_STATUS"
fi
resize2fs "$RAW"
echo "[4/7] Mounting expanded system image"
mount -o loop,rw "$RAW" "$MNT" || {
  echo "Could not mount the expanded image. Check that this runner supports loop devices." >&2
  exit 1
}
if [[ -d "$MNT/system/system_ext" ]]; then
  SYS="$MNT/system"
else
  SYS="$MNT"
fi
[[ -d "$SYS/system_ext" ]] || {
  echo "Could not locate system_ext in the mounted system image." >&2
  ls -la "$MNT"
  exit 1
}
SE="$SYS/system_ext"
label() {
  setfattr -n security.selinux -v u:object_r:system_file:s0 "$1" 2>/dev/null ||
    echo "Warning: could not set SELinux label on $1"
}
echo "[5/7] Installing LombardSetup as a privileged app"
rm -rf "$SE/priv-app/Provision" "$SYS/priv-app/Provision"
install -d -m 0755 "$SE/priv-app/LombardSetup" "$SE/etc/permissions"
install -m 0644 "$APK" "$SE/priv-app/LombardSetup/LombardSetup.apk"
install -m 0644 "$ROOT/privapp-permissions-com.lombardos.setup.xml" "$SE/etc/permissions/privapp-permissions-com.lombardos.setup.xml"
label "$SE/priv-app/LombardSetup"
label "$SE/priv-app/LombardSetup/LombardSetup.apk"
label "$SE/etc/permissions/privapp-permissions-com.lombardos.setup.xml"
echo "[6/7] Setting Mongolian default locale"
BP="$SYS/build.prop"
[[ -f "$BP" ]] || { echo "build.prop not found at $BP" >&2; exit 1; }
if grep -q '^ro.product.locale=' "$BP"; then
  sed -i 's/^ro.product.locale=.*/ro.product.locale=mn-MN/' "$BP"
else
  printf '\nro.product.locale=mn-MN\n' >> "$BP"
fi
echo "[7/7] Unmounting, checking and writing output"
sync
umount "$MNT"
e2fsck -f -n "$RAW"
img2simg "$RAW" "$OUT/lombardos-system.img"
(
  cd "$OUT"
  sha256sum lombardos-system.img | tee lombardos-system.img.sha256
)
echo "Done: $OUT/lombardos-system.img (NOT boot-tested)"
