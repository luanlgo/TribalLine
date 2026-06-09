@echo off
chcp 65001 >nul
title TribalLine — Publicar Release

:: Le versao atual
set /p CURRENT=<"%~dp0..\version.txt"
echo Versao atual: %CURRENT%

:: Incrementa o patch (ex: 1.0.0 -> 1.0.1)
for /f "tokens=1,2,3 delims=." %%a in ("%CURRENT%") do (
    set MAJOR=%%a
    set MINOR=%%b
    set /a PATCH=%%c+1
)
set NEW_VERSION=%MAJOR%.%MINOR%.%PATCH%

echo Nova versao : %NEW_VERSION%
echo.
set /p CONFIRM=Publicar v%NEW_VERSION% no GitHub? (S/N):
if /i not "%CONFIRM%"=="S" (
    echo Cancelado.
    pause
    exit /b 0
)

echo.
echo ==> Rodando build_release.ps1 -Version %NEW_VERSION% -Publish ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_release.ps1" -Version %NEW_VERSION% -Publish
if %errorlevel% neq 0 (
    echo.
    echo ERRO no build/publish. Versao nao foi incrementada.
    pause
    exit /b 1
)

echo.
echo ==> Release v%NEW_VERSION% publicada com sucesso!
pause
