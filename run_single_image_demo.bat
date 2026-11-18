@echo off
title ECE443 CA2: Single Image Pothole Inspector
cd /d "%~dp0"
echo Launching Interactive Single-Image Demonstration...
start "" "C:\Users\subra\MATLAB_Toolboxes\R2026b\bin\matlab.exe" -r "addpath(pwd); addpath(fullfile(pwd, 'src')); demo_single_image;"
