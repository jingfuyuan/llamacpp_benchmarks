# use this script to exract llama.cpp benchmarking results from the log files
# Usage: python extract_results.py --input_dir folder_name
# Your input directory should has the following structure:
# <input_dir>/<model_name>/file.txt

import os
import re
import argparse
import pandas as pd
from pathlib import Path
from glob import glob
from datetime import datetime

def process_one_file(file_path) -> pd.DataFrame:
    # read the file, extract data from the lines starting with "|"
    # should skip the first two lines starting with "|", which are headers
    col_names = ["PP", "TG", "B", "N_KV", "T_PP s", "S_PP t/s", "T_TG s", "S_TG t/s", "T s", "S t/s"]
    data = []
    with open(file_path, "r") as f:
        skip_count = 0
        lines = f.readlines()
        for line in lines:
            if line.startswith("|"):
                skip_count += 1
                if skip_count <= 2:
                    continue
                # extract the data between "|"
                parts = [float(part.strip()) for part in line.split("|")[1:-1]]
                data.append(parts)
    df = pd.DataFrame(data, columns=col_names)
    # remove warmup runs. For the same PP, TG, and B, only keep the last run
    df = df.groupby(["PP", "TG", "B"], as_index=False).last()
    df[["PP", "TG", "B", "N_KV"]] = df[["PP", "TG", "B", "N_KV"]].astype(int)

    # extract other information from the file path
    # extract cpu_name and model_name from the file path
    file_path = Path(file_path).absolute()
    path_parts = file_path.parts
    cpu_name = path_parts[-3]
    model_name = path_parts[-2]
    file_name = path_parts[-1]
    df["file_path"] = str(file_path)
    df["CPU"] = cpu_name
    df["Model"] = model_name
    # extract num_instances, instance_id and repeat_id from the file name
    # here is an example file name: 110525-TurinC-i4-s4-IN128-OUT128-rep1.txt. 
    # need to extract: num_instances=4, instance_id=4, repeat_id=1
    match = re.search(r'-i(\d+)-s(\d+).*-rep(\d+)', file_name)
    if match:
        num_instances = int(match.group(1))
        instance_id = int(match.group(2))
        repeat_id = int(match.group(3))
    else:
        num_instances = None
        instance_id = None
        repeat_id = None
    df["num_instances"] = num_instances
    df["instance_id"] = instance_id
    df["repeat_id"] = repeat_id

    order_cols = ["file_path", "CPU", "Model", "num_instances", "instance_id", "repeat_id"] + col_names
    df = df[order_cols]
    # print(df.iloc[:5,3:])
    return df
    
def process_one_model(input_dir):
    input_dir = Path(input_dir)
    model_name = input_dir.name
    cpu_name = input_dir.parent.name
    all_files = glob(os.path.join(input_dir, "*.txt"))
    all_files = sorted(all_files)
    print(f"processing {len(all_files)} files in {input_dir}")
    all_dfs = []
    for file_path in all_files:
        df = process_one_file(file_path)
        all_dfs.append(df)
    final_df = pd.concat(all_dfs, ignore_index=True)
    # save the final_df to a csv file with the timestamped name
    timestamp = datetime.now().strftime("-%Y%m%d-%H%M%S")
    file_name = model_name + timestamp + ".csv"
    output_path = input_dir.parent.parent / file_name
    final_df.to_csv(output_path, index=False)
    print(f"saved the extracted results to {output_path}")
    # calculate the avarage throughput for each configuration
    stat_cols = ["T_PP s", "S_PP t/s", "T_TG s", "S_TG t/s", "T s", "S t/s"]
    summary_df_mean = final_df.groupby(["num_instances", "PP", "TG", "B"])[stat_cols].mean()
    summary_df_mean["total_tps"] = summary_df_mean["S_TG t/s"] * summary_df_mean.index.get_level_values("num_instances")
    summary_df_std = final_df.groupby(["num_instances", "PP", "TG", "B"])[stat_cols].std()
    summary_df_std.columns = [col + " std" for col in stat_cols]
    summary_df = pd.concat([summary_df_mean, summary_df_std], axis=1).reset_index()
    summary_df.insert(0, "Model", model_name)
    summary_df.insert(0, "CPU", cpu_name)
    summary_file_name = input_dir.name + "-summary" + timestamp + ".csv"
    summary_output_path = input_dir.parent.parent / summary_file_name
    summary_df.to_csv(summary_output_path, index=False)
    print(f"saved the summary results to {summary_output_path}")
    return summary_df



if __name__ == "__main__":
    # test the function
    parser = argparse.ArgumentParser()
    parser.add_argument("--input_dir", type=str, required=True, help="Input directory containing batched llama.cpp benchmarking results")
    args = parser.parse_args()
    input_dir = args.input_dir
    # input_dir is expected to be like: ./test_name/<cpu_name>/<model_name>/ or "./test_name/<cpu_name>/*"
    # input_dir could be a wildcard path. If using wildcard, need to quote the path on the command line. 
    if "*" in input_dir:
        matched_dirs = glob(input_dir)
        for dir_path in matched_dirs:
            if os.path.isdir(dir_path):
                process_one_model(dir_path)
    else:
        process_one_model(input_dir)
