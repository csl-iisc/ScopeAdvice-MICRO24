#!/bin/bash

temp='temp.out'
rm -f *.out

# First run the program to generate optimized data
./opt -compress -iterations=1 > $temp
# Put the data in opt.out
grep -a ElapsedTime $temp | awk '{ print $2 }' > opt.out

# Run the program to generate original data
./og -compress -iterations=1 > $temp
# Put the data in og.out
grep -a ElapsedTime $temp | awk '{ print $2 }' > og.out

# Generate nsight data for optimized run
nv-nsight-cu-cli --target-processes all --kernel-id "::huffman_build_tree_kernel:" --metrics smsp__average_warps_issue_stalled_membar_per_issue_active.ratio ./opt -compress -iterations=1 > $temp
# Put the data in opt-nsight.out
grep 'smsp__average_warps_issue_stalled_membar_per_issue_active' $temp | awk '{ print $3 }' > opt-nsight.out

# Generate nsight data for optimized run
nv-nsight-cu-cli --target-processes all --kernel-id "::huffman_build_tree_kernel:" --metrics smsp__average_warps_issue_stalled_membar_per_issue_active.ratio ./og -compress -iterations=1 > $temp
# Put the data in og-nsight.out
grep 'smsp__average_warps_issue_stalled_membar_per_issue_active' $temp | awk '{ print $3 }' > og-nsight.out

rm $temp
