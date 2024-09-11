#!/bin/bash

# Ensure that the run file in the root directory is done before running this script

for dir in */
do
    echo $dir
    cd $dir
    ./eval.sh
    cd ..
done

python3 process-figure.py
