import io
import os
import subprocess
import yaml

# EDITME: Change this path based on requirements
TOOL_PATH='../scope-advice.so'
KIND_DELIMITER='|'
VALUE_DELIMITER=':'

# read a yaml test configuration file
conf_file = open('conf.yaml', 'r')
config = yaml.safe_load(conf_file)
conf_file.close()

# Get the command
cmd = config['cmd']

counts = int(config['tests'])
# Use this to read inputs from inputs file. Each line is an input
tests = []
input_file = open(config['input_file'], 'r')
for line in input_file.readlines():
    args = line.rstrip()
    tests.append(args.split(" "))
input_file.close()

kernels = config['kernels']

# Extend the environment of current user with LD_PRELOAD to run the tool
# For safety, we use CUDA_INJECTION64_PATH. An issue on NvBIT github suggested this
wrapper_env = os.environ.copy()
wrapper_env['CUDA_INJECTION64_PATH'] = TOOL_PATH

# Do this for each kernel
for kernel in kernels:
    wrapper_env['KERNELID'] = kernel
    # Output from wrapper script for the kernel!
    comment = {}
    epochs_over_inputs = set()

    # For each kernel, iterate over each input
    for i in range(0, counts):
        args = [cmd]
        f = subprocess.DEVNULL

        # Input independent arguments
        if config['args']:
            args.append(config['args'])

        # Request a prolog.sh script from devs which takes input as the argument and sets up the program.
        if config['prolog']:
            # Input is provided to the prolog script
            cmd = ["bash", "./prolog.sh", tests[i]]
            prolog = subprocess.check_call(cmd, stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
        # line is a file that needs to be redirected, open it
        elif config['redirect']:
            f = open(tests[i], "r")
        # no prolog, build args based on the for loop.
        else:
            args = args + tests[i]

        # Run the command!
        proc = subprocess.Popen(args, stdout=subprocess.PIPE, stdin=f, env=wrapper_env)

        # get the output from the program!
        epochs = set()
        for line in io.TextIOWrapper(proc.stdout, encoding="utf-8"):
            # The list here is populated based on output from ScopeAdvice NVBit tool
            # Any changes there must reflect here as well!
            if all(x in line for x in ['Fence@', 'Epoch', 'Info', 'Type']):
                # Process the line and get the epoch!
                splits = line.split(KIND_DELIMITER)
                epoch = splits[1]
                value = epoch.split(VALUE_DELIMITER)[1].strip()
                epochs.add(value)
                # Need the comment for later output
                comment[value] = line.rstrip()
        # epochs is from this input, get intersection!
        if epochs_over_inputs:
            if (len(epochs_over_inputs - epochs)):
                print(f"Removing {epochs_over_inputs - epochs} fence IDs from over-synchronized list")
            epochs_over_inputs = epochs.intersection(epochs_over_inputs)
        else:
            epochs_over_inputs = epochs

    ''' Now we have an intersection of all inputs. Take epochs from epochs_over_inputs
    and advice from comment to get the output!
    '''
    print('Suggestions after iterating over inputs for ' + kernel + ' kernel')
    for epoch in epochs_over_inputs:
        print(comment[epoch])

