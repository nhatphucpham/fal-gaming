@echo off
setlocal
for %%D in (Binaries Intermediate Saved DerivedDataCache) do if exist "%~dp0..\%%D" rmdir /s /q "%~dp0..\%%D"
