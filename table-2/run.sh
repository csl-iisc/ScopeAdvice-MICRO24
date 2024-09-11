#!/bin/bash

for dir in */
do
    echo $dir
    cd $dir
    ./perf.sh
    cd ..
done

python3 process-table-2.py
