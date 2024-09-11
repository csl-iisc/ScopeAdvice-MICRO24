#!/bin/bash

LD_PRELOAD=../../scope-advice/scope-advice.so KERNELID=huffman_build_tree_kernel ./og -compress -iterations=1 > run.out
