# Set up the package environment
cd(@__DIR__)
using Pkg
Pkg.activate("../..")

# Import packages
using PowerSystems
const PSY = PowerSystems
using PowerSimulationsDynamics
const PSID = PowerSimulationsDynamics

# Include script with DynamicGeneratorComponent definitions we will use as building blocks
include(joinpath(dirname(@__FILE__), "ComponentDefinitions_Sienna.jl"))

# -----------------------------------------------------------------------------------------
# PARSE ARGS
# -----------------------------------------------------------------------------------------
@assert length(ARGS) == 2 "Provide N_INSTANCES as 1st arg, GEN_MIX as 2nd arg"
N_INSTANCES_ALL = [parse(Int, i) for i in split(string(ARGS[1]), ',')] # e.g. [1,2,4]
GEN_MIX = ARGS[2] # e.g. "2sg1inv"  
@assert GEN_MIX == "2sg1inv" "Only set up for GEN_MIX=\"2sg1inv\" at the moment"

# For VSCode
#N_INSTANCES_ALL = [2]
#GEN_MIX = "2sg1inv"

# -----------------------------------------------------------------------------------------
# DEFINE GENERATOR MODELS
# -----------------------------------------------------------------------------------------
# Define dynamic generator that you will add to this model 
function dyn_gen_sauerpai(generator)
    return PSY.DynamicGenerator(;
        name = get_name(generator), #static generator
        ω_ref = 1.0, # [pu]
        machine = machine_sauerpai(),
        shaft = shaft_damping(),
        avr = avr_type1(),
        prime_mover = tg_none(),
        pss = pss_none(),
    )
end

# Define dynamic inverter to add to new static inverter
function dyn_gen_inverter(inverter)
    return PSY.DynamicInverter(;
        name = get_name(inverter), #static inverter
        ω_ref = 1.0, # [pu]
        converter = converter_high_power(),
        outer_control = outer_control_droop(),
        inner_control = inner_control(),
        dc_source = dc_source_lv(),
        freq_estimator = no_pll(), #reduced_pll(),
        filter = filter_lcl(),
        base_power = 250.0, # [MVA] 
        )
end

# Swap out an existing dynamic generator with an inverter
function replace_gen_with_inv!(system, name)
    gen_static = get_component(ThermalStandard, system, name)
    PSY.remove_component!(sys, get_dynamic_injector(gen_static))
    inv_dynamic = dyn_gen_inverter(gen_static)
    PSY.add_component!(sys, inv_dynamic, gen_static)
end

# -----------------------------------------------------------------------------------------
# LOOP THROUGH INSTANCES AND CREATE ALL JSON FILES
# -----------------------------------------------------------------------------------------
# Make directory for json files (no effect if it already exists)
mkpath(joinpath(dirname(@__FILE__),"../json_files"))

for N_INSTANCES in N_INSTANCES_ALL

    # -------------------------------------------------------------------------------------
    # DEFINE SYSTEM TO BUILD
    # -------------------------------------------------------------------------------------
    N_BUSES = 6*N_INSTANCES
    SYSTEM = "$(N_BUSES)Bus"

    # -------------------------------------------------------------------------------------
    # BUILD SYSTEM
    # -------------------------------------------------------------------------------------
    file_dir = joinpath(dirname(@__FILE__), "../../raw_files/raw_files_6n/$(SYSTEM).raw")
    global sys = System(file_dir; runchecks = false)

    # -------------------------------------------------------------------------------------
    # MAKE CHANGES TO NETWORK
    # -------------------------------------------------------------------------------------
    # Convert constant power loads to constant impedance loads
    for l in PSY.get_components(PSY.StandardLoad, sys)
        PSID.transform_load_to_constant_impedance(l)
    end

    # Convert all static lines to dynamic lines
    for i in PSY.get_components(PSY.Line, sys)
        dyn_branch = DynamicBranch(i)
        PSY.add_component!(sys, dyn_branch)
    end

    # Check that this is what you expect
    #show_components(sys, Line)
    #show_components(sys, Transformer2W)
    #show_components(sys, DynamicBranch, [:n_states, :states])

    # -------------------------------------------------------------------------------------
    # ADD DYNAMIC GENERATORS
    # -------------------------------------------------------------------------------------
    # Add Sauer Pai dynamic SGs to each generator bus
    # TODO: this adds three identical dynamic gens, consider making the params different?
    #  (Can't use S&P values because not the same machine)
    for g in PSY.get_components(PSY.Generator, sys)
        case_gen = dyn_gen_sauerpai(g)
        PSY.add_component!(sys, case_gen, g)
        println("Adding DynamicGenerator @ $(get_name(g))")
    end

    # If desired, replace the SG dynamic injector at each "generator-X2-1" with a GFM
    if GEN_MIX == "2sg1inv"
        for i in get_components(ThermalStandard,sys)
            gen_name = get_name(i)
            if occursin("2-1", gen_name)  # Bus 2 in the original 9bus system
                println("Replacing DynamicGenerator with DynamicInverter @ $(gen_name)")
                replace_gen_with_inv!(sys, gen_name)
            end
        end
    end

    # Check that this is what you expect
    #show_components(sys,PSY.ThermalStandard, [:dynamic_injector])

    # -------------------------------------------------------------------------------------
    # SAVE MODEL
    # -------------------------------------------------------------------------------------
    path = joinpath(dirname(@__FILE__), "../json_files/$(SYSTEM)_$(GEN_MIX).json")
    to_json(sys, path, force=true)

end


# References: I implemented this similarly to other PSID test scripts:
# Sys building blocks: https://github.com/NREL-Sienna/PowerSimulationsDynamics.jl/blob/main/test/data_tests/dynamic_test_data.jl
# Script to build sys: https://github.com/NREL-Sienna/PowerSimulationsDynamics.jl/blob/main/test/data_tests/test45.jl
# Script to test sys: https://github.com/NREL-Sienna/PowerSimulationsDynamics.jl/blob/main/test/test_case45_sauerpai.jl
