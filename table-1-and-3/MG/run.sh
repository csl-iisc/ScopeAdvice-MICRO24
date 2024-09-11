#!/bin/bash

LD_PRELOAD=../../scope-advice/scope-advice.so KERNELID=mergeMulti_higher ./og -mergesort -iterations=1 > run.out
