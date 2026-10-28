#!/bin/bash

#cd testcode
#make clean
#cd ..

FILES="altera_mf_ver/ modelsim.ini transcript work/ result.wlf test.lst *.ver sram.mif vsim.wlf"

# movetotrash where available, otherwise delete, so that a stale work
# library from an earlier build is never simulated
if command -v movetotrash >/dev/null 2>&1; then
    movetotrash $FILES
else
    rm -rf $FILES
fi
