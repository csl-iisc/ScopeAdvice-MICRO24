#!/bin/bash
OUT="run.out"
FEN="fence.out"
MEM="mem.out"

# This script expects a folder which is being processed

# Separate fence data
cat $1/$OUT | grep 'Fence@' > $1/$FEN

# and memory metadata
tail -n 5 $1/$OUT > $1/$MEM
