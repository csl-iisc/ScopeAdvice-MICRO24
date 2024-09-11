#!/bin/bash

LD_PRELOAD=../../scope-advice/scope-advice.so KERNELID=blockWiseStringSort ./og -stringsort -iterations=1 > run.out
