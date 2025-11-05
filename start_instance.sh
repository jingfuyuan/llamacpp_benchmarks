#!/bin/bash

source $env_file

threads=$1
tb=$2
bind_cpu=$3
node=$4
file_name=$5
model_path=$6
input_length=$7
output_length=$8
batch_size=$9

# check whether BENCH_PROGRAM is set
if [ -z $BENCH_PROGRAM ]; then
    echo "BENCH_PROGRAM is not set. Please set it to the path of the llama-batched-bench program."
    exit 1
fi

# get the biggest batch size 
IFS=',' read -r -a batch_sizes <<< "$batch_size"
max_bs=${batch_sizes[-1]}
max_ctx=$(( (input_length + output_length) * max_bs ))


numactl -C $bind_cpu -m $node $BENCH_PROGRAM -m $model_path -t $threads -tb $tb --numa numactl -b 2048 -ub 1024 -c $max_ctx \
        -npp $input_length -ntg $output_length -npl $batch_size -fa on --no-mmap 2>&1 | tee $file_name
