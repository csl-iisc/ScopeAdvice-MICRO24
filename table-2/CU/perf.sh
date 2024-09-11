#!/bin/bash

temp='temp.out'
rm -f *.out

# First run the program to generate optimized data
./opt > $temp
# Put the data in opt.out
grep -a ElapsedTime $temp | awk '{ print $2 }' > opt.out

# Run the program to generate original data
./og > $temp
# Put the data in og.out
grep -a ElapsedTime $temp | awk '{ print $2 }' > og.out

# Generate nsight data for optimized run
nv-nsight-cu-cli --target-processes all --metrics smsp__average_warps_issue_stalled_membar_per_issue_active.ratio ./opt 16384 > $temp
# Put the data in opt-nsight.out
grep 'smsp__average_warps_issue_stalled_membar_per_issue_active' $temp | awk '{ print $3 }' > opt-nsight.out

# Generate nsight data for original run
nv-nsight-cu-cli --target-processes all --metrics smsp__average_warps_issue_stalled_membar_per_issue_active.ratio ./og 16384 > $temp
# Put the data in og-nsight.out
grep 'smsp__average_warps_issue_stalled_membar_per_issue_active' $temp | awk '{ print $3 }' > og-nsight.out
