@echo off
title Push Project to GitHub - Subu2006/Pothole-Detection-from-Road-Images
cd /d "%~dp0"
echo =========================================================================
echo   ROADVISION AI: PUSH TO GITHUB
echo   Target: https://github.com/Subu2006/Pothole-Detection-from-Road-Images
echo =========================================================================
echo.
set "PATH=C:\Users\subra\AppData\Local\Programs\Git\cmd;C:\Users\subra\AppData\Local\Programs\Git\ucrt64\bin;%PATH%"

echo Checking repository status...
git status -s
echo.

echo Pushing all commits and project files to GitHub (main branch)...
echo (A browser window or sign-in dialog may appear to authorize your GitHub account)
echo.

git push -u origin main

if %errorlevel% equ 0 (
    echo.
    echo =========================================================================
    echo   SUCCESS! All project files are now live on GitHub!
    echo   Repository URL: https://github.com/Subu2006/Pothole-Detection-from-Road-Images
    echo =========================================================================
) else (
    echo.
    echo =========================================================================
    echo   Notice: Authentication needed.
    echo.
    echo   How to complete:
    echo   1. Choose "Sign in with your browser" in the prompt window, OR
    echo   2. Use a GitHub Personal Access Token (PAT) with 'repo' scope from:
    echo      https://github.com/settings/tokens
    echo =========================================================================
)
echo.
pause
