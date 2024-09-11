apps = ['CU', 'ST', 'CP', 'MM', 'UT', 'UT-A', 'SC']

def get_mean(data):
    return round(float(sum(data)/len(data)), 3)

def get_data(file_name):
    data_file = open(file_name, 'r')
    data = []
    for line in data_file.readlines():
        data.append(float(line.rstrip()))

    return get_mean(data)

table = {}
for app in apps:
    # each app has a file for optimized and original runtimes. Fetch the data
    opt = get_data('./' + app + '/opt.out')
    og = get_data('./' + app + '/og.out')

    table[app] = {}
    table[app]['perf_improv'] = round(float((og - opt)/og) * 100, 2)
    table[app]['og_nsight_cycles'] = get_data('./' + app + '/og-nsight.out')
    table[app]['opt_nsight_cycles'] = get_data('./' + app + '/opt-nsight.out')

output_lines = []
# For each app, list content in CSV format
output_lines.append("Application,PerformanceImprovement(%),Stalls(Original),Stalls(Modified)\n")
for app in table.keys():
    output_lines.append(f"{app},{table[app]['perf_improv']},{table[app]['og_nsight_cycles']},{table[app]['opt_nsight_cycles']}\n")

f = open('result.csv', 'w')
for line in output_lines:
    # write to terminal
    print(line, end="")
    # write to results file
    f.write(line)
f.close()
