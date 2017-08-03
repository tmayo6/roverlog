@echo off
mode %1 baud=%2 parity=n data=8 > nul
echo %3 %4 %5 %6 %7 %8 %9 > %1
