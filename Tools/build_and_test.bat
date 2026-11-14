@echo off
rem Builds the GDExtension, imports the project and runs every headless test
rem on Windows, stopping at the first step that fails with a hint to fix it.
rem
rem Usage (from any folder, or double-click):
rem   Tools\build_and_test.bat            build, import, run the tests
rem   Tools\build_and_test.bat editor     same, then open the editor
rem   Tools\build_and_test.bat nopause    do not wait for a key at the end
rem
rem Godot path: set GODOT to the console executable before running, or edit
rem DEFAULT_GODOT below. Otherwise the script looks for
rem Godot_v4.7*_win64_console.exe on PATH, then in C:\Godot, Program Files,
rem Downloads and Desktop (subfolders included). For a first-time setup see
rem "Windows setup from scratch" in Docs\build.md.

setlocal EnableExtensions DisableDelayedExpansion
set "DEFAULT_GODOT=C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
set "DLL=bin\libfalemag.windows.template_debug.x86_64.dll"
rem Saved before "shift" below, which also moves %0 and so %~dp0.
set "TOOLS_DIR=%~dp0"

set "OPEN_EDITOR="
set "NO_PAUSE="
:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="editor" (set "OPEN_EDITOR=1") else if /i "%~1"=="nopause" (set "NO_PAUSE=1") else (
    echo Unknown option "%~1". Options: editor, nopause
    exit /b 2
)
shift
goto parse_args
:args_done

rem The script lives in Tools\, so the repository root is one level up.
pushd "%TOOLS_DIR%.." || (
    echo [FAIL] Cannot open the repository folder "%TOOLS_DIR%..".
    exit /b 1
)
set "ROOT=%CD%"

echo.
echo [1/7] Repository: "%ROOT%"
if not exist "project.godot" call :fail "project.godot not found. Keep this script in the Tools folder of the fal-gaming clone." & goto end
if not exist "Assets\Sfx\arrow.wav" call :fail "Files are missing: the clone or checkout did not finish. In the repository run: git restore --source=HEAD :/ then git lfs pull" & goto end
rem Without Git LFS the sounds are small text pointers instead of WAV files.
findstr /b /l /c:"version https://git-lfs" "Assets\Sfx\arrow.wav" >nul 2>&1 && (call :fail "Sounds and images are Git LFS pointers. Install Git LFS, then run: git lfs install and git lfs pull" & goto end)

echo.
echo [2/7] Godot
if defined GODOT goto godot_chosen
if exist "%DEFAULT_GODOT%" set "GODOT=%DEFAULT_GODOT%" & goto godot_chosen
for /f "delims=" %%G in ('where Godot_v4.7*_win64_console.exe 2^>nul') do if not defined GODOT set "GODOT=%%G"
if not defined GODOT call :find_godot "C:\Godot"
if not defined GODOT call :find_godot "%ProgramFiles%\Godot"
if not defined GODOT call :find_godot "%USERPROFILE%\Downloads"
if not defined GODOT call :find_godot "%USERPROFILE%\Desktop"
if not defined GODOT call :fail "Godot 4.7 not found. Download Godot 4.7.2 Windows 64-bit from https://godotengine.org/download/archive/4.7.2-stable/ and unzip it to C:\Godot, or run: set GODOT=C:\path\to\Godot_v4.7.2-stable_win64_console.exe" & goto end
:godot_chosen
rem Accept a path set with quotes, such as set GODOT="C:\Godot\godot.exe".
set "GODOT=%GODOT:"=%"
echo       "%GODOT%"
if not exist "%GODOT%" call :fail "No file at this GODOT path. Fix the path, or clear it with: set GODOT=" & goto end
echo "%GODOT%" | findstr /i /l /c:"_console" >nul || echo [WARN] Use the *_console.exe that ships next to Godot.exe: the plain exe hides the test output.
"%GODOT%" --version | findstr /b /l /c:"4.7." >nul || call :fail "This Godot is not version 4.7.x. The project needs Godot 4.7.2." || goto end

echo.
echo [3/7] godot-cpp submodule
rem Run it every time: after a pull that moves the godot-cpp pin, the folder
rem exists but holds the old commit. It does nothing when already up to date.
if exist ".git" (
    git submodule update --init || (call :fail "git submodule update failed. Is Git installed?" & goto end)
)
if not exist "Native\godot-cpp\SConstruct" call :fail "Native\godot-cpp is still empty. Clone with: git clone --recurse-submodules https://github.com/nhatphucpham/fal-gaming.git" & goto end

echo.
echo [4/7] Python and SCons
set "PY="
python -c "import sys; sys.exit(sys.version_info[0] < 3)" >nul 2>&1 && set "PY=python"
if not defined PY py -3 -c "import sys" >nul 2>&1 && set "PY=py -3"
if not defined PY call :fail "Python 3 not found. Install it from python.org and tick 'Add python.exe to PATH'." & goto end
%PY% -c "import SCons,sys; v=tuple(int(x) for x in SCons.__version__.split('.')[:2]); sys.exit(0 if v>=(4,11) else 1)" >nul 2>&1 || (
    echo       Installing or upgrading SCons ^(4.11 or later is needed to find Visual Studio^)
    %PY% -m pip install --upgrade "scons>=4.11" || (call :fail "pip could not install SCons." & goto end)
)

echo.
echo [5/7] Build the C++ extension (the first build takes a few minutes)
%PY% -m SCons target=template_debug || (call :fail "The C++ build failed. If Godot is open, close it, since it locks the DLL. Otherwise install Visual Studio 2022 or 2026 Build Tools with the 'Desktop development with C++' workload, then run again." & goto end)
if not exist "%DLL%" call :fail "The build finished but %DLL% is missing." & goto end
if not exist "bin\libfalemag.windows.template_debug.x86_64.exp" echo [WARN] No .exp file next to the DLL: SCons may have used MinGW instead of Visual Studio.

echo.
echo [6/7] Import the project
rem Godot 4.7.2 crashes on exit after the first import of a fresh clone that
rem has a GDExtension. Listing the extension first avoids it (Docs\build.md).
if not exist ".godot" mkdir ".godot"
> ".godot\extension_list.cfg" echo res://falemag.gdextension
"%GODOT%" --headless --editor --path "%ROOT%" --import || (call :fail "The Godot import failed. Read the errors above." & goto end)

echo.
echo [7/7] Tests
set "PASSED=0"
set "FAILED="
rem The smoke test checks that the extension loads, so it goes first.
call :run_test smoke_test
if defined FAILED call :fail "The smoke test failed, so the C++ extension did not load. Read the errors above." & goto end
for %%T in (Tests\*_test.gd) do if /i not "%%~nT"=="smoke_test" call :run_test %%~nT
rem Like CI, also start the main scene for two frames.
echo.
echo ---- main scene start
"%GODOT%" --headless --path "%ROOT%" --quit-after 2
if not "%ERRORLEVEL%"=="0" (set "FAILED=%FAILED% main_scene_start") else (set /a PASSED+=1 >nul)
echo.
echo Passed: %PASSED%
if defined FAILED call :fail "Failed:%FAILED%" & goto end
echo All tests passed.

if defined OPEN_EDITOR (
    echo Opening the editor...
    start "" "%GODOT%" --editor --path "%ROOT%"
)
set "EXIT_CODE=0"
goto end

:run_test
echo.
echo ---- %~1
"%GODOT%" --headless --path "%ROOT%" --script "res://Tests/%~1.gd"
rem Any non-zero code fails, including the negative codes of a crash.
if not "%ERRORLEVEL%"=="0" (set "FAILED=%FAILED% %~1") else (set /a PASSED+=1 >nul)
exit /b 0

rem Sets GODOT to the first Godot 4.7 console executable under the folder.
:find_godot
if not exist "%~1\" exit /b 0
for /r "%~1" %%G in (Godot_v4.7*_win64_console.exe) do if not defined GODOT set "GODOT=%%G"
exit /b 0

rem Prints the message, marks the run failed and returns a non-zero code so
rem "call :fail ... || goto end" also works.
:fail
echo.
echo [FAIL] %~1
set "EXIT_CODE=1"
exit /b 1

:end
popd
if not defined EXIT_CODE set "EXIT_CODE=1"
echo.
if "%EXIT_CODE%"=="0" (echo Done.) else (echo Stopped. Fix the step marked [FAIL] above and run again.)
if not defined NO_PAUSE pause
exit /b %EXIT_CODE%
