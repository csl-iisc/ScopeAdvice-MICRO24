# ScopeAdvice: Finding Over-synchronization and Memory Overheads

We provide the application binaries used in ScopeAdvice for generating results in Table 1 and Table 3.

## Evaluation and test environment
We evaluated ScopeAdvice on the below hardware and software specification:
* SM compute capability: sm_86 (NVIDIA RTX 3090)
* Host CPU: AMD Ryzen 5950x
* OS: Ubuntu 20.04 with linux v 5.4.0-42-generic
* GCC version : 9.4.0
* CUDA version: cuda_11.2.r11.2
* CUDA driver version: 470.256.02

## Steps to setup and reproduce results
The following are the steps required to reproduce the results. The commands should be run in this folder.

### Reproducing results (Tables 1 and 3)
The following command runs compiles ScopeAdvice, runs every application against ScopeAdvice and generates result contained in Table 1 and Table 3. Each subfolder in this folder is dedicated to each application used in the evaluation.

Run the following command in the current folder:
```bash
./run.sh
```

The outputs of ScopeAdvice are parsed to count the number of unique cases caught. The scripts responsible for parsing can be found in *[table-1-and-3](table-1-and-3/)*, called *process-table-1-and-3.py*. 

Raw outputs for ScopeAdvice will be contained in *table-1-and-3/ABC/fence.out* and *table-1-and-3/ABC/mem.out* where ABC is the application name (e.g., CU for cuML). The file *fence.out* will report case of over-synchronization and the file *mem.out* will report the memory overhead.

Final parsed results will be outputted in the terminal and are also contained at *table-1-and-3/table-1-result.csv* and *table-1-and-3/table-3-result.csv* in comma-separated format.
