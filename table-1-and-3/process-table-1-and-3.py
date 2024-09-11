# This script is called after the tool is run. It is for measuring the tool's effectiveness
# and measure memory overheads
import json

# DELIMITERS for formatting tool advice
KIND_DELIMITER='|'
VAL_DELIMITER=':'

# DELIMITERS for formatting tool memory overheads
MEM_DELIMITER=' '

# the folder name for the apps to be processed
apps_tab_1=['CU', 'ST', 'CP', 'MM', 'GE', 'UT', 'UT-A', 'SC', 'RD', 'HS', 'PL', 'MG']
print_debug_info=False

# The below structure is needed as NVBIt has an error and does not provide line number in the output file
# for all programs. This structure ensures that we maintain unique counts (for Table 1)
# Note: tracking NVBIT bug in github: https://github.com/NVlabs/NVBit/issues/70
rep={
    # there are multiple appearances due to function inlining (in all the cases here)
    # (ST): first is for bin_search device function and the second is lin_search device function
    'ST':   [{'set': set([1,2,3,4,5,6,7,8,9]), 'count': 0}, {'set': set([12,13,14,15,16,17,18]), 'count': 0}],
    'UT':   [{'set': set([0,4]), 'count': 0}],
    'UT-A': [{'set': set([0,4]), 'count': 0}, {'set': set([1,5]), 'count': 0}]
}


# The below structure identifies the true count of over-synchronization in each application
# This count corresponds to the 'Actual' column in Table 1
# Note: This count must match with the one found by ScopeAdvice
true_count={
    'CU': '3', 'ST': '10', 'CP': '2', 'MM': '3', 'GE': '-', 'UT': '2', 'UT-A': '2', 'SC': '2'
}


""" This returns the type string that is shown in Table 1 for each application
"""
def get_type_from_variants(var_dict):
    types = []
    if var_dict['Variant 1'] != 0:
        types.append("1")
    if var_dict['Variant 2'] != 0:
        types.append("2")
    if var_dict['Variant 3'] != 0:
        types.append("3")
    type_str = None
    if types:
        type_str = "Variant " + ",".join(types)
    else:
        type_str = "-"
    return type_str


""" Returns the total count of over-synchronizations identified by ScopeAdvice
"""
def get_var_count(var_dict):
    var = 0
    var += var_dict['Variant 1']
    var += var_dict['Variant 2']
    var += var_dict['Variant 3']
    return var


""" Returns the true count of over-synchronization cases in each application
"""
def get_true_count(app_name):
    return true_count.get(app_name, 0)


print('')
print("Output for Table-1. Please check the app-name, reported, and the variants for verification.")
print('')
osync_table = {}
for app in apps_tab_1:
    # Fence output file, for measuring effectiveness
    fence_file = './' + app + '/fence.out'
    db_file = './' + app + '/db.json'

    fence = open(fence_file, 'r')
    info = {}
    try:
        db = open(db_file, 'r')
        info = json.load(db)
    except Exception:
        # No db file present for this --- process the output without it
        pass

    variants = {'Variant 1': 0, 'Variant 2': 0, 'Variant 3': 0}
    debug_info = []
    for line in fence.readlines():
        if all(x in line for x in ['Fence@', 'Epoch', 'Info', 'Type']):
            # There is a splitter first using '|'
            splits = line.rstrip().split(KIND_DELIMITER)
            epoch = int(splits[1].split(VAL_DELIMITER)[1].strip())
            # Some epochs are multiple tool output entries, but same program lines. Separate those
            repetition = False
            if app in rep:
                for i in range(len(rep[app])):
                    func = rep[app][i]
                    if epoch in func['set']:
                        if func['count'] == 1:
                            repetition = True
                        rep[app][i]['count'] = 1
            debug_info.append(info[str(epoch)])

            # Increment the variant count only when the output is not unique
            if not repetition:
                variant = splits[3].split(VAL_DELIMITER)[1].strip()
                variants[variant] = variants[variant] + 1

    fence.close()
    db.close()
    osync_table[app] = variants

output_lines = []
# For each app, list content in CSV format
output_lines.append("Application,Actual,Reported,Type\n")
for app in osync_table.keys():
    output_lines.append(f"{app},{get_true_count(app)},{get_var_count(osync_table[app])},{get_type_from_variants(osync_table[app])}\n")

f = open('table-1-result.csv', 'w')
for line in output_lines:
    # write to terminal
    print(line, end="")
    # write to results file
    f.write(line)
f.close()

print('')

apps_tab_3=['CU', 'ST', 'CP', 'MM', 'UT', 'UT-A', 'SC', 'RD', 'HS', 'PL', 'MG']

print("----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----")
print('')
print("Output for Table-3. Please check the app name, corresponding overheads. Note that due to float")
print("calculations Metadata and Trace Filter columns will have a slight margin of error.")
print('')
mem_table = {}
for app in apps_tab_3:
    # Memory overhead file for measuring memory overhead
    memory_file = './' + app + '/mem.out'
    memory = open(memory_file, 'r')
    mem_over = {'Metadata': 0, 'Fence': 0, 'Sampling': 0, 'Trace Filter': 0}
    for line in memory.readlines():
        splits = line.rstrip().split(MEM_DELIMITER)
        if 'App:' in line:
            base = float(splits[-2])
        elif 'Metadata (Stream + Agg)' in line:
            mem = float(splits[-2])
            # This is aggregation of stream and metadata in 1:2 ratio
            meta = round(0.333 * (float(mem) / base), 6)
            mem_over['Metadata'] = meta
            trace = round(0.667 * (float(mem) / base), 6)
            mem_over['Trace Filter'] = trace
        elif 'Metadata (Fen)' in line:
            mem = float(splits[-2])
            over = round(float(mem / base), 6)
            mem_over['Fence'] = over
        elif 'Metadata (Sampling)' in line:
            mem = float(splits[-2])
            over = round(float(mem / base), 6)
            mem_over['Sampling'] = over
    memory.close()
    mem_table[app] = mem_over

output_lines = []
# For each app, list content in CSV format
output_lines.append("Application,Metadata,Fence,Sampling,TraceFilter\n")
for app in mem_table.keys():
    output_lines.append(f"{app},{mem_table[app]['Metadata']},{mem_table[app]['Fence']},{mem_table[app]['Sampling']},{mem_table[app]['Trace Filter']}\n")

f = open('table-3-result.csv', 'w')
for line in output_lines:
    # write to terminal
    print(line, end="")
    # write to results file
    f.write(line)
f.close()
