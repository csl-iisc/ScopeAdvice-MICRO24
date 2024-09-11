# ScopeAdvice Wrapper

We provide wrapper scripts that is capable of running ScopeAdvice with applications that have
multiple kernels in them, or to run the same kernel with different inputs.

The wrapper requires a yaml file with simple information that can be easily created automatically.
For e.g., the number of kernels, name of kernels can be fetched using a source analysis or using NVBit.

The arguments in yaml file are as follows:
- **cmd**       : The command to run the application (e.g., the program executable)
- **args**      : Some programs require command line arguments which are input independent. Use this for that purpose (Optional)
- **tests**     : Number of tests the script should run (At least 1)
- **input_file**: This requires a simple file with arguments in each line for each test
            (For example, 3 tests will have a input file with 3 lines each with arguments)
            (At least 1, can be a file with dummy one line)
- **redirect**  : This is a boolean flag that says if the input to 'cmd' is provided using redirection (<) or as space separated command line arguments.
- **prolog**    : The developer can provide a 'prolog.sh' (fixed file name) file to pre-process the program that is being tested. For example, apply a patch and compile the program again (Optional)
- **kernels**   : This is a list of kernels present in the program. Note that this is case-sensitive and care must be taken to avoid spelling errors. At least 1 kernel must be provided as an argument.

We provide a sample conf.yaml example which was created for cuML program available on GitHub. We have updated the conf.yaml file accordingly.

Usage:
```bash
python3 wrapper.py
```

Output:
A suggestion list for each kernel. 
It will print which all fence IDs were eliminated over time.
