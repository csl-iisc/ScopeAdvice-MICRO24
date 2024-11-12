# Over-synchronization in GPU Programs
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.13743937.svg)](https://doi.org/10.5281/zenodo.13743937)


We provide the source code and the setup for ScopeAdvice, a tool to detect over-synchronization in GPU programs. ScopeAdvice instruments GPU programs to detect over-synchronization in them. It uses NVIDIA's NVBit [1], a GPU binary instrumenter, as the framework for instrumentation. 

This README provides a peek into the tool and a very high-level view of source code organization and steps to reproduce results from the paper.

For full details refer to our paper:
<pre>
<b>Over-synchronization in GPU Programs</b>
Ajay Nayak and Arkaprava Basu
<i>IEEE/ACM International Symposium on Microarchitecture (MICRO), 2024</i>
DOI: https://dl.acm.org/doi/10.1109/MICRO61859.2024.00064
</pre>

## Hardware and software requirements
ScopeAdvice is built on top of NVBit (version 1.5.3) and shares its requirements, listed below:
* SM compute capability: >= 3.5 && <= 8.6
* Host CPU: x86\_64, ppc64le, aarch64
* OS: Linux v 5.4.0-42-generic
* GCC version : >= 5.3.0 for x86\_64;
* CUDA version: >= 8.0 && <= 11.x
* CUDA driver version: <= 495.xx

Currently no embedded GPUs or ARMs host are supported.

## Behind the scenes: ScopeAdvice's setup, and source code 

### Pre-requisites
CUDA runtime and NVIDIA drivers are necessary for ScopeAdvice. Follow the steps from *[NVIDIA](https://docs.nvidia.com/cuda/cuda-installation-guide-linux/)* for a proper installation setup.


### Compilation

```bash
cd scope-advice
make -B
```

The compiled tool can be found at *scope-advice/scope-advice.so*. 

### Running ScopeAdvice
Once compiled, ScopeAdvice can be run on binaries containing NVIDIA GPU code by setting the LD_PRELOAD environment variable. For example, to run ScopeAdvice on an application binary called *app.exe* contained in the main repository folder, you would run the following command:
```bash
LD_PRELOAD=./scope-advice/scope-advice.so ./app.exe
```
Compiling the application binary with `-lineinfo` flag allows ScopeAdvice to output line numbers when applications have over-synchronization. Otherwise, SASS offsets are used.


### Source code
The source code for the ScopeAdvice is found in the *[scope-advice/](scope-advice/)* folder.
The major files are as follows:    
 - **[scope-advice.cu](scope-advice/scope-advice.cu)**: This contains the CPU-side code for the tool.  This includes allocating memory for metadata, the binary instrumentation process, and outputting caught cases of over-synchronization to the user.
- **[inject_funcs.cu](scope-advice/inject_funcs.cu)**: This contains the CUDA code run on the GPU after instrumentation. This updating GPU metadata, and sending trace to the CPU for analysis.

We provide patch files for enabling different levels of optimziations in *[scope-advice/patch](scope-advice/patch)* folder.

We provide a wrapper script in *[scope-advice/wrapper](scope-advice/wrapper)* that enables running ScopeAdvice to be run across multiple inputs. Checkout the README for further details and an example run of the script.

## Setting up docker container (advised)
To install docker on an Ubuntu machine
```bash
sudo apt install docker.io
```

To run experiments within the container, build the container as:

```bash
docker build . -t sa:v1
```

The docker container requires access to NVIDIA GPUs and NVIDIA driver. This is enabled by installing NVIDIA container toolkit. Follow the steps from *[NVIDIA](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)* to set it up. We recommend installing via APT.

Then launch the docker container in an interactive as:
```bash
docker container run -it --runtime=nvidia --gpus all sa:v1 bash
```

Next, run the experiments as mentioned in the commands below to reproduce results.

## Reproducing results of the paper
To reproduce the results given in the paper, we provide pre-compiled application binaries. Full details are given in the README inside the folders corresponding to the results in the paper.
- **[table-1-and-3/](table-1-and-3/)** folder reproduces the results of Tables 1 and 3 from the paper.
- **[figure/](figure/)** folder reproduces the results of Figure 11 from the paper.
- **[table-2/](table-2/)** folder reproduces the results of Table 2 from the paper.

A single script is provided to generate all the key results from the paper. The command can be run as follows:
```bash
./run.sh
```
Alternatively, steps inside individual folders can be followed to generate corresponding results.

## References
**[1]** NVBit [*[Paper](https://github.com/NVlabs/NVBit/releases/download/v1.0/MICRO_19_NVBit.pdf)*],[*[Repository](https://github.com/NVlabs/NVBit)*]
