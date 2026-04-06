#!/bin/bash

#SBATCH --nodes=1
#SBATCH --ntasks=32         # oom with 8, oom w/ 16, 40% utilization with 32
#SBATCH --time=3-00:00:00   # took 2-00:26:00 (5 runs)
#SBATCH --partition=amilan 
#SBATCH --qos=long
#SBATCH --output=build64-%j.out
#SBATCH --job-name=build64
#SBATCH --mail-type=ALL
#SBATCH --mail-user=fima7193@colorado.edu
#SBATCH --account=ucb-general

module purge
module load julia/1.11.6

# --- Activate the Julia environment
PROJECT_PATH="~/../../projects/fima7193/dae-index-reduction"
export JULIA_PROJECT=$PROJECT_PATH
julia --project=$PROJECT_PATH -e 'using Pkg; Pkg.activate()'

# --- Define arguments 
N_INSTANCES=64
GEN_MIX="2sg1inv"
NUM_RUNS=5
echo "N_INSTANCES="$N_INSTANCES
echo "GEN_MIX="$GEN_MIX
echo "NUM_RUNS="$NUM_RUNS

# --- Run build performance
echo "Starting analysis/measure_performance.jl..."
julia analysis/measure_performance.jl $N_INSTANCES $GEN_MIX $NUM_RUNS