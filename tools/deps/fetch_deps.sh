#!/usr/bin/env bash
# Reproducible download of every engine and build dependency for the Godot port.
# Idempotent: skips any file already present with the pinned SHA-256. Nothing is written into the repo.
#   DEPS_DIR=/home/user/deps tools/deps/fetch_deps.sh
# Pins: Godot 4.7.2 (editor + export templates), Blender 4.0.2 (tools/cars pipeline), Android SDK
# (platform 36, build-tools 35.0.0, platform-tools). JDK 17+ and Python 3 with Pillow must already exist.
set -euo pipefail
DEPS="${DEPS_DIR:-/home/user/deps}"
mkdir -p "$DEPS"
fetch() {  # fetch <url> <dest> <sha256>
  local url="$1" dest="$2" sha="$3"
  if [[ -f "$dest" ]] && echo "$sha  $dest" | sha256sum -c --status 2>/dev/null; then
    echo "ok (cached)  $dest"; return
  fi
  echo "download     $url"
  curl -sSL --retry 4 --retry-delay 2 -o "$dest.part" "$url"
  echo "$sha  $dest.part" | sha256sum -c --status || { echo "SHA-256 MISMATCH for $url" >&2; rm -f "$dest.part"; exit 1; }
  mv "$dest.part" "$dest"
}

GODOT_TAG=4.7.2-stable
GODOT_REL="https://github.com/godotengine/godot-builds/releases/download/$GODOT_TAG"
fetch "$GODOT_REL/Godot_v4.7.2-stable_linux.x86_64.zip" "$DEPS/godot.zip" \
  cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4
fetch "$GODOT_REL/Godot_v4.7.2-stable_export_templates.tpz" "$DEPS/godot_templates.tpz" \
  f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011
fetch "https://download.blender.org/release/Blender4.0/blender-4.0.2-linux-x64.tar.xz" "$DEPS/blender.tar.xz" \
  5583a5588736da8858c522ef17fff5d73be59c47a6fe91ad29c6f3263e22086a
fetch "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" "$DEPS/cmdline-tools.zip" \
  2d2d50857e4eb553af5a6dc3ad507a17adf43d115264b1afc116f95c92e5e258

# Unpack
mkdir -p "$DEPS/godot-4.7.2" "$DEPS/blender-4.0.2" "$DEPS/android-sdk"
[[ -x "$DEPS/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64" ]] || { unzip -q -o "$DEPS/godot.zip" -d "$DEPS/godot-4.7.2"; chmod +x "$DEPS/godot-4.7.2/"*.x86_64; }
[[ -x "$DEPS/blender-4.0.2/blender" ]] || tar -xJf "$DEPS/blender.tar.xz" -C "$DEPS/blender-4.0.2" --strip-components=1

# Export templates go where the editor looks for them
TPL="$HOME/.local/share/godot/export_templates/4.7.2.stable"
if [[ ! -f "$TPL/android_debug.apk" ]]; then
  mkdir -p "$TPL" && unzip -q -o "$DEPS/godot_templates.tpz" -d "$TPL.tmp" && mv "$TPL.tmp/templates/"* "$TPL/" && rm -rf "$TPL.tmp"
fi

# Android SDK packages (licences accepted non-interactively)
SDK="$DEPS/android-sdk"
if [[ ! -d "$SDK/cmdline-tools/latest" ]]; then
  unzip -q -o "$DEPS/cmdline-tools.zip" -d "$SDK" && mkdir -p "$SDK/cmdline-tools/latest" \
   && mv "$SDK/cmdline-tools/bin" "$SDK/cmdline-tools/lib" "$SDK/cmdline-tools/source.properties" "$SDK/cmdline-tools/NOTICE.txt" "$SDK/cmdline-tools/latest/"
fi
export ANDROID_HOME="$SDK"
yes | "$SDK/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null 2>&1 || true
"$SDK/cmdline-tools/latest/bin/sdkmanager" "platform-tools" "build-tools;35.0.0" "platforms;android-36" >/dev/null

# Debug keystore for APK signing (never committed; *.keystore is gitignored)
KS="$DEPS/keystore/debug.keystore"
if [[ ! -f "$KS" ]]; then
  mkdir -p "$DEPS/keystore"
  keytool -genkeypair -keystore "$KS" -storepass android -keypass android -alias androiddebugkey \
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi

echo
echo "Godot : $DEPS/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64"
echo "Blender: $DEPS/blender-4.0.2/blender"
echo "Android: ANDROID_HOME=$SDK"
echo "Export env:  GODOT_ANDROID_KEYSTORE_DEBUG_PATH=$KS GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android"
