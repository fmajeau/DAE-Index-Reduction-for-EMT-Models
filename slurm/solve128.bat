#!/bin/bash

#SBATCH --nodes=1
#SBATCH --ntasks=24         # oom with 3.75*16, oom with 3.75*32, oom with 3.75*64, 89% with 15.6*24
#SBATCH --time=08:00:00     # timed out @ 6hours
#SBATCH --partition=amem 
#SBATCH --qos=mem
#SBATCH --output=solve128-%j.out
#SBATCH --job-name=solve128
#SBATCH --mail-type=ALL
#SBATCH --mail-user=fima7193@colorado.edu
#SBATCH --account=ucb-general

# --- tried ntasks=64, time=6, partition=amilan, qos=normal .. was OOM on 2nd MTK run. also, i

module purge
module load julia/1.11.6

# --- Activate the Julia environment
PROJECT_PATH="~/../../projects/fima7193/dae-index-reduction"
export JULIA_PROJECT=$PROJECT_PATH
julia --project=$PROJECT_PATH -e 'using Pkg; Pkg.activate()'

# --- Define arguments 
N_INSTANCES=128
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