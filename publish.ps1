# ==================================================
# ANDROID APP MANAGER - FLUTTER AUTOMATED BUILD ORCHESTRATOR
# ==================================================
$ErrorActionPreference = "Stop"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   ANDROID APP MANAGER - BUILD ORCHESTRATOR      " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$FLUTTER_SDK_DIR = "C:\src\flutter"
$BIN_OUT = Join-Path $SCRIPT_DIR "bin"

# 1. Resolve Flutter SDK Environment
Write-Host "[1/4] Resolving Flutter SDK Environment..." -ForegroundColor Yellow
if (Test-Path "$FLUTTER_SDK_DIR\bin\flutter.bat") {
    $env:PATH = "$FLUTTER_SDK_DIR\bin;$env:PATH"
    Write-Host "    [+] Found Flutter SDK at $FLUTTER_SDK_DIR" -ForegroundColor Green
} elseif (Get-Command "flutter" -ErrorAction SilentlyContinue) {
    Write-Host "    [+] Using Flutter from system PATH" -ForegroundColor Green
} else {
    Write-Host "    [-] Flutter SDK not found at $FLUTTER_SDK_DIR" -ForegroundColor Red
    exit 1
}

Set-Location $SCRIPT_DIR

# 2. Fetch Dart Dependencies
Write-Host "[2/4] Resolving Dart Package Dependencies..." -ForegroundColor Yellow
flutter pub get

# 3. Add -D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS to CMakeLists.txt if needed
$CMAKE_FILE = "$SCRIPT_DIR\windows\CMakeLists.txt"
if (Test-Path $CMAKE_FILE) {
    $cmakeContent = Get-Content $CMAKE_FILE -Raw
    if (-not $cmakeContent.Contains("_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS")) {
        $cmakeContent = $cmakeContent.Replace("add_definitions(-DUNICODE -D_UNICODE)", "add_definitions(-DUNICODE -D_UNICODE -D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)")
        Set-Content -Path $CMAKE_FILE -Value $cmakeContent -Force
    }
}

# 4. Compile Windows Desktop EXE & Web HTML Packages
Write-Host "[3/4] Compiling Windows Desktop EXE & Web HTML5 Packages..." -ForegroundColor Yellow
flutter build windows
flutter build web

# 5. Copy Output Binaries to local bin directory
Write-Host "[4/4] Packaging Release Artifacts..." -ForegroundColor Yellow
if (-not (Test-Path $BIN_OUT)) { New-Item -ItemType Directory -Path $BIN_OUT -Force | Out-Null }

$BUILT_EXE_DIR = "$SCRIPT_DIR\build\windows\x64\runner\Release"
$TARGET_EXE_DIR = "$BIN_OUT\appmanager-windows-release"

$BUILT_WEB_DIR = "$SCRIPT_DIR\build\web"
$TARGET_WEB_DIR = "$BIN_OUT\appmanager-web-release"

if (Test-Path $BUILT_EXE_DIR) {
    Stop-Process -Name "app_manager" -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    if (-not (Test-Path $TARGET_EXE_DIR)) { New-Item -ItemType Directory -Path $TARGET_EXE_DIR -Force | Out-Null }
    Copy-Item -Path "$BUILT_EXE_DIR\*" -Destination $TARGET_EXE_DIR -Recurse -Force
}

if (Test-Path $BUILT_WEB_DIR) {
    if (-not (Test-Path $TARGET_WEB_DIR)) { New-Item -ItemType Directory -Path $TARGET_WEB_DIR -Force | Out-Null }
    Copy-Item -Path "$BUILT_WEB_DIR\*" -Destination $TARGET_WEB_DIR -Recurse -Force

    # Generate interactive Start/Stop Web Server Batch Script inside Web Release folder
    $BAT_SCRIPT = @"
@echo off
title Android App Manager Web Server
color 0A

:MENU
cls
echo ==================================================
echo   ANDROID APP MANAGER - WEB SERVER MANAGER
echo ==================================================
echo.
echo  [1] Start Web Server and Open Browser (Port 8085)
echo  [2] Stop / Kill Web Server (Port 8085)
echo  [3] Exit
echo.
set /p choice="Select an option (1-3): "

if "%choice%"=="1" goto START_SERVER
if "%choice%"=="2" goto STOP_SERVER
if "%choice%"=="3" goto END

goto MENU

:START_SERVER
cls
echo ==================================================
echo   STARTING WEB SERVER...
echo ==================================================
echo.
echo  [+] Launching local HTTP server on http://localhost:8085
start "" "http://localhost:8085"
python -m http.server 8085
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo  [-] Python not found on PATH. Trying PowerShell HTTP Server...
    powershell -Command "Start-Process 'http://localhost:8085'; `$listener = New-Object System.Net.HttpListener; `$listener.Prefixes.Add('http://localhost:8085/'); `$listener.Start(); Write-Host 'Server running at http://localhost:8085...'; while (`$listener.IsListening) { `$context = `$listener.GetContext(); `$reqPath = `$context.Request.Url.AbsolutePath.TrimStart('/'); if (`$reqPath -eq '') { `$reqPath = 'index.html' }; `$file = Join-Path (Get-Location) `$reqPath; if (-not (Test-Path `$file)) { `$file = 'index.html' }; `$bytes = [System.IO.File]::ReadAllBytes(`$file); `$context.Response.ContentLength64 = `$bytes.Length; `$context.Response.OutputStream.Write(`$bytes, 0, `$bytes.Length); `$context.Response.Close() }"
)
pause
goto MENU

:STOP_SERVER
cls
echo ==================================================
echo   STOPPING WEB SERVER...
echo ==================================================
echo.
for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":8085" ^| findstr "LISTENING"') do (
    echo  [+] Killing process PID: %%a listening on port 8085...
    taskkill /F /PID %%a >nul 2>&1
)
echo.
echo  [+] Web Server Stopped successfully!
pause
goto MENU

:END
exit
"@
    Set-Content -Path "$TARGET_WEB_DIR\run_web_server.bat" -Value $BAT_SCRIPT -Force
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor Green
Write-Host "  [+] Android App Manager Build Complete!" -ForegroundColor Green
Write-Host "      Windows EXE: $TARGET_EXE_DIR\app_manager.exe" -ForegroundColor Yellow
Write-Host "      Web HTML5:   $TARGET_WEB_DIR\index.html" -ForegroundColor Yellow
Write-Host "      Web Manager: $TARGET_WEB_DIR\run_web_server.bat" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green
