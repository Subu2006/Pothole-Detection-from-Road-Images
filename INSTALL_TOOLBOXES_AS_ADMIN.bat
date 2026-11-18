@echo off
:: Self-elevating batch file to copy MATLAB Toolboxes into Program Files
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Requesting Administrative Privileges to sync toolboxes into Program Files...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    set params = %*:"=""
    echo UAC.ShellExecute "cmd.exe", "/c ""%~s0"" %params%", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    echo =========================================================================
    echo   INSTALLING MATLAB TOOLBOXES INTO C:\Program Files\MATLAB\R2026b
    echo =========================================================================
    robocopy "C:\Users\subra\MATLAB_Toolboxes\R2026b" "C:\Program Files\MATLAB\R2026b" /E /XO /XN /XC /NP /R:1 /W:1
    echo.
    echo Toolboxes successfully synced into Program Files!
    echo Regenerating pathdef.m for Program Files MATLAB...
    "C:\Program Files\MATLAB\R2026b\bin\matlab.exe" -batch "restoredefaultpath; savepath;"
    echo.
    echo =========================================================================
    echo   Complete! Both MATLAB installations now have Image Processing and Stats!
    echo =========================================================================
    pause
