@echo off
setlocal
echo Starting NeuroCheat 3D in Godot 4...

REM 1. 檢查是否已在系統 PATH (可直接輸入 godot 啟動)
where godot >nul 2>nul
if %errorlevel% equ 0 (
    start "" godot --path "%~dp0."
    exit /b 0
)

REM 2. 檢查專案同層或本機常見的 Godot 執行檔路徑
if exist "%~dp0Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" (
    start "" "%~dp0Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" --path "%~dp0."
    exit /b 0
)

if exist "C:\Users\ACER\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" (
    start "" "C:\Users\ACER\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" --path "%~dp0."
    exit /b 0
)

echo.
echo [提示] 找不到本機的 Godot 執行檔。
echo 請直接打開您的 Godot 4 引擎，點擊「匯入 (Import)」並選擇本資料夾內的 project.godot 即可執行！
echo.
pause
