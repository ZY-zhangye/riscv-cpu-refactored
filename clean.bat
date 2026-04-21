@echo off
echo Cleaning QuestaSim temporary files...
rd /s /q work
del /q transcript
del /q vsim.wlf
del /q *.vcd
del /q *.log
del /q results\*.txt
echo Done.