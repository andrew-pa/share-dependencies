@echo off
robocopy /MIR %1 %2 %3
IF %ERRORLEVEL% LSS 8 set ERRORLEVEL=0
