#!/bin/bash

# Build scope-advice with the correct configuration
cd ../scope-advice
git checkout .
git apply patch/scope-advice.patch
make -B
cd ../table-1-and-3

# Ensure that the run file in root directory is done before running this script
for dir in */
do
    echo $dir
    cd $dir
    ./run.sh
    cd ..
    ./trim.sh $dir
done

python3 process-table-1-and-3.py
