#!/bin/bash

#SBATCH --nodes=1
#SBATCH --ntasks=1          # ~2.7/3.75, 98% CPU
#SBATCH --time=00:20:00     # ~00:05:00 (01:03:00 cpu)
#SBATCH --partition=amilan 
#SBATCH --qos=normal
#SBATCH --output=solve8-%j.out
#SBATCH --job-name=solve8
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
ABSTOL="1e-7"
RELTOL="1e-4"
NUM_RUNS=5
echo "N_INSTANCES="$N_INSTANCES
echo "GEN_MIX="$GEN_MIX
echo "ABSTOL="$ABSTOL
echo "RELTOL="$RELTOL
echo "NUM_RUNS="$NUM_RUNS

# --- Run build performance
echo "Starting analysis/measure_performance_solve.jl..."
julia analysis/measure_performance_solve.jl $N_INSTANCES $GEN_MIX $ABSTOL $RELTOL $NUM_RUNS