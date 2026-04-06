#!/bin/bash

#SBATCH --nodes=1
#SBATCH --ntasks=4          # 7.5/7.5GB, 56% CPU
#SBATCH --time=01:15:00     # 00:01:00
#SBATCH --partition=amilan 
#SBATCH --qos=normal
#SBATCH --output=mtk16-%j.out
#SBATCH --job-name=mtk16
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
N_INSTANCES=16
GEN_MIX="2sg1inv"
ABSTOL="1e-7"
RELTOL="1e-4"
echo "N_INSTANCES="$N_INSTANCES
echo "GEN_MIX="$GEN_MIX
echo "ABSTOL="$ABSTOL
echo "RELTOL="$RELTOL

# --- Run build performance
echo "Starting analysis/measure_performance_solve.jl..."
julia mtk/run_simulation_MTK.jl $N_INSTANCES $GEN_MIX $ABSTOL $RELTOL