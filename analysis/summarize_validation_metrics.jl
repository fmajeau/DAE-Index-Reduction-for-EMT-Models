# Set up the package environment
cd(@__DIR__)
using Pkg
Pkg.activate("..")

# Import packages
using JLD2
using Printf
using Suppressor
using Statistics
using DataFrames
using CSV

# NOTE: can be run independently as long as there are solution_norm files in analysis/validation_files.

# This script uses the following:
#   analysis/validation_files/eigs_norms.jld2
#   analysis/validation_files/solution_norms_$(SYSTEM)_$(GEN_MIX).jld2
# And creates the following:
#   validation_files/validation_metrics.csv

# -----------------------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------------------
# For bash
# @assert length(ARGS) == 2 "Provide N_INSTANCES as 1st arg, GEN_MIX as 2nd arg"
# N_INSTANCES_ALL = [parse(Int, i) for i in split(string(ARGS[1]), ',')] # e.g. [1,2,4]
# GEN_MIX = ARGS[2] # e.g. "2sg1inv"  
# @assert GEN_MIX == "2sg1inv" "Only set up for GEN_MIX=\"2sg1inv\" at the moment"

# For VSCode
N_INSTANCES_ALL = [1,2,4,8,16,32,64,128]
GEN_MIX = "2sg1inv"

# -----------------------------------------------------------------------------------------
# Make CSV with values for table
# -----------------------------------------------------------------------------------------

# Make directory for jld2 files (no effect if it already exists)
sienna_load_dir = "../sienna/result_files"
mtk_load_dir = "../mtk/result_files"
save_dir = "validation_files"
mkpath(joinpath(dirname(@__FILE__),"$(save_dir)"))

# Create an empty DataFrame to store the validation metrics we will use in the paper
df_metrics = DataFrame(
    system = String[], 
    max_traj_diff_inf_norm = String[], 
    mean_traj_diff_inf_norm = String[], 
    eig_diff_inf_norm = String[]
    )

# Load eigenvalues to annotate
eigs_norms_dict = @suppress load_object(joinpath(dirname(@__FILE__),"$(save_dir)/eigs_norms.jld2"))

for N_INSTANCES in N_INSTANCES_ALL
    # Define system
    N_BUSES = 6*N_INSTANCES
    SYSTEM = "$(N_BUSES)Bus"

    # Load trajectory norms (all states)
    traj_norms_dict = @suppress load_object(joinpath(dirname(@__FILE__),"$(save_dir)/solution_norms_$(SYSTEM)_$(GEN_MIX).jld2"));
    traj_norms = collect(values(traj_norms_dict)) # don't need var names for mean/max metrics

    # Get summary metrics for trajectory norms (across all state variables in this system)
    traj_norm_max = maximum(traj_norms)
    traj_norm_mean = mean(traj_norms)

    # Get eigenvalue norm for this system (only one set per system)
    eig_norm = eigs_norms_dict[N_INSTANCES]

    # Get formatted metrics for validation table in paper
    str_system = @sprintf "%iBus" 9*N_INSTANCES # e.g. 9Bus, 18Bus
    str_traj_norm_max = @sprintf "%.1e" traj_norm_max
    str_traj_norm_mean = @sprintf "%.1e" traj_norm_mean
    str_eig_norm = @sprintf "%.1e" eig_norm

    # Add formatted values to the dataframe
    push!(df_metrics, (str_system, str_traj_norm_max, str_traj_norm_mean, str_eig_norm))
end

# Write to CSV
CSV.write(joinpath(dirname(@__FILE__),"$(save_dir)/validation_metrics.csv"), df_metrics)
