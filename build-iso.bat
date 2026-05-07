@echo off
REM ============================================================
REM Lanceur convivial du script PowerShell de build ISO
REM Double-clique sur ce fichier pour démarrer
REM ============================================================

cd /d "%~dp0"

echo.
echo ============================================================
echo   Ubuntu Terminal Applicatif - Build ISO
echo ============================================================
echo.

REM Lance PowerShell en bypassant la policy d'execution
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-iso.ps1"

echo.
echo Appuie sur une touche pour fermer cette fenetre...
pause >nul
