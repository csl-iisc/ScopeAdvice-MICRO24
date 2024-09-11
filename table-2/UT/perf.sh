#!/bin/bash

iterations=50
temp='temp.out'
rm -f *.out

# First run the program to generate optimized data
for (( i = 0; i < iterations; i++))
do
    ./opt 6 6 6 >> $temp
done
# Put the data in opt.out
grep -a ElapsedTime $temp | awk '{ print $2 }' >> opt.out

rm $temp
# Run the program to generate original data
for (( i = 0; i < iterations; i++))
do
    ./og 6 6 6 >> $temp
done
# Put the data in og.out
grep -a ElapsedTime $temp | awk '{ print $2 }' >> og.out

rm $temp
# Generate nsight data for optimized run
for (( i = 0; i < iterations; i++))
do
    nv-nsight-cu-cli --target-processes all --metrics smsp__average_warps_issue_stalled_membar_per_issue_active.ratio ./opt 6 6 6 >> $temp
done
# Put the data in opt-nsight.out
grep 'smsp__average_warps_issue_stalled_membar_per_issue_active' $temp | awk '{ print $3 }' >> opt-nsight.out

rm $temp
# Generate nsight data for optimized run
for (( i = 0; i < iterations; i++))
do
    nv-nsight-cu-cli --target-processes all --metrics smsp__average_warps_issue_stalled_membar_per_issue_active.ratio ./og 6 6 6 >> $temp
done
# Put the data in og-nsight.out
grep 'smsp__average_warps_issue_stalled_membar_per_issue_active' $temp | awk '{ print $3 }' >> og-nsight.out
