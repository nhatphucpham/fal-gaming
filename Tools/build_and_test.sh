#!/usr/bin/env bash
# Builds the GDExtension, imports the project and runs every headless test,
# stopping at the first setup step that fails with a hint to fix it.
# Same steps as Tools/build_and_test.bat, for bash: Git Bash or MSYS2 on
# Windows, and Linux.
#
# Usage (from any folder):
#   Tools/build_and_test.sh           build, import, run the tests
#   Tools/build_and_test.sh editor    same, then open the editor
#
# Godot path: export GODOT=/path/to/godot before running. Otherwise the
# script tries a 4.7 `godot` on PATH, then looks in /c/Godot, Program
# Files/Godot, Downloads and Desktop (Windows), or ~/Godot, ~/Downloads,
# ~/Desktop and /opt/godot (Linux).

set -u

open_editor=0
for arg in "$@"; do
	case "$arg" in
		editor) open_editor=1 ;;
		*) echo "Unknown option \"$arg\". Options: editor"; exit 2 ;;
	esac
done

fail() {
	echo
	echo "[FAIL] $1"
	echo "Stopped. Fix the step marked [FAIL] above and run again."
	exit 1
}

case "$(uname -s)" in
	MINGW* | MSYS* | CYGWIN*) on_windows=1 ;;
	*) on_windows=0 ;;
esac

# The script lives in Tools/, so the repository root is one level up.
cd "$(dirname "$0")/.." || fail "Cannot open the repository folder."
root="$PWD"
if [ "$on_windows" = 1 ]; then
	# Godot is a Windows program: give it E:/... paths and stop MSYS from
	# rewriting arguments such as res://Tests/smoke_test.gd.
	root="$(cygpath -m "$PWD")"
	export MSYS2_ARG_CONV_EXCL='*'
	export MSYS_NO_PATHCONV=1
	godot_pattern='Godot_v4.7*_win64_console.exe'
	dll="bin/libfalemag.windows.template_debug.x86_64.dll"
else
	godot_pattern='Godot_v4.7*_linux.x86_64'
	dll="bin/libfalemag.linux.template_debug.x86_64.so"
fi

echo
echo "[1/7] Repository: $root"
[ -f project.godot ] || fail "project.godot not found. Keep this script in the Tools folder of the fal-gaming clone."
[ -f Assets/Sfx/arrow.wav ] || fail "Files are missing: the clone or checkout did not finish. In the repository run: git restore --source=HEAD :/ && git lfs pull"
# Without Git LFS the sounds are small text pointers instead of WAV files.
if head -c 40 Assets/Sfx/arrow.wav 2>/dev/null | grep -q "^version https://git-lfs"; then
	fail "Sounds and images are Git LFS pointers. Install Git LFS, then run: git lfs install && git lfs pull"
fi

echo
echo "[2/7] Godot"
find_godot() {
	[ -d "$1" ] || return 0
	find "$1" -maxdepth 4 -type f -name "$godot_pattern" 2>/dev/null | head -n 1
}
if [ -z "${GODOT:-}" ]; then
	GODOT="$(command -v godot 2>/dev/null || true)"
	# Only a 4.7 build counts; otherwise keep looking in the folders below.
	if [ -n "$GODOT" ] && ! "$GODOT" --version 2>/dev/null | grep -q "^4\.7\."; then
		GODOT=""
	fi
	if [ "$on_windows" = 1 ]; then
		home_dir="$(cygpath -u "${USERPROFILE:-$HOME}")"
		search_dirs=(/c/Godot "/c/Program Files/Godot" "$home_dir/Downloads" "$home_dir/Desktop")
	else
		search_dirs=("$HOME/Godot" "$HOME/Downloads" "$HOME/Desktop" /opt/godot)
	fi
	for dir in "${search_dirs[@]}"; do
		[ -n "$GODOT" ] && break
		GODOT="$(find_godot "$dir")"
	done
fi
[ -n "$GODOT" ] || fail "Godot 4.7 not found. Download Godot 4.7.2 from https://godotengine.org/download/archive/4.7.2-stable/ (on Windows unzip it to C:\\Godot), or run: export GODOT=/path/to/godot"
echo "      $GODOT"
[ -f "$GODOT" ] || fail "No file at this GODOT path. Fix the path, or clear it with: unset GODOT"
case "$GODOT" in
	*.exe) case "$GODOT" in *_console.exe) ;; *) echo "[WARN] Use the *_console.exe that ships next to Godot.exe: the plain exe hides the test output." ;; esac ;;
esac
"$GODOT" --version 2>/dev/null | grep -q "^4\.7\." || fail "This Godot is not version 4.7.x. The project needs Godot 4.7.2."

echo
echo "[3/7] godot-cpp submodule"
# Run it every time: after a pull that moves the godot-cpp pin, the folder
# exists but holds the old commit. It does nothing when already up to date.
if [ -e .git ]; then
	git submodule update --init || fail "git submodule update failed. Is Git installed?"
fi
[ -f Native/godot-cpp/SConstruct ] || fail "Native/godot-cpp is still empty. Clone with: git clone --recurse-submodules https://github.com/nhatphucpham/fal-gaming.git"

echo
echo "[4/7] Python and SCons"
# On Windows prefer the python.org launcher: MSYS2's own Python makes SCons
# build with MinGW instead of Visual Studio.
python=()
if [ "$on_windows" = 1 ]; then
	# MSYS2 drops the user PATH by default, where python.org and winget put
	# the launcher, so also try its usual install folders.
	for launcher in py "$(cygpath -u "${LOCALAPPDATA:-C:/}")/Programs/Python/Launcher/py.exe" /c/Windows/py.exe; do
		if "$launcher" -3 -c "import sys" >/dev/null 2>&1; then
			python=("$launcher" -3)
			break
		fi
	done
fi
if [ "${#python[@]}" -eq 0 ]; then
	for candidate in python3 python; do
		if "$candidate" -c "import sys; sys.exit(sys.version_info[0] < 3)" >/dev/null 2>&1; then
			python=("$candidate")
			break
		fi
	done
fi
[ "${#python[@]}" -gt 0 ] || fail "Python 3 not found. Install it from python.org (on Windows tick 'Add python.exe to PATH')."
echo "      ${python[*]}"
# 4.11 is needed to find Visual Studio; elsewhere godot-cpp needs only 4.0.
if [ "$on_windows" = 1 ]; then scons_min="4,11"; scons_spec="scons>=4.11"; else scons_min="4,0"; scons_spec="scons>=4.0"; fi
if ! "${python[@]}" -c "import SCons,sys; v=tuple(int(x) for x in SCons.__version__.split('.')[:2]); sys.exit(0 if v>=($scons_min) else 1)" >/dev/null 2>&1; then
	echo "      Installing or upgrading SCons ($scons_spec)"
	if [ "$on_windows" = 1 ]; then
		pip_hint=""
	else
		pip_hint=" Install it with your package manager (such as apt install scons, if it gives 4.0 or later), or in a virtual environment: python3 -m venv ~/.venv-scons && . ~/.venv-scons/bin/activate && pip install scons, then run this script again."
	fi
	"${python[@]}" -m pip install --upgrade "$scons_spec" || fail "pip could not install SCons.$pip_hint"
fi

echo
echo "[5/7] Build the C++ extension (the first build takes a few minutes)"
if [ "$on_windows" = 1 ]; then
	build_hint="If Godot is open, close it, since it locks the DLL. Otherwise install Visual Studio 2022 or 2026 Build Tools with the 'Desktop development with C++' workload, then run again."
else
	build_hint="Install a C++ compiler (g++ or clang), then run again."
fi
"${python[@]}" -m SCons target=template_debug || fail "The C++ build failed. $build_hint"
[ -f "$dll" ] || fail "The build finished but $dll is missing."
if [ "$on_windows" = 1 ] && [ ! -f "${dll%.dll}.exp" ]; then
	echo "[WARN] No .exp file next to the DLL: SCons may have used MinGW instead of Visual Studio."
fi

echo
echo "[6/7] Import the project"
# Godot 4.7.2 crashes on exit after the first import of a fresh clone that
# has a GDExtension. Listing the extension first avoids it (Docs/build.md).
mkdir -p .godot
echo "res://falemag.gdextension" > .godot/extension_list.cfg
"$GODOT" --headless --editor --path "$root" --import || fail "The Godot import failed. Read the errors above."

echo
echo "[7/7] Tests"
passed=0
failed=""
run_godot() {
	local name="$1"
	shift
	echo
	echo "---- $name"
	if "$GODOT" --headless --path "$root" "$@"; then
		passed=$((passed + 1))
	else
		failed="$failed $name"
	fi
}
# The smoke test checks that the extension loads, so it goes first.
run_godot smoke_test --script res://Tests/smoke_test.gd
[ -z "$failed" ] || fail "The smoke test failed, so the C++ extension did not load. Read the errors above."
for test in Tests/*_test.gd; do
	name="$(basename "$test" .gd)"
	[ "$name" = smoke_test ] && continue
	run_godot "$name" --script "res://Tests/$name.gd"
done
# Like CI, also start the main scene for two frames.
run_godot main_scene_start --quit-after 2
echo
echo "Passed: $passed"
[ -z "$failed" ] || fail "Failed:$failed"
echo "All tests passed."

if [ "$open_editor" = 1 ]; then
	echo "Opening the editor..."
	"$GODOT" --editor --path "$root" >/dev/null 2>&1 &
fi
echo
echo "Done."
