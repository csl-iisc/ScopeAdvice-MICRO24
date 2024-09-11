# This script should be run after generating the data

apps=['CU', 'ST', 'CP', 'MM', 'UT', 'UT-A', 'SC', 'RD', 'HS', 'PL', 'MG']

def mean(data):
    return round(float(sum(data)/len(data)), 3)

def get_data(file_path):
    f = open(file_path, 'r')
    data = []
    for line in f.readlines():
        data.append(float(line.rstrip()))
    return mean(data)

def normalize(base, val):
    return round(float(val/base), 3)

data = {}
for app in apps:
    # Each app will have an eval folder, with baseline, blank (nvbit) and 1 folder for each bar
    # Extract all the data
    baseline = get_data('./' + app + '/eval/baseline.out')
    nvbit = get_data('./' + app + '/eval/blank.out')
    onet1b = get_data('./' + app + '/eval/1t1b.out')
    twelvetnb = get_data('./' + app + '/eval/12tnb.out')
    samp = get_data('./' + app + '/eval/sampling.out')
    sa = get_data('./' + app + '/eval/scopeadvice.out')

    # Now, we have times for each application, normalize using baseline
    nvbit = normalize(baseline, nvbit)
    onet1b = normalize(baseline, onet1b)
    twelvetnb = normalize(baseline, twelvetnb)
    samp = normalize(baseline, samp)
    sa = normalize(baseline, sa)

    # Populate the app_data
    app_data = {'naive': onet1b, 'para': twelvetnb, 'para+sampling': samp, 'scopeadvice': sa}
    data[app] = app_data

    # For graph, each bar has two partitions, nvbit and the rest. Create two portions for each version
    onet1b_data = [nvbit, onet1b - nvbit]
    twelvetnb_data = [nvbit, twelvetnb - nvbit]
    samp_data = [nvbit, samp - nvbit]
    sa_data = [nvbit, sa - nvbit]

    # TODO: Check how to create graph from this, for now print

output_lines = []
# For each app, list content in CSV format
output_lines.append("Application,Naive,Para,Para+Sampling,ScopeAdvice\n")
for app in data.keys():
    output_lines.append(f"{app},{data[app]['naive']},{data[app]['para']},{data[app]['para+sampling']},{data[app]['scopeadvice']}\n")

f = open('result.csv', 'w')
for line in output_lines:
    # write to terminal
    print(line, end="")
    # write to results file
    f.write(line)
f.close()
