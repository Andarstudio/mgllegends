#!/usr/bin/env bash
# Repack a stock Android 14 GSI system.img into a LombardOS GSI. No AOSP build needed.
# UNTESTED: written without access to a real GSI. Run it and report any error.
set -euo pipefail

[ $# -ge 2 ] || { echo "Usage: sudo $0 <stock-system.img> <LombardSetup.apk> [out-dir]"; exit 1; }
[ "$(id -u)" = 0 ] || { echo "Run with sudo: mounting the image needs a loop device."; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IN="$(realpath "$1")"; APK="$(realpath "$2")"; OUT="$(realpath -m "${3:-$ROOT/output}")"
XML="$ROOT privapp-permissions-com.lombardos.setup.xml"
GROW_MB=256

for t in simg2img img2simg e2fsck resize2fs truncate setfattr file mount; do
  command -v "$t" >/dev/null || { echo "Missing tool: $t (Ubuntu: apt install android-sdk-libsparse-utils e2fsprogs attr)"; exit 1; }
done
[ -f "$APK" ] && [ -f "$XML" ] || { echo "APK or permissions XML not found"; exit 1; }

WORK="$(mktemp -d)"; MNT="$WORK/mnt"; RAW="$WORK/raw.img"; mkdir -p "$MNT" "$OUT"
cleanup(){ mountpoint -q "$MNT" && umount "$MNT" || true; rm -rf "$WORK"; }
trap cleanup EXIT

echo "[1/7] Converting to raw"
if file "$IN" | grep -qi "sparse"; then simg2img "$IN" "$RAW"; else cp "$IN" "$RAW"; fi
file "$RAW" | grep -Eqi "ext[234]" || { echo "Not ext4 (maybe EROFS). Unsupported by this script."; file "$RAW"; exit 1; }

echo "[2/7] Unsharing blocks and growing image by ${GROW_MB} MB"
e2fsck -fy -E unshare_blocks "$RAW" || [ $? -le 1 ]
truncate -s +${GROW_MB}M "$RAW"
e2fsck -fy "$RAW" || [ $? -le 1 ]
resize2fs "$RAW"

echo "[3/7] Mounting"
mount -o loop,rw "$RAW" "$MNT" || { echo "Loop mount failed. Codespaces often blocks loop devices; use a Linux VM or PC."; exit 1; }
if [ -d "$MNT/system/system_ext" ]; then SYS="$MNT/system"; else SYS="$MNT"; fi
[ -d "$SYS/system_ext" ] || { echo "Cannot find system_ext in image"; ls "$MNT"; exit 1; }
SE="$SYS/system_ext"
echo "system root: $SYS"

label(){ setfattr -n security.selinux -v u:object_r:system_file:s0 "$1" 2>/dev/null || echo "WARN: could not set SELinux label on $1"; }

echo "[4/7] Installing LombardSetup as privileged app"
rm -rf "$SE/priv-app/Provision" "$SYS/priv-app/Provision"   # default AOSP first-boot app, replaced by LombardSetup
install -d -m 0755 "$SE/priv-app/LombardSetup" "$SE/etc/permissions"
install -m 0644 "$APK" "$SE/priv-app/LombardSetup/LombardSetup.apk"
install -m 0644 "$XML" "$SE/etc/permissions/privapp-permissions-com.lombardos.setup.xml"
label "$SE/priv-app/LombardSetup"; label "$SE/priv-app/LombardSetup/LombardSetup.apk"
label "$SE/etc/permissions/privapp-permissions-com.lombardos.setup.xml"

echo "[5/7] Setting Mongolian default locale"
BP="$SYS/build.prop"; [ -f "$BP" ] || { echo "build.prop not found at $BP"; exit 1; }
if grep -q '^ro.product.locale=' "$BP"; then sed -i 's/^ro.product.locale=.*/ro.product.locale=mn-MN/' "$BP"
else printf '\nro.product.locale=mn-MN\n' >> "$BP"; fi

echo "[6/7] Unmounting and checking"
sync; umount "$MNT"; e2fsck -fy "$RAW" || [ $? -le 1 ]

echo "[7/7] Writing output"
img2simg "$RAW" "$OUT/lombardos-system.img"
( cd "$OUT" && sha256sum lombardos-system.img | tee lombardos-system.img.sha256 )
echo "Done: $OUT/lombardos-system.img (NOT boot-tested)"
