@echo off
title ADB Toolkit Web Server
color 0A

:MENU
cls
echo ==================================================
echo       ADB TOOLKIT - WEB SERVER MANAGER
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
    powershell -Command "Start-Process 'http://localhost:8085'; $listener = New-Object System.Net.HttpListener; $listener.Prefixes.Add('http://localhost:8085/'); $listener.Start(); Write-Host 'Server running at http://localhost:8085...'; while ($listener.IsListening) { $context = $listener.GetContext(); $reqPath = $context.Request.Url.AbsolutePath.TrimStart('/'); if ($reqPath -eq '') { $reqPath = 'index.html' }; $file = Join-Path (Get-Location) $reqPath; if (-not (Test-Path $file)) { $file = 'index.html' }; $bytes = [System.IO.File]::ReadAllBytes($file); $context.Response.ContentLength64 = $bytes.Length; $context.Response.OutputStream.Write($bytes, 0, $bytes.Length); $context.Response.Close() }"
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
