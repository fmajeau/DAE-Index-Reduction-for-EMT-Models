#!/bin/bash

#SBATCH --nodes=1
#SBATCH --ntasks=64         # 73% utilization with 64
#SBATCH --time=7-00:00:00   # timed out with 7 days (completed 3 runs, was working on 4th) had to do 5.5 because of maintenance.
#SBATCH --partition=amilan 
#SBATCH --qos=long
#SBATCH --output=build128-%j.out
#SBATCH --job-name=build128
#SBATCH --mail-type=ALL
#SBATCH --mail-user=fima7193@colorado.edu
#SBATCH --account=ucb-general

module purge
module load julia/1.11.6

# --- Activate the Julia environment
PROJECT_PATH="~/../../projects/fima7193/dae-index-reduction"
export JULIA_PROJECT=$PROJECT_PATH
julia --project=$PROJECT_PATH

# --- Define arguments 
N_INSTANCES=128
GEN_MIX="2sg1inv"
NUM_RUNS=5
echo "N_INSTANCES="$N_INSTANCES
echo "GEN_MIX="$GEN_MIX
echo "NUM_RUNS="$NUM_RUNS

# --- Run build performance
echo "Starting analysis/measure_performance.jl..."
julia analysis/measure_performance.jl $N_INSTANCES $GEN_MIX $NUM_RUNS