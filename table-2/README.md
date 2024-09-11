# ScopeAdvice: Performance Improvement After Eliminating Over-synchronization

We provide the application binaries used in ScopeAdvice for generating results in Table 2.

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

### Reproducing results (Table 2)
The following command runs two variants of applications to demonstrate performance improvement. It runs (1) the original program, i.e., with over-synchronization, and (2) the modified program, i.e., without over-synchronization. Each subfolder in this folder is dedicated to each application used in the evaluation.

Run the following command in the current folder:
```bash
./run.sh
```

The outputs of this experiment are parsed to measure the performance improvement, and also provide the peformance counter values (stalls due to fence operations). The scripts responsible for parsing can be found in *[table-2](table-2/)*, called *process-table-2.py*. 

Raw outputs for this experiment will be contained in *table-2/ABC/og.out*, *table-2/ABC/opt.out*, *table-2/ABC/og-nsight.out* and *table-2/ABC/opt-nsight.out* where ABC is the application name (e.g., CU for cuML). The file *og.out* will contain the execution time of application with over-synchronization, and *opt.out* will contain the execution time of the application after eliminating over-synchronization. The files *og-nsight.out* and *opt-nsight.out* have the stalls the application faced due to fence instructions with and without over-synchronization respectively.

Final parsed results will be outputted in the terminal and are also contained at *table-2/result.csv* in comma-separated format.
