# Set up the package environment
cd(@__DIR__)
#using Pkg
#Pkg.activate("..")

# Import packages
using OrdinaryDiffEq
using ModelingToolkit # 9.68.1
using JLD2
using LinearAlgebra # norm()
using Suppressor
using Printf
using Logging
using Serialization #stlib
using ForwardDiff

using ModelingToolkit: t_nounits as t, D_nounits as D
# NOTE: using ModelingToolkitv9.68.1 for now. Things broke w/ v10.22.0, it might be related
# to how I'm accessing the system to calculate residuals, because residuals were non-zero.
# Figure this out later in order to upgrade ModelingToolkit, not a priority right now.

include("utils/SystemDefinitions_MTK.jl")
include("utils/helper_functions_MTK.jl")


# -----------------------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------------------
@assert length(ARGS) == 4 "Provide N_INSTANCES as 1st arg, GEN_MIX as 2nd arg"
N_INSTANCES_ALL = [parse(Int, i) for i in split(string(ARGS[1]), ',')] # e.g. [1,2,4]
GEN_MIX = ARGS[2] # e.g. "2sg1inv"  
ABSTOL = parse(Float64, ARGS[3])
RELTOL = parse(Float64, ARGS[4])
@assert GEN_MIX == "2sg1inv" "Only set up for GEN_MIX=\"2sg1inv\" at the moment"

# For VSCode
# N_INSTANCES_ALL = [1]
# GEN_MIX = "2sg1inv"
# ABSTOL = 1e-7
# RELTOL = 1e-4

# -----------------------------------------------------------------------------------------
# Run all simulations
# -----------------------------------------------------------------------------------------
# Make directory for jld2 files (no effect if they already exists)
save_dir = "result_files"
mkpath(joinpath(dirname(@__FILE__),"$(save_dir)"))

function get_live_bytes_mib(;gc_before=false)
    if gc_before
        GC.gc()
    end
    return Base.gc_live_bytes() / (2^20)
end

function load_or_build_ODEProblem(sys, u0_dict, tspan, path; force_build=false)
    local prob
    if !force_build && isfile(path)
        # Load ODEProblem from binary if available
        @info @sprintf("Found serialized ODEProblem."); flush(logger.stream);
        t0 = time()
        prob = deserialize(path) 
        @info @sprintf(" >> ODEProblem Load: RUNTIME = %.2f sec", time() - t0); flush(logger.stream);
    else
        # Build ODEProblem from MTK system if not (this step is called "codegen")
        @info @sprintf("Did not find serialized ODEProblem."); flush(logger.stream);
        @info @sprintf("Starting conversion from MTK to ODEProblem..."); flush(logger.stream);
        t0 = time()
        prob = ODEProblem(sys, u0_dict, tspan, jac=true, sparse=true) # builds symbolic form of jacobian
        @info @sprintf(" >> ODEProblem Build: RUNTIME = %.2f sec", time() - t0)

        # Serialize so we can skip the codegen step later
        serialize(path, prob) # saves functions unlike load_object
    end
    return prob
end

# Create a ConsoleLogger that writes to the file
log_label = join(string.(N_INSTANCES_ALL), "_")
io = open("run_sim_MTK_$(log_label)_sparse_final.log", "w")
logger = ConsoleLogger(io)
with_logger(logger) do 

for N_INSTANCES in N_INSTANCES_ALL
    
    # -------------------------------------------------------------------------------------
    # DEFINE SYSTEM TO BUILD
    # -------------------------------------------------------------------------------------
    N_BUSES = 6*N_INSTANCES
    SYSTEM = "$(N_BUSES)Bus"
    @info @sprintf("\n------------------------[N = %i] Starting %s...", N_INSTANCES, SYSTEM); flush(logger.stream);
    
    # -------------------------------------------------------------------------------------
    # Load initial conditions and set points from Sienna
    # -------------------------------------------------------------------------------------
    # Import initial condition from Sienna
    x0 = @suppress load_object(joinpath(dirname(@__FILE__), "../sienna/init_files/x0_$(SYSTEM)_$(GEN_MIX).jld2"));

    # Import set points from Sienna
    sp = @suppress load_object(joinpath(dirname(@__FILE__), "../sienna/init_files/sp_$(SYSTEM)_$(GEN_MIX).jld2"))

    # Import bridges from Sienna
    bridges = @suppress load_object(joinpath(dirname(@__FILE__), "../sienna/init_files/bridges_$(SYSTEM)_$(GEN_MIX).jld2"))
    bridges = convert(Dict{Symbol, Dict{Symbol, Union{Int64, String}}} , bridges)

    # -------------------------------------------------------------------------------------
    # Build MTK system and associated initial conditions
    # -------------------------------------------------------------------------------------
    # Run system-specific script builds `sys` and `u0_dict`
    @info @sprintf("Starting MTK model build...")
    @info @sprintf(" >> ODEProblem creation: INITIAL live bytes = %.1f MiB", get_live_bytes_mib(gc_before=true)); flush(logger.stream);    
    t0 = time()
    (sys, u0_dict) = build_MTK_model(SYSTEM, x0, sp, bridges); ### still need this for varmap and parameter indexing
    @info @sprintf(" >> @mtkbuild: RUNTIME = %.2f sec", time() - t0)
    
    diff_count = length(findall(x -> occursin("Differential(t)(", string(x)), equations(sys)));
    alg_count = length(findall(x -> occursin("0 ~ ", string(x)), equations(sys)));
    @info @sprintf(" >> %i diff states + %i alg states = %i total", diff_count, alg_count, diff_count + alg_count)

    # -------------------------------------------------------------------------------------
    # Load or build ODEProblem from MTK model to use for simulations
    # -------------------------------------------------------------------------------------
    tspan = (0.0, 30.0)
    path_ODEProblem = joinpath(dirname(@__FILE__),"$(save_dir)/odeproblem_$(SYSTEM)_$(GEN_MIX).jld2")
    prob_init_ode = load_or_build_ODEProblem(sys, u0_dict, tspan, path_ODEProblem; force_build=false)

    # -------------------------------------------------------------------------------------
    # Calculate residual (just a sanity check)
    # -------------------------------------------------------------------------------------
    @info @sprintf("Starting residual evaluation..."); flush(logger.stream);
    resid = prob_init_ode.f(prob_init_ode.u0,prob_init_ode.p,t)
    @info @sprintf("Norm of residual of IC: %.8e", LinearAlgebra.norm(resid,Inf)); flush(logger.stream);

    # Build problem to solve (need copy of params since we are perturbing params)
    @info @sprintf("Building prob_ode = ODEProblem(..."); flush(logger.stream);
    #prob_ode = ODEProblem(prob_init_ode.f, prob_init_ode.u0, tspan, copy(prob_init_ode.p), jac=true, sparse=true)
    prob_ode = remake(prob_init_ode; p = deepcopy(prob_init_ode.p)) # same, just make parameters a copy
    @info @sprintf(" >> ODEProblem creation: FINAL live bytes = %.1f MiB", get_live_bytes_mib(gc_before=false)); flush(logger.stream);

    # -------------------------------------------------------------------------------------
    # Run simulation for a given perturbation 
    # -------------------------------------------------------------------------------------
    # Get index of load8 active power in the MTK parameters
    #load8_name = SYSTEM == "6Bus" ? "load8₊P" : "sys0₊load8₊P"; # name of load8 bus in 0th instance
    load8_name = "sys0₊load8₊P"; # name of load8 bus in 0th instance
    P_idx = findfirst(name -> string(name) == load8_name, parameters(sys))

    # Define perturbation using a callback
    perturb_times = [1.0]
    condition(u, t, integrator) = t in perturb_times
    function load_decrease!(integrator) 
        integrator.p[1][P_idx] = 0.8  # 20% decrease in power
    end
    perturbation! = load_decrease!
    cb = DiscreteCallback(condition, perturbation!);

    # Run simulation
    @info @sprintf("Running solve(prob_ode, Rodas5P(), ...")
    @info @sprintf(" >> Rodas5P solve: INITIAL LIVE BYTES = %.1f MiB", get_live_bytes_mib(gc_before=true)); flush(logger.stream);
    t0 = time()
    sol = solve(prob_ode, Rodas5P(), callback=cb, tstops=perturb_times, dense=true, abstol=ABSTOL, reltol=RELTOL)
    @info @sprintf(" >> Rodas5P solve: FINAL LIVE BYTES = %.1f MiB", get_live_bytes_mib(gc_before=false))
    @info @sprintf(" >> Rodas5P solve: RUNTIME = %.2f sec", time() - t0); flush(logger.stream);

    # -----------------------------------------------------------------------------------------
    # Calculate eigenvalues
    # -----------------------------------------------------------------------------------------
    
    # NOTE: To get initial condition jacobian, you have to use the pre-perturbation 
    #  parameters because prod_ode.p will have changed in place
    @info @sprintf("Calculating eigs..."); flush(logger.stream);

    t0 = time()
    #A = prob_ode.f.jac(prob_ode.u0, prob_init_ode.p, 0.0)  # pre perturbation value
    A_fd = get_jacobian_evaluated_at_u0_forwarddiff(prob_ode, prob_init_ode.p)
    println(typeof(A_fd))
    #A = get_jacobian_evaluated_at_u0_symbolic(prob_ode, prod_init_ode.p)
    @info @sprintf(" >> Calculate A from jac (ForwardDiff): RUNTIME = %.2f sec", time() - t0); flush(logger.stream);

    # t0 = time()
    # #A = prob_ode.f.jac(prob_ode.u0, prob_init_ode.p, 0.0)  # pre perturbation value
    # #A = get_jacobian_evaluated_at_u0_forwarddiff(prob_ode, prod_init_ode.p)
    # A_sym = get_jacobian_evaluated_at_u0_symbolic(prob_ode, prob_init_ode.p)
    # println(typeof(A))
    # @info @sprintf(" >> Calculate A from jac (Symbolic): RUNTIME = %.2f sec", time() - t0); flush(logger.stream);

    # # Checking to see if ForwardDiff is good?
    # norm_diff = LinearAlgebra.opnorm(A_fd - A_sym, Inf)
    # @info @sprintf(" >> Inf norm of difference: %.4e", norm_diff); flush(logger.stream);

    A = A_fd

    t0 = time()
    eigenvalues = calculate_reduced_eigenvalues(A, diff_count, alg_count)
    @info @sprintf(" >> Calculate eigs from A: RUNTIME = %.2f sec", time() - t0)

    # -----------------------------------------------------------------------------------------
    # Save solution files for analysis
    # -----------------------------------------------------------------------------------------
    # Save results
    @info @sprintf("Saving solution..."); flush(logger.stream);
    @suppress save_object(joinpath(dirname(@__FILE__),"$(save_dir)/solution_$(SYSTEM)_$(GEN_MIX).jld2"), sol);

    # Save variable map for analysis
    @info @sprintf("Saving varmap..."); flush(logger.stream);
    varmap = make_var_to_index_map_mtk(sys)
    @suppress save_object(joinpath(dirname(@__FILE__),"$(save_dir)/varmap_$(SYSTEM)_$(GEN_MIX).jld2"), varmap);

    # Save eigenvalues
    @info @sprintf("Saving eigs..."); flush(logger.stream);
    @suppress save_object(joinpath(dirname(@__FILE__),"$(save_dir)/eigs_$(SYSTEM)_$(GEN_MIX).jld2"), eigenvalues);

end
#flush(stdout)

@info @sprintf("********* DONE *********"); flush(logger.stream);

end # logger

# -----------------------------------------------------------------------------------------
# Build DAEProblem from MTK model to use for simulations
# -----------------------------------------------------------------------------------------
# ****HAVE TO USE IDA IF I DO THIS, SO SWITCHED TO MASS MATRIX FORMAT****

# Grab dimensions of this system 
#diff_count = length(findall(x -> occursin("Differential(t)(", string(x)), equations(sys)));
#alg_count = length(findall(x -> occursin("0 ~ ", string(x)), equations(sys)));

# Build inputs
#tspan = (0.0, 30.0)
###du0_init = zeros(Float64,(diff_count + alg_count,1));
###differential_vars = collect(vcat(trues(diff_count), falses(alg_count)));

# Convert from MTK to DAEProblem
#prob_init = DAEProblem(sys, du0_init, u0_dict, tspan)

# Build problem to solve (need copy of params since we are perturbing params)
#prob_dae = DAEProblem(prob_init.f, prob_init.du0, prob_init.u0, tspan, copy(prob_init.p), differential_vars=differential_vars)

# SAME PERTURBATION 

# Run simulation
#sol = solve(prob_dae, IDA(), callback=cb, tstops=perturb_times, abstol=1e-6, reltol=1e-3) # abstol=1e-7, reltol=1e-4, saveat = 0.02, 
