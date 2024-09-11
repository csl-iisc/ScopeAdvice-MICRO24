# ScopeAdvice: Runtime overheads

We provide the application binaries used in ScopeAdvice for generating results in Figure 11.

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

### Reproducing results (data for Figure 11)
The following command runs every application against ScopeAdvice  with different optimizations enabled at each step. The experiment generates result contained in Figure 11. Each subfolder in this folder is dedicated to each application used in the evaluation.

Run the following command in the current folder:
```bash
./run.sh
```

The outputs of this experiment are parsed to measure the runtime overheads of ScopeAdvice. The scripts responsible for parsing can be found in *[figure](figure/)*, called *process-figure.py*. 

Raw outputs for this experiment will be contained in *figure/ABC/eval/XYZ.out*, where ABC is the application name (e.g., CU for cuML), and *XYZ.out* will be the execution time when the application is run along with different optimization levels of ScopeAdvice. XYZ could be 1t1b (Naive), 12tnb (Para), sampling (Para+Sampling) and scopeadvice (all optimizations - ScopeAdvice).

Final parsed results will be outputted in the terminal and are also contained at *figure/result.csv* in comma-separated format.
