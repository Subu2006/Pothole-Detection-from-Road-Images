@echo off
title ROADVISION AI: Pothole Detection Suite (ECE443 CA2)
cd /d "%~dp0"
echo Starting ROADVISION AI Interactive Engineering Dashboard...
start "" "C:\Users\subra\MATLAB_Toolboxes\R2026b\bin\matlab.exe" -r "addpath(pwd); addpath(fullfile(pwd, 'src')); pothole_gui;"
