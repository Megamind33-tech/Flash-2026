#!/usr/bin/env bash
# Headless Unity runner for any Linux host with Docker (local machine or cloud worker).
# Uses the same GameCI editor image as CI, so local and CI builds are identical.
#
# Licence (never commit these; pass via environment):
#   Personal : UNITY_LICENSE_FILE=/path/to/Unity_lic.ulf   (from Unity Hub after signing in)
#   Pro/Plus : UNITY_SERIAL=... UNITY_EMAIL=... UNITY_PASSWORD=...
#
# Usage: tools/unity-docker.sh build|release|editmode|playmode|prepare
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/^m_EditorVersion: //p' "$ROOT/ProjectSettings/ProjectVersion.txt")"
IMAGE="unityci/editor:ubuntu-${VERSION}-android-3"
CMD="${1:-build}"
mkdir -p "$ROOT/artifacts"

case "$CMD" in
  build)    UNITY_ARGS="-executeMethod BuildScript.BuildAndroid -customBuildPath /project/Builds/Android/Gridline.apk" ;;
  release)  UNITY_ARGS="-executeMethod BuildScript.BuildAndroidRelease -customBuildPath /project/Builds/Android/Gridline.aab" ;;
  prepare)  UNITY_ARGS="-executeMethod BuildScript.PrepareProjectAndExit" ;;
  editmode) UNITY_ARGS="-runTests -testPlatform EditMode -testResults /project/artifacts/editmode-results.xml" ;;
  playmode) UNITY_ARGS="-runTests -testPlatform PlayMode -testResults /project/artifacts/playmode-results.xml" ;;
  *) echo "unknown command: $CMD" >&2; exit 2 ;;
esac

LICENCE_MOUNT=()
ACTIVATE="true"
if [ -n "${UNITY_LICENSE_FILE:-}" ]; then
  LICENCE_MOUNT=(-v "$UNITY_LICENSE_FILE:/root/.local/share/unity3d/Unity/Unity_lic.ulf:ro")
elif [ -n "${UNITY_SERIAL:-}" ]; then
  ACTIVATE='unity-editor -batchmode -nographics -quit -logFile - -serial "$UNITY_SERIAL" -username "$UNITY_EMAIL" -password "$UNITY_PASSWORD"'
else
  echo "No Unity licence: set UNITY_LICENSE_FILE (Personal) or UNITY_SERIAL/UNITY_EMAIL/UNITY_PASSWORD (Pro/Plus)." >&2
  exit 3
fi

# The `quit` flag is omitted for -runTests (the test runner exits by itself).
QUIT="-quit"; [[ "$CMD" == editmode || "$CMD" == playmode ]] && QUIT=""

docker run --rm \
  -e UNITY_SERIAL -e UNITY_EMAIL -e UNITY_PASSWORD -e GRIDLINE_VERSION -e GITHUB_RUN_NUMBER -e GRIDLINE_DEV_BUILD \
  -e GRIDLINE_KEYSTORE_PATH -e GRIDLINE_KEYSTORE_PASS -e GRIDLINE_KEYALIAS_NAME -e GRIDLINE_KEYALIAS_PASS \
  "${LICENCE_MOUNT[@]}" -v "$ROOT:/project" -w /project "$IMAGE" bash -c "
    set -e
    $ACTIVATE
    status=0
    unity-editor -batchmode -nographics $QUIT -projectPath /project -buildTarget Android -logFile /project/artifacts/unity-$CMD.log $UNITY_ARGS || status=\$?
    if [ -n \"\${UNITY_SERIAL:-}\" ]; then unity-editor -batchmode -nographics -quit -returnlicense -username \"\$UNITY_EMAIL\" -password \"\$UNITY_PASSWORD\" || true; fi
    exit \$status
  "
echo "Done: $CMD (log: artifacts/unity-$CMD.log)"
