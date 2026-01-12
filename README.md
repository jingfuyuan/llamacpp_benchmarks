# LLM Inference on CPU Benchmarking with llama.cpp

This package provides scripts to benchmark LLM inference performance on CPU using llama.cpp's batched benchmarking tool. It supports running multiple instances concurrently and includes utilities for extracting and summarizing results.

## Features

- **Single socket benchmarking** (requires modification for dual socket systems). For dual socket performance, it is advisable to extrapolate from single sokcet performance, because there is no communication between instances.
- **Multi-instance support** - run multiple inference instances in parallel
- **Batch size sweeping** - test various batch sizes in a single run
- **Automated result extraction** - parse log files into CSV summaries with statistics

## Prerequisites

- [llama.cpp](https://github.com/ggerganov/llama.cpp) compiled with `llama-batched-bench` binary
- `numactl` for CPU affinity control
- `screen` for managing multiple instances
- Python 3 with `pandas` for result extraction

## Compile llama.cpp with AOCC

### Install AOCC
Download from this link: https://www.amd.com/en/developer/aocc.html. Follow the instructions.
For Ubuntu, run the following command:
```bash
sudo dpkg -i aocc-compiler-5.0.0_1_amd64.deb
```
It is installed at /opt/AMD/aocc-compiler-5.0.0

### Build llama.cpp with AOCC
Here are steps for building llama.cpp with AOCC:
```bash
source /opt/AMD/aocc-compiler-5.0.0/setenv_AOCC.sh
git clone llama.cpp
cd llama.cpp
cmake -B build -DCMAKE_C_COMPILER=/opt/AMD/aocc-compiler-5.0.0/bin/clang -DCMAKE_CXX_COMPILER=/opt/AMD/aocc-compiler-5.0.0/bin/clang++ 
cmake --build build --config Release -j $(nproc)
```
when you run AOCC built llama.cpp, make sure AOCC environment is activated using command `source /opt/AMD/aocc-compiler-5.0.0/setenv_AOCC.sh`
When building llama.cpp, if you see “could not find CURL error”, run `sudo apt install curl libcurl4-openssl-dev`.

## Directory Structure

```
├── run_batch.sh              # Main entry point for running benchmarks
├── run_multi_instances.sh    # Orchestrates multiple parallel instances
├── start_instance.sh         # Launches a single benchmark instance
├── extract_results.py        # Extracts and summarizes results from logs
└── results/                  # Output directory for benchmark results
```

## Configuration

Before running benchmarks, configure the following environment variables in `run_batch.sh`:

```bash
export env_file="/opt/AMD/aocc-compiler-5.0.0/setenv_AOCC.sh"  # Compiler environment (optional)
export BENCH_PROGRAM="/path/to/llama.cpp/build/bin/llama-batched-bench"
```

## Usage

### Running Benchmarks

Edit `run_batch.sh` to configure the test for your speicific platform.
Here is an example of this script:
```bash
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
root_dir="$(pwd)/results/TurinC-128C"
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
                done
	done
done
```
Key variables explained:
- `testing_models` - array of GGUF model paths
- `total_cores` - total CPU cores available on the socket
- `in_out_length` - array of input/output token length combinations (format: "input/output")
- `batch_size` - comma-separated batch sizes to test. **keep "1,1,1" at the beginning as warmup runs"**
- `rep` - number of repetitions for each configuration
- `ni` - number of instances
- `cpi` - core per instance

Then run:

```bash
./run_batch.sh
```

### Extracting Results

For each model, the `llama-batch-bench` output logs of all configurations are included in one folder named with that model. The log file name has a format like `110525-TurinC-i4-s2-IN128-OUT128-rep2.txt`.  
Here is the interpretation:
- `i4`: total 4 instances running
- `s2`: the second instance
- `IN128`: 128 input tokens
- `OUT128`: 128 output tokens
- `rep2`: the second repeating run

After benchmarks complete, extract results to CSV using the `extract_results.py` script:

```bash
# Process a single model directory
python extract_results.py --input_dir ./results/CPU-Name/Model-Name

# Process multiple models using wildcards (quote the path)
python extract_results.py --input_dir "./results/CPU-Name/*"
```

This generates two CSV files per model:
- `<model-name>-<timestamp>.csv` - detailed results from all runs
- `<model-name>-summary-<timestamp>.csv` - aggregated statistics (mean, std, total throughput)

## Output Metrics

The benchmark captures the following metrics:

| Metric | Description |
|--------|-------------|
| PP | Prompt processing tokens |
| TG | Token generation count |
| B | Batch size |
| T_PP s | Prompt processing time (seconds) |
| S_PP t/s | Prompt processing speed (tokens/sec) |
| T_TG s | Token generation time (seconds) |
| S_TG t/s | Token generation speed (tokens/sec) |
| T s | Total time (seconds) |
| S t/s | Total speed (tokens/sec) |

## Notes

- The scripts use `screen` to manage parallel instances. Use `screen -list` to monitor running sessions.
- Warmup runs are automatically excluded during result extraction (only the last run per configuration is kept).
- Results are organized by: `<results-dir>/<CPU-name>/<Model-name>/<benchmark-files>.txt`
- The `--numa numactl` flag is passed to llama-batched-bench for NUMA-aware execution.

## Limitations

- Currently designed for **single socket** systems. Dual socket support requires modifications to `run_multi_instances.sh` to distribute instances across NUMA nodes.
- CPU binding assumes contiguous core allocation starting from core 0.

