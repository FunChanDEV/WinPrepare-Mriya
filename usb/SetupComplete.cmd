@echo off
rem ============================================================================
rem  WinPrepare bootstrap hook.
rem  Runs as SYSTEM at the very end of Windows setup (standard SetupComplete
rem  mechanism). Place this file into:
rem    <USB>:\sources\$OEM$\$$\Setup\Scripts\SetupComplete.cmd
rem  and the WinPrepare folder next to it:
rem    <USB>:\sources\$OEM$\$$\Setup\Scripts\WinPrepare\
rem ============================================================================
if exist "%WINDIR%\Setup\Scripts\WinPrepare\Bootstrap.ps1" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WINDIR%\Setup\Scripts\WinPrepare\Bootstrap.ps1" >> "%WINDIR%\Setup\Scripts\WinPrepare\bootstrap.log" 2>&1
)
