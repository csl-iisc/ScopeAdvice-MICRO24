#!/bin/bash

# Run some basic setup [currently, it generates data for RD]
./setup.sh

# Run script for generating data for Figure 11
cd figure
./run.sh
cd ..

# Run script for getting results from Table 1 and Table 3
cd table-1-and-3
./run.sh
cd ..

# Run script for getting results from Table 2
cd table-2
./run.sh
cd ..
