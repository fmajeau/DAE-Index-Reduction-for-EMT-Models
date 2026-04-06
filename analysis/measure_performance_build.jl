# Set up the package environment
cd(@__DIR__)
using Pkg
Pkg.activate("..")

# Import packages
using PowerSystems
const PSY = PowerSystems
using PowerSimulationsDynamics
const PSID = PowerSimulationsDynamics
using OrdinaryDiffEq
using LinearAlgebra
using JLD2
using ModelingToolkit
using Printf
using Statistics #mean
using Suppressor 
using Logging
using Serialization #stlib

using ModelingToolkit: t_nounits as t, D_nounits as D
# NOTE: using ModelingToolkitv9.68.1 for now. Things broke w/ v10.22.0, it might be related
# to how I'm accessing the system to calculate residuals, because residuals were non-zero.
# Figure this out later in order to upgrade ModelingToolkit, not a priority right now.

include("../mtk/utils/SystemDefinitions_MTK.jl")
include("../mtk/utils/helper_functions_MTK.jl")
include("../sienna/utils/helper_functions_Sienna.jl") 

# This script creates the following:
#   performance_files_build/odeproblem_build_MTK_{SYSTEM}_{GEN_MIX}.jld2
#   performance_files_build/performance_build_MTK_{SYSTEM}_{GEN_MIX}.jld2
#   performance_files_build/performance_build_Sienna_{SYSTEM}_{GEN_MIX}.jld2
    
# -----------------------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------------------
@assert length(ARGS) == 3 "Provide N_INSTANCES as 1st arg, GEN_MIX as 2nd arg, NUM_RUNS as third arg"
N_INSTANCES_ALL = [parse(Int, i) for i in split(string(ARGS[1]), ',')] # e.g. [1,2,4]
GEN_MIX = ARGS[2] # e.g. "2sg1inv"  
NUM_RUNS = parse(Int, ARGS[3])
@assert GEN_MIX == "2sg1inv" "Only set up for GEN_MIX=\"2sg1inv\" at the moment"
# Number of runs per model type and size (i.e. number of times through "6Bus" Sienna) 
@assert NUM_RUNS > 1 "NUM_RUNS must be more than 1 since first compile-heavy run is excluded"

# For VSCode
#N_INSTANCES_ALL = [1,2]
#GEN_MIX = "2sg1inv"

# -----------------------------------------------------------------------------------------
# TEST SET UP
# -----------------------------------------------------------------------------------------
# Create a ConsoleLogger that writes to the file
log_label = join(string.(N_INSTANCES_ALL), "_")
io = open("performance_build$(log_label).log", "w")
logger = ConsoleLogger(io)

# Create directory to save results
save_dir = "performance_files_build"
mkpath(joinpath(dirname(@__FILE__),"$(save_dir)"))

# Log a single run to the output file
function log_one_run(logger, run, SYSTEM, i)
    with_logger(logger) do
        @info @sprintf("[%s] Run # %i", SYSTEM, i)
        @info @sprintf "   Mem (allocated):    %12.4f GiB" run.gcstats.allocd/(2^30)
        @info @sprintf "   Mem (MaxRSS):       %12.4f GiB" run.maxrss/(2^30)
        @info @sprintf "   Time (total):       %12.4f s" run.time
        @info @sprintf "   Time (compile):     %12.4f s" run.compile_time
        @info @sprintf "   Time (recompile):   %12.4f s" run.recompile_time
        @info @sprintf "   Time (gc):          %12.4f s" run.gctime
        flush(logger.stream) # force write to txt so we can watch progress
    end
end

# Summarize the runs for a specific size and model type (i.e. "6bus" Sienna)
function log_summary(logger, stats, model_name)
    with_logger(logger) do
        for N_INSTANCES in N_INSTANCES_ALL
            N_BUSES = 6*N_INSTANCES
            SYSTEM = "$(N_BUSES)Bus"
            @info @sprintf("------------------------------------------------------------- %s %5s (SUMMARY)", model_name, SYSTEM)
            stats_sys = stats[N_INSTANCES]
            n = length(stats_sys)
            time_executed_dict = Dict{Int64,Float64}()
            mem_allocated_dict = Dict{Int64,Float64}()
            mem_maxrss_dict = Dict{Int64,Float64}()
            for (i, run) in stats_sys
                time_executed_dict[i] = run.time
                mem_allocated_dict[i] = run.gcstats.allocd
                mem_maxrss_dict[i] = run.maxrss
            end

            # Calculate mean (exclude first run because compile time is significant)
            time_executed_mean = mean(collect(val for (i, val) in time_executed_dict if i != 1))
            mem_allocated_mean = mean(collect(val for (i, val) in mem_allocated_dict if i != 1))
            mem_maxrss_mean = mean(collect(val for (i, val) in mem_maxrss_dict if i != 1))

            # Print average info to log file
            @info @sprintf "> AVERAGE across %i runs (excludes compile-heavy first run)" (n-1)
            @info @sprintf "   Time (total):     %12.4f sec" time_executed_mean
            @info @sprintf "   Mem (allocated):  %12.4f GiB" mem_allocated_mean/2^30
            @info @sprintf "   Mem (MaxRSS):     %12.4f GiB" mem_maxrss_mean/2^30
            flush(logger.stream) # force write to txt so we can watch progress
        end
    end
end

# Starting Logging
# TODO: remove the full process logging once you know it is running smoothly since logger
# adds performance overhead
with_logger(logger) do

# -----------------------------------------------------------------------------------------
# SIENNA
# -----------------------------------------------------------------------------------------
# Run all systems n times and save the stats
# TODO: probably remove all of the print statements from PSID
stats_sienna = Dict()
for N_INSTANCES in N_INSTANCES_ALL
    N_BUSES = 6*N_INSTANCES
    SYSTEM = "$(N_BUSES)Bus"
    @info @sprintf("------------------------------------------------------------- %s %5s (ALL RUNS) ", "Sienna", SYSTEM)
    @info @sprintf("Building simulation and initial conditions...")
    flush(logger.stream)

    # Get initial conditions
    path = joinpath(dirname(@__FILE__), "../sienna/json_files/$(SYSTEM)_$(GEN_MIX).json")
    sys = PSY.System(path, runchecks=false);
    load_device = get_component(StandardLoad, sys, "load81");
    perturbation = LoadChange(1.0, load_device, :P_ref_impedance, 0.8);
    sim = Simulation!(MassMatrixModel, sys, pwd(), (0.0, 30.0), perturbation);
    x0_init_known = PSID.get_initial_conditions(sim); # save so we can use below
    @info @sprintf("\n### MaxRSS BEFORE Sienna %s = %.4f GiB \n ", SYSTEM, Sys.maxrss()/(2^30))
    flush(logger.stream)

    # Get performance info assuming we know the initial conditions
    # NOTE: this is so we can compare apples to apples w/ MTK which relies on Sienna's IC
    stats_sienna_system = Dict()
    for i in 1:NUM_RUNS
        @info @sprintf("--- [%s] Run # %i", SYSTEM, i)
        flush(logger.stream)
        GC.gc() # Force a garbage collection

        # --- TIMED SECTION ---
        stats = @timed begin
            sys = PSY.System(path, runchecks=false);
            load_device = get_component(StandardLoad, sys, "load81");
            perturbation = LoadChange(1.0, load_device, :P_ref_impedance, 0.8);
            sim = Simulation!(
                MassMatrixModel, sys, pwd(), (0.0, 30.0), perturbation;
                initialize_simulation = false,
                initial_conditions = x0_init_known,
            );
        end;

        # Remove :value (i.e. what this code returns) before saving, don't need it and takes up space
        stats_new = merge(stats, (maxrss = Sys.maxrss(),))
        stats_sienna_system[i] = Base.structdiff(stats_new, NamedTuple{(:value,)}((stats_new.value,))) 
        log_one_run(logger, stats_sienna_system[i], SYSTEM, i);
    end
    @info stats_sienna_system
    stats_sienna[N_INSTANCES] = stats_sienna_system; 
    @suppress save_object(joinpath(dirname(@__FILE__),"$(save_dir)/performance_build_Sienna_$(SYSTEM)_$(GEN_MIX).jld2"), stats_sienna_system);
    @info @sprintf("\n### MaxRSS AFTER Sienna %s = %.4f GiB \n ", SYSTEM, Sys.maxrss()/(2^30))
end

# Log the summary metrics
log_summary(logger, stats_sienna, "Sienna")


# -----------------------------------------------------------------------------------------
# MTK
# -----------------------------------------------------------------------------------------

# Run all systems n times and save the stats
stats_mtk = Dict()
for N_INSTANCES in N_INSTANCES_ALL
    N_BUSES = 6*N_INSTANCES
    SYSTEM = "$(N_BUSES)Bus"

    @info @sprintf("------------------------------------------------------------- %s %5s (ALL RUNS) ", "MTK", SYSTEM)
    @info @sprintf("Loading sienna init_files...")
    flush(logger.stream)

    # Import initial conditions & set points from Sienna (same for all systems)
    x0 = @suppress load_object(joinpath(dirname(@__FILE__), "../sienna/init_files/x0_$(SYSTEM)_$(GEN_MIX).jld2")); # BEFORE BUILD SCRIPT / NOT SYSTEM SPECIFIC
    sp = @suppress load_object(joinpath(dirname(@__FILE__), "../sienna/init_files/sp_$(SYSTEM)_$(GEN_MIX).jld2"));
    bridges = @suppress load_object(joinpath(dirname(@__FILE__), "../sienna/init_files/bridges_$(SYSTEM)_$(GEN_MIX).jld2"));
    @info @sprintf("\n### MaxRSS BEFORE MTK %s = %.4f GiB \n ", SYSTEM, Sys.maxrss()/(2^30))
    flush(logger.stream)

    # Get performance info assuming we know the initial conditions
    stats_mtk_system = Dict()
    for i in 1:NUM_RUNS
        @info @sprintf("--- [%s] Run # %i", SYSTEM, i)
        flush(logger.stream)
        GC.gc() # Force a garbage collection

        # --- TIMED SECTION ---
        stats = @timed begin
            # Build MTK model and map initial conditions from Sienna
            (sys, u0_dict) = build_MTK_model(SYSTEM, x0, sp, bridges)

            # Build numerical model as ODE
            prob_init = ODEProblem(sys, u0_dict, (0.0, 30.0), jac=true, sparse=true) # This converts MTK model into ODEProblem format
            prob_ode = remake(prob_init; p = deepcopy(prob_init.p)) # same, just make parameters a copy
            # prob_ode = ODEProblem(
            #     prob_init.f, prob_init.u0, 
            #     prob_init.tspan, copy(prob_init.p))
        end;

        # Remove :value (i.e. what this code returns) before saving, don't need it and takes up space
        stats_new = merge(stats, (maxrss = Sys.maxrss(),))
        stats_mtk_system[i] = Base.structdiff(stats_new, NamedTuple{(:value,)}((stats_new.value,)))
        log_one_run(logger, stats_mtk_system[i], SYSTEM, i);

        # Save model after the first run to reuse in other scripts
        if i == 1
            @info @sprintf("Saving prod_ode to binary... (first run only)")
            flush(logger.stream)
            Serialization.serialize(joinpath(dirname(@__FILE__),"$(save_dir)/odeproblem_build_MTK_$(SYSTEM)_$(GEN_MIX).jld2"), prob_ode)
        end
        # Save as you go since these ones take so long (it will save 1, then 1,2, then 1,2,3, so just overwrite)
        if N_INSTANCES in [64,128] 
            @suppress save_object(joinpath(dirname(@__FILE__),"$(save_dir)/performance_build_MTK_$(SYSTEM)_$(GEN_MIX)_progress.jld2"), stats_mtk_system);
        end
    end
    @info stats_mtk_system
    stats_mtk[N_INSTANCES] = stats_mtk_system; # save dict of tests for this system
    @suppress save_object(joinpath(dirname(@__FILE__),"$(save_dir)/performance_build_MTK_$(SYSTEM)_$(GEN_MIX).jld2"), stats_mtk_system);
    @info @sprintf("\n### MaxRSS AFTER MTK %s = %.4f GB \n ", SYSTEM, Sys.maxrss()/(2^30))
end

# Log the summary metrics
log_summary(logger, stats_mtk, "MTK")
@info @sprintf("************ DONE ************")

end # of "with_logger(logger) do"

# Close log file
flush(io)
close(io)
