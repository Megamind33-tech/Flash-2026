#!/usr/bin/env bash
# Licence-free compile check: compiles every GRIDLINE assembly with Unity's bundled Roslyn against the
# editor's reference assemblies. Proves C# validity against the exact Unity API; it does NOT import assets
# or run the game. Requires an extracted Unity Linux editor (no activation needed):
#   UNITY_DATA=/path/to/Editor/Data tools/compile-check.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
E="${UNITY_DATA:?set UNITY_DATA to <unity>/Editor/Data}"
OUT="$(mktemp -d)"
DEFS="UNITY_6000_0_OR_NEWER;UNITY_6000_3_OR_NEWER;UNITY_ANDROID;UNITY_2019_4_OR_NEWER;UNITY_2021_3_OR_NEWER;UNITY_2022_3_OR_NEWER;UNITY_2023_1_OR_NEWER;ENABLE_LEGACY_INPUT_MANAGER;UNITY_INCLUDE_TESTS"
SH="$E/NetStandard/compat/2.1.0/shims/netfx"
BASE=(-r:"$E/NetStandard/ref/2.1.0/netstandard.dll")
for f in "$E"/Managed/UnityEngine/UnityEngine*.dll; do BASE+=(-r:"$f"); done
ED=(); for f in "$E"/Managed/UnityEngine/UnityEditor*.dll; do ED+=(-r:"$f"); done
PKG="$E/Resources/PackageManager/BuiltInPackages"
NUNIT="$PKG/com.unity.ext.nunit/net40/unity-custom/nunit.framework.dll"
TESTRUNNER="$(find "$E" -name UnityEngine.TestRunner.dll | head -1)"

csc() { local out=$1; shift; "$E/NetCoreRuntime/dotnet" "$E/DotNetSdkRoslyn/csc.dll" -nologo -noconfig -nostdlib -target:library \
  -langversion:9 -nowarn:0618,0649,0414,0169 -warnaserror- -define:"$DEFS" -out:"$OUT/$out" "${BASE[@]}" "$@"; echo "ok  $out"; }
files() { find "$@" -name '*.cs' -print0 | xargs -0 printf '%s\n'; }

mapfile -t UGUI < <(files "$PKG/com.unity.ugui/Runtime/UGUI" "$PKG/com.unity.ugui/Runtime/InternalBridge")
csc UnityEngine.UI.dll -unsafe "${UGUI[@]}"
mapfile -t F < <(files "$ROOT/Assets/Gridline/Core");                   csc Gridline.Core.dll "${F[@]}"
mapfile -t F < <(files "$ROOT/Assets/ThirdParty/RVP/Scripts");          csc RVP.Runtime.dll "${ED[@]}" -define:"$DEFS;UNITY_EDITOR" "${F[@]}"
R=(-r:"$OUT/Gridline.Core.dll" -r:"$OUT/RVP.Runtime.dll" -r:"$OUT/UnityEngine.UI.dll")
mapfile -t F < <(files "$ROOT/Assets/Gridline/Runtime");                csc Gridline.Runtime.dll "${R[@]}" "${F[@]}"
R+=(-r:"$OUT/Gridline.Runtime.dll")
mapfile -t F < <(files "$ROOT/Assets/Gridline/Editor");                 csc Gridline.Editor.dll "${ED[@]}" "${R[@]}" "${F[@]}"
T=(-r:"$NUNIT" -r:"$TESTRUNNER" -r:"$SH/mscorlib.dll" -r:"$SH/System.dll" -r:"$SH/System.Core.dll")
mapfile -t F < <(files "$ROOT/Assets/Gridline/Tests/EditMode");         csc Gridline.Tests.EditMode.dll "${ED[@]}" "${R[@]}" -r:"$OUT/Gridline.Editor.dll" "${T[@]}" "${F[@]}"
mapfile -t F < <(files "$ROOT/Assets/Gridline/Tests/PlayMode");         csc Gridline.Tests.PlayMode.dll "${ED[@]}" "${R[@]}" "${T[@]}" -define:"$DEFS;UNITY_EDITOR" "${F[@]}"
echo "All GRIDLINE assemblies compile against $(sed -n 's/^m_EditorVersion: //p' "$ROOT/ProjectSettings/ProjectVersion.txt") reference assemblies."
