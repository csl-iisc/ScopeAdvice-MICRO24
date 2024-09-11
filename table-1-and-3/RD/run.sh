#!/bin/bash

# Ensure that file exists
if [ ! -f ../../data/red ];
then
    cd ../../data
    ./gen-red
    cd ../table-1-and-3/RD
fi

LD_PRELOAD=../../scope-advice/scope-advice.so ./og < ../../data/red > run.out
