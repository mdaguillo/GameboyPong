@echo off
if exist pong.gb del pong.gb
if exist pong.map del pong.map
if exist pong.obj del pong.obj
if exist pong.sym del pong.sym

:begin
echo assembling...
rgbasm -opong.obj pong.asm
if errorlevel 1 goto end
echo linking...
rgblink -mpong.map -npong.sym -opong.gb pong.obj
if errorlevel 1 goto end
echo fixing...
rgbfix -p0 -v pong.gb

:end
pause
rem del *.obj