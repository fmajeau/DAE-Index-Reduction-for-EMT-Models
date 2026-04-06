#!/bin/bash

#SBATCH --nodes=1
#SBATCH --ntasks=2          # ~2.6/7.5
#SBATCH --time=01:00:00     # ~00:51:00
#SBATCH --partition=amilan 
#SBATCH --qos=normal
#SBATCH --output=build8-%j.out
#SBATCH --job-name=build8
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
N_INSTANCES=8
GEN_MIX="2sg1inv"
NUM_RUNS=5
echo "N_INSTANCES="$N_INSTANCES
echo "GEN_MIX="$GEN_MIX
echo "NUM_RUNS="$NUM_RUNS

# --- Run build performance
echo "Starting analysis/measure_performance.jl..."
julia analysis/measure_performance.jl $N_INSTANCES $GEN_MIX $NUM_RUNS