## Workloads (GPU benchmark suites, libraries and applications)
The following table lists the workloads used in the evaluation of the submission version of the paper. This repository contains pre-compiled binaries from the open-source benchmark suites listed below. If one wishes, she/he can compile the workloads from source too.

| Suite        | Code     | Description |
| ----------   | -------- | ----------- |
| ScoR         | [*[Github](https://github.com/csl-iisc/ScoR)*] | Racey applications using scopes. |
| cuML         | [*[Github](https://github.com/rapidsai/cuml)*] | Suite of libraries that implement machine learning algorithms and mathematical primitives
| Kilo-TM      | [*[Github](https://github.com/upenn-acg/barracuda/tree/master/benchmarks/gpu-tm)*]    | GPU applications with fine-grained communication between threads. | 
| Cudpp        | [*[Github](https://github.com/cudpp/cudpp)*] | CUDA Data parallel primitives library   |
| CUDA Samples | [*[Github](https://github.com/NVIDIA/cuda-samples/)*] | Samples for CUDA Developers which demonstrates features in CUDA Toolkit |
| Predatar     | [*[Paper](https://arxiv.org/abs/2111.12478)*] | Predictive race detection for GPU |
| Gpufilter    | [*[Github](https://github.com/andmax/gpufilter)*] | GPU Recursive Filtering |

## Modifying applications to eliminate over-synchronization
To modify the applications that have over-synchronization, the programmer can follow 'db.json' file present in table-1-and-3/ABC where ABC is the application name (e.g., CU). An example can be found in CU folder (*[../table-1-and-3/CU/db.json](../table-1-and-3/CU/db.json)*). Note that the db.json file is present only in applications which demonstrate over-synchronization. For this step, programmer will have to manually modify the corresponding source files (3 lines on average). After modification, the code will require recompilation for the changes to take effect.


Link to source files will be added soon.
