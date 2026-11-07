#!/usr/bin/env bash
# Reports whether this machine can run the prototype build and a full AOSP build.
ok=0; warn=0
pass(){ echo "[ OK ] $*"; }
bad(){ echo "[FAIL] $*"; ok=1; }
note(){ echo "[WARN] $*"; warn=1; }

echo "== OS =="; uname -sm; grep PRETTY_NAME /etc/os-release 2>/dev/null
[ "$(uname -s)" = Linux ] && pass "Linux" || bad "AOSP requires Linux"
grep -qi microsoft /proc/version 2>/dev/null && note "WSL detected: keep sources on the Linux filesystem"

echo "== CPU/RAM/Disk =="
cores=$(nproc); echo "cores: $cores"; [ "$cores" -ge 8 ] && pass "cores" || note "8+ cores recommended"
ram=$(awk '/MemTotal/{printf "%d",$2/1048576}' /proc/meminfo); echo "RAM: ${ram} GB"
[ "$ram" -ge 32 ] && pass "RAM" || { [ "$ram" -ge 16 ] && note "16-31 GB: needs swap, slow" || bad "under 16 GB RAM"; }
free_gb=$(df -P "$HOME" | awk 'NR==2{printf "%d",$4/1048576}'); echo "free disk: ${free_gb} GB"
[ "$free_gb" -ge 400 ] && pass "disk" || note "AOSP needs about 400 GB free (prototype only: 10 GB)"

echo "== Tools =="
for t in git python3 curl zip unzip rsync make; do
  command -v $t >/dev/null && pass "$t" || bad "$t missing"
done
command -v repo >/dev/null && pass "repo" || note "repo missing (needed for AOSP sync only)"
if command -v java >/dev/null; then
  v=$(java -version 2>&1 | head -1); echo "$v"
  echo "$v" | grep -q '"17' && pass "JDK 17" || note "JDK 17 expected"
else bad "java missing"; fi
if [ -n "$ANDROID_HOME" ] && [ -d "$ANDROID_HOME" ]; then pass "ANDROID_HOME=$ANDROID_HOME"; else note "ANDROID_HOME not set (needed for prototype)"; fi
command -v adb >/dev/null && pass "adb" || note "adb not on PATH (add \$ANDROID_HOME/platform-tools)"
command -v gradle >/dev/null && pass "gradle" || note "gradle missing (or use Android Studio)"

echo; [ $ok -eq 0 ] && echo "Result: usable (warnings: $warn)" || echo "Result: blocking problems found"
exit $ok
