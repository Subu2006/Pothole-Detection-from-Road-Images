@echo off
title ECE443 CA2: Pothole Detection Automated Benchmark
cd /d "%~dp0"
echo =========================================================================
echo   Running Full ECE443 CA2 Automated Benchmark Pipeline...
echo =========================================================================
"C:\Users\subra\MATLAB_Toolboxes\R2026b\bin\matlab.exe" -batch "addpath(pwd); addpath(fullfile(pwd, 'src')); main_run;"
echo.
echo Benchmark Complete! Results saved to 'results/' and 'models/'.
pause
