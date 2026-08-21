@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "PROJECT_DIR=%~dp0"
set "GODOT_GUI=%GODOT_BIN%"
set "GODOT_IMPORT=%GODOT_BIN%"

if not defined GODOT_GUI (
    for /f "delims=" %%G in ('where godot 2^>nul') do if not defined GODOT_GUI set "GODOT_GUI=%%G"
)
if not defined GODOT_GUI (
    for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*") do (
        for %%G in ("%%~fD\Godot_v*-stable_win64.exe") do if exist "%%~fG" if not defined GODOT_GUI set "GODOT_GUI=%%~fG"
    )
)
if not defined GODOT_IMPORT (
    for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*") do (
        for %%G in ("%%~fD\Godot_v*-stable_win64_console.exe") do if exist "%%~fG" if not defined GODOT_IMPORT set "GODOT_IMPORT=%%~fG"
    )
)
if not defined GODOT_IMPORT set "GODOT_IMPORT=%GODOT_GUI%"

if not defined GODOT_GUI (
    echo Godot executable not found. Install Godot or set GODOT_BIN to its full path.
    pause
    exit /b 1
)

if not exist "%PROJECT_DIR%build\world_res" (
    echo World resources not found: %PROJECT_DIR%build\world_res
    echo Run client_godot\build_remote.sh or generate the Godot resources first.
    exit /b 1
)
if not exist "%PROJECT_DIR%build\audio" (
    echo Audio resources not found: %PROJECT_DIR%build\audio
    echo Run client_godot\build_remote.sh or generate the Godot resources first.
    exit /b 1
)

rem Runtime resource trees are loaded through MIR2X_*_RES and can contain
rem hundreds of thousands of files. Keep the Godot importer out of them.
if not exist "%PROJECT_DIR%build\world_res\.gdignore" type nul > "%PROJECT_DIR%build\world_res\.gdignore"
if not exist "%PROJECT_DIR%build\audio\.gdignore" type nul > "%PROJECT_DIR%build\audio\.gdignore"

set "MIR2X_WORLD_RES=%PROJECT_DIR%build\world_res"
set "MIR2X_AUDIO_RES=%PROJECT_DIR%build\audio"

rem Source runs do not import newly copied external resources automatically.
rem Run the incremental editor scan first so fonts and other assets have valid
rem .import metadata/cache entries on a fresh Windows workspace.
"%GODOT_IMPORT%" --headless --editor --path "%PROJECT_DIR%." --quit
if errorlevel 1 (
    echo Godot resource import failed.
    pause
    exit /b 1
)

start "" "%GODOT_GUI%" --path "%PROJECT_DIR%." %*
exit /b 0
