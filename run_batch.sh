#!/bin/bash
export env_file="/opt/AMD/aocc-compiler-5.0.0/setenv_AOCC.sh"
export BENCH_PROGRAM="/home/amd/workspace/llama.cpp.b6946/build/bin/llama-batched-bench"

testing_models=(
        "/home/amd/dataset/hf_home/gguf/Qwen3-30B-A3B-Q8_0.gguf"
        "/home/amd/dataset/hf_home/gguf/Qwen3-30B-A3B-BF16.gguf"
        "/home/amd/dataset/hf_home/gguf/gpt-oss-20b-F16.gguf"
        "/home/amd/dataset/hf_home/gguf/gpt-oss-20b-Q8_0.gguf"
        "/home/amd/dataset/hf_home/gguf/llama-3.1-8B-bf16.gguf"
        "/home/amd/dataset/hf_home/gguf/Meta-Llama-3.1-8B-Instruct-Q8_0.gguf"
        "/home/amd/dataset/hf_home/gguf/DeepSeek-R1-Distill-Qwen-7B-Q8_0.gguf"
        "/home/amd/dataset/hf_home/gguf/DeepSeek-R1-Distill-Qwen-7B-f16.gguf"
        "/home/amd/dataset/hf_home/gguf/Qwen3-32B-Q4_K_M.gguf"
	)

total_cores=128
root_dir="$(pwd)/TurinC-128C"
in_out_length=("128/128" "128/1024" "1024/128" "1024/1024")
batch_size="1,1,1,2,4,8,16,32"
file_name_prefix="110525-TurinC"
rep=4

for model_path in "${testing_models[@]}"; do
	model_name=$(basename "$model_path")
	model_name="${model_name%.*}"
	results_dir="${root_dir}/${model_name}"
	if [ ! -d "$results_dir" ]; then
		mkdir -p "$results_dir"
	fi
	for ni in 1 2 4; do
		cpi=$((total_cores / ni))
                for input_output in "${in_out_length[@]}"; do
                    IFS='/' read -r input_length output_length <<< "$input_output"
                    ./run_multi_instances.sh --cpi "$cpi" --ni "$ni" --model "$model_path"  --rep "$rep" \
                        --input "$input_length" --output "$output_length" --bs "$batch_size" \
                        --name "${file_name_prefix}" --results-dir "$results_dir"
            	#exit 1
                done
	done
	#exit 1
done

