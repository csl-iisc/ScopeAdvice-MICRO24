# This script should be run after generating the data

apps=['CU', 'ST', 'CP', 'MM', 'UT', 'UT-A', 'SC', 'RD', 'HS', 'PL', 'MG']
data = {}
paper_data = {}


def mean(data):
    return round(float(sum(data)/len(data)), 3)


def get_data(file_path):
    f = open(file_path, 'r')
    data = []
    for line in f.readlines():
        data.append(float(line.rstrip()))
    return mean(data)


def get_float(val):
    return float(val.strip())


def set_paper_data():
    # Get from run in the paper
    f = open('paper_data', 'r')
    for line in f.readlines():
        # CSV, each line is a float, first app
        vals = line.rstrip().split(",")
        app = vals[0].strip()
        paper_app_data = {'baseline': get_float(vals[1]), 'naive': get_float(vals[2]), 'para': get_float(vals[3]), 'para+sampling': get_float(vals[4]), 'scopeadvice': get_float(vals[5])}
        paper_data[app] = paper_app_data


# Get data used in the paper
set_paper_data()

# Get and process the data generated from the script
for app in apps:
    # Each app will have an eval folder, with baseline, blank (nvbit) and 1 folder for each bar
    # Extract all the data
    baseline = get_data('./' + app + '/eval/baseline.out')
    nvbit = get_data('./' + app + '/eval/blank.out')
    onet1b = get_data('./' + app + '/eval/1t1b.out')
    twelvetnb = get_data('./' + app + '/eval/12tnb.out')
    samp = get_data('./' + app + '/eval/sampling.out')
    sa = get_data('./' + app + '/eval/scopeadvice.out')

    app_data = {'baseline': baseline, 'naive': onet1b, 'para': twelvetnb, 'para+sampling': samp, 'scopeadvice': sa}
    data[app] = app_data


# For each app --- do comparison
max_err = 0
margin = 10 # %
for app in apps:
    for key in data[app].keys():
        paper_val = paper_data[app][key]
        expt_val = data[app][key]
        # expt_val should not be more than 10% of paper_val
        err = round((expt_val - paper_val) / paper_val, 3) * 100
        if err > margin:
            print(f"{app}:{key} beyond {margin}% margin ({err}%)")
        max_err = max(err, max_err)

# print(f"Max error comparing to paper results: {max_err} %")

