#!/bin/bash

tool_path=../../scope-advice
current=`pwd`
bench=og
iterations=20
# create output folder
mkdir -p eval

run_tool() {
    mkdir -p eval/$2
    file='run.out'
    rm -f eval/$2/$file

    for (( i = 0; i < iterations; i++))
    do
        if [ $1 -eq 0 ]; then
            # no instrumentation
            ./$bench  >> eval/$2/$file
        elif [ $1 -eq 1 ]; then
            # instrumentation
            LD_PRELOAD=$tool_path/scope-advice.so ./$bench >> eval/$2/$file
        fi
        echo '------- END '$i' ITERATION ----------' >> eval/$2/$file
    done
}

run_tool 0 'baseline'

cd $tool_path
git checkout helper.h common.h *.cu
git apply patch/naive.patch
make -B
cd $current
run_tool 1 '1t1b'

cd $tool_path
git checkout helper.h common.h *.cu
git apply patch/para.patch
make -B
cd $current
run_tool 1 '12tnb'

cd $tool_path
git checkout helper.h common.h *.cu
git apply patch/para+sampling.patch
make -B
cd $current
run_tool 1 'sampling'

cd $tool_path
git checkout helper.h common.h *.cu
git apply patch/scope-advice.patch
make -B
cd $current
run_tool 1 'scopeadvice'

cd $tool_path
git checkout helper.h common.h *.cu
git apply patch/nvbit.patch
make -B
cd $current
run_tool 1 'blank'

./get_time.sh
