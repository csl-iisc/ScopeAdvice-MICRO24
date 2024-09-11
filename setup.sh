#!/bin/bash

if [ -f ./data/red ]; then
    echo 'Data file for RD exists'
else
    # Generate data for red
    cd data
    ./gen-red > red
    cd ..
fi
