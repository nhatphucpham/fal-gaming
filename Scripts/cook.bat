@echo off
setlocal
if not defined UE_ROOT (
	echo Set UE_ROOT to your Unreal Engine 5.5 installation directory. 1>&2
	exit /b 1
)
call "%UE_ROOT%\Engine\Build\BatchFiles\RunUAT.bat" BuildCookRun -project="%~dp0..\Falemag.uproject" -noP4 -platform=Win64 -clientconfig=Development -cook -unattended %*
exit /b %errorlevel%
