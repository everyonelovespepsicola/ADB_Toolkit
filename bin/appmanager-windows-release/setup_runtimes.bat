@echo off
title Installing Windows Sandbox Runtime Dependencies
color 0A
echo ==================================================
echo   INSTALLING VISUAL C++ RUNTIMES IN SANDBOX
echo ==================================================
echo.
echo  [+] Downloading Microsoft Visual C++ 2015-2022 Redistributable (x64)...
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile '%TEMP%\vc_redist.x64.exe'; Start-Process '%TEMP%\vc_redist.x64.exe' -ArgumentList '/q /norestart' -Wait"
echo  [+] Runtimes successfully installed!
echo  [+] Opening App Manager Release Folder...
explorer.exe "C:\Users\WDAGUtilityAccount\Desktop\appmanager-windows-release"
