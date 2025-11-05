#!/bin/bash
set -x

program="./start_instance.sh"

# This script takes the following arguments:
# 1. cpi: core per instance
# 2. ni: number of instances
# 3. model-path: path to the model file
# 4. rep: number of repetitions (optional, default is 1)
# 5. input-length: input length
# 6. output-length: output length
# 7. batch-size: multiple batch sizes separated by commas (optional, default is "1,1,1,1,2,4,8")
# 8. file-name-prefix: prefix for the output file names
# 9. results-dir: directory to store the results (optional, default is current directory)

# parse command line arguments

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <cpi> <ni> <model-path> [<rep>] <input-length> <output-length> <file-name-prefix> [<results-directory>]"
    exit 1
fi

# Default values
rep=1
results_directory="."
batch_size="1,1,1"
# parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cpi) cpi="$2"; shift 2 ;;
        --ni) ni="$2"; shift 2 ;;
        --model) model_path="$2"; shift 2 ;;
        --rep) rep="$2"; shift 2 ;;
        --input) input_length="$2"; shift 2 ;;
        --output) output_length="$2"; shift 2 ;;
        --bs) batch_size="$2"; shift 2 ;;
        --name) file_name_prefix="$2"; shift 2 ;;
        --results-dir) results_dir="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done



for ((r=1; r<=$rep; r++)); do

    # run the instances on node 0
    node=0
    for ((i=1; i<=$ni; i++)); do
            screen -dmS ds_session_${i} $program $cpi $cpi "$((i*cpi - cpi))-$((i*cpi-1))" $node \
            "${results_dir}/${file_name_prefix}-i${ni}-s${i}-IN${input_length}-OUT${output_length}-rep${r}.txt" \
            $model_path $input_length $output_length $batch_size
    done

    # Wait for all screens to finish
    while true; do
            if screen -list | grep -q "ds_session"; then
                    echo "session is sitll running"
                    sleep 3
            else
                    break
            fi
    done


done
