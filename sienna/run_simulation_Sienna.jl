# Set up the package environment
cd(@__DIR__)
using Pkg
Pkg.activate("..")

# Import packages
using PowerSystems
const PSY = PowerSystems
using PowerSimulationsDynamics
const PSID = PowerSimulationsDynamics
using OrdinaryDiffEq # Rodas5P()
using JLD2
using Suppressor
#using Logging # if you want to use console_level kwarg for Simulation! 

include("utils/helper_functions_Sienna.jl") 

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
# N_INSTANCES_ALL = [2]
# GEN_MIX = "2sg1inv"
# ABSTOL = 1e-7
# RELTOL = 1e-4

# -----------------------------------------------------------------------------------------
# Run all simulations
# -----------------------------------------------------------------------------------------
# Make directories for jld2 files (no effect if they already exists)
mkpath(joinpath(dirname(@__FILE__),"init_files"))
mkpath(joinpath(dirname(@__FILE__),"result_files"))

for N_INSTANCES in N_INSTANCES_ALL

    # -------------------------------------------------------------------------------------
    # DEFINE SYSTEM TO BUILD
    # -------------------------------------------------------------------------------------
    N_BUSES = 6*N_INSTANCES
    SYSTEM = "$(N_BUSES)Bus"
    println("--- Starting $(SYSTEM) ........"); flush(stdout);

    # -----------------------------------------------------------------------------------------
    # Load system
    # -----------------------------------------------------------------------------------------
    path = joinpath(dirname(@__FILE__), "json_files/$(SYSTEM)_$(GEN_MIX).json")
    sys = PSY.System(path, runchecks=false)
    println("Finished build of $(SYSTEM) from json"); flush(stdout);

    # -----------------------------------------------------------------------------------------
    # Select perturbation
    # -----------------------------------------------------------------------------------------
    load_device = PSY.get_component(StandardLoad, sys, "load81")
    perturbation = LoadChange(1.0, load_device, :P_ref_impedance, 0.8)  # P_ref 1.0 -> 0.8reduce P_ref to 0.8

    # -----------------------------------------------------------------------------------------
    # Build and run simulation
    # -----------------------------------------------------------------------------------------
    # Build simulation object
    sim = Simulation!(MassMatrixModel, sys, pwd(), (0.0, 30.0), perturbation) #; console_level=Logging.Info)
    println("Finished Simulation!"); flush(stdout);

    # Check small signal stability
    small_signal = PSID.small_signal_analysis(sim)
    println(small_signal); flush(stdout);

    # Run simulation
    t0 = time()
    execute!(sim, Rodas5P(), dense=true, abstol=ABSTOL, reltol=RELTOL)
    results = read_results(sim)
    println("Finished execute!")
    println("> solve time = $(time() - t0)"); flush(stdout);

    # -----------------------------------------------------------------------------------------
    # Save simulation files for MTK
    # -----------------------------------------------------------------------------------------
    # Save initial conditions
    x0_init_dict = build_initial_condition_dict_Sienna(sim)
    @suppress save_object(joinpath(dirname(@__FILE__),"init_files/x0_$(SYSTEM)_$(GEN_MIX).jld2"), x0_init_dict)

    # Save setpoints
    sp_init_dict = build_setpoints_dict_Sienna(sim)
    @suppress save_object(joinpath(dirname(@__FILE__),"init_files/sp_$(SYSTEM)_$(GEN_MIX).jld2"), sp_init_dict)
    
    # Save bridge lines
    bridges_init_dict = build_bridge_line_dict_Sienna(sys)
    @suppress save_object(joinpath(dirname(@__FILE__),"init_files/bridges_$(SYSTEM)_$(GEN_MIX).jld2"), bridges_init_dict)

    # -----------------------------------------------------------------------------------------
    # Save simulation files for debugging
    # -----------------------------------------------------------------------------------------
    # Save results 
    @suppress save_object(joinpath(dirname(@__FILE__),"result_files/solution_$(SYSTEM)_$(GEN_MIX).jld2"), results.solution)
    varmap = make_var_to_index_map_sienna(sim)
    @suppress save_object(joinpath(dirname(@__FILE__),"result_files/varmap_$(SYSTEM)_$(GEN_MIX).jld2"), varmap)

    # Save eigenvalues
    @suppress save_object(joinpath(dirname(@__FILE__),"result_files/eigs_$(SYSTEM)_$(GEN_MIX).jld2"), small_signal.eigenvalues)
    println("Saved all jld2 files"); flush(stdout);

end
