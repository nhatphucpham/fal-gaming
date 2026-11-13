@echo off
setlocal
if not defined UE_ROOT (
	echo Set UE_ROOT to your Unreal Engine 5.5 installation directory. 1>&2
	exit /b 1
)
call "%UE_ROOT%\Engine\Build\BatchFiles\Build.bat" FalemagEditor Win64 Development -Project="%~dp0..\Falemag.uproject" -WaitMutex -NoHotReload %*
exit /b %errorlevel%
