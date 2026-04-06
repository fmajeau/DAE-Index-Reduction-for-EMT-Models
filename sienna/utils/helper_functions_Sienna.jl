# -----------------------------------------------------------------------------------------
# Get 9bus instance based on bus number
# -----------------------------------------------------------------------------------------
function _get_9bus_instance(bus)
    return Int64(floor(bus/10))
end

# -----------------------------------------------------------------------------------------
# Build dict of Sienna simulation initial conditions to save
# -----------------------------------------------------------------------------------------
function build_initial_condition_dict_Sienna(sim)
    # Dict to return
    # NOTE: Format is identical to global map, but with values instead of indices
    x0_init_dict = Dict{String, Dict{Symbol, Float64}}()

    # Initial conditions in vector form and map to identify them
    x0_init_vec = PSID.get_initial_conditions(sim)
    x0_init_map = PSID.make_global_state_map(sim.inputs)

    # Build map between the voltage bus labels (which are based on indices) and the voltage bus names
    #   get_voltage_buses_ix sets the V_XX names - but it is returning the wrong set of buses!!
    #   https://github.com/NREL-Sienna/PowerSimulationsDynamics.jl/blob/4a2ff3d7098ab488174041ed6e18fb92076ab435/src/post_processing/post_proc_common.jl#L20
    #   get bus count is 18, then findall in get_DAE_vector
    #   https://github.com/NREL-Sienna/PowerSimulationsDynamics.jl/blob/4a2ff3d7098ab488174041ed6e18fb92076ab435/src/base/simulation_inputs.jl#L130
    diff_voltage_names_MTK = map(x -> "V_" * string(x), get_bus_numbers(sim.sys))
    diff_voltage_names_Sienna = map(x -> "V_" * string(x), 1:length(get_bus_numbers(sim.sys)))
    diff_voltage_names_Sienna_to_MTK = Dict(zip(diff_voltage_names_Sienna, diff_voltage_names_MTK)) # e.g. "V_9" => "V_9, "V_10" => "V_11"

    for (device_Sienna, states) in x0_init_map
        # A few exceptions where we want a different key
        if occursin("V_", device_Sienna)
            # Sienna names the voltages buses based on V_{index}, while MTK expects V_{bus_name}
            #   Sienna: V_1-V_9, V_10-V_18, ...
            #   MTK:    V_1-V_9, V_11-V_19, ... (to match orig raw file and make the 9bus blocks obvious)
            device = diff_voltage_names_Sienna_to_MTK[device_Sienna]
        elseif occursin("generator-3-Trip", device_Sienna)
            # The raw file was from a paper that used this "Trip" label. We don't need it for this paper.
            device = "generator-3-1"
        else
            device = device_Sienna 
        end

        # Add the initial conditions to the dict
        x0_init_dict[device] = Dict{Symbol, Float64}()
        for (name,index) in states
            x0_init_dict[device][name] = x0_init_vec[index]
        end 
    end

    return x0_init_dict
end

# -----------------------------------------------------------------------------------------
# Build dict of Sienna simulation set points to save
# -----------------------------------------------------------------------------------------
function build_setpoints_dict_Sienna(sim)

    # Get setpoints that have already been calculated, we will add to this.
    sp_init_dict = get_setpoints(sim) 

    for g in PSY.get_components(PSY.Generator, sim.sys)
        # Add base power values
        sp_init_dict[get_name(g)]["Sb_gen"] = get_base_power(g)
        # Add τm0 for each DynamicGenerator with TGFixed
        di = get_dynamic_injector(g)        
        if occursin("DynamicGenerator", string(typeof(di)))            
            tgov = get_prime_mover(di)
            τm0 = get_P_ref(tgov) * get_efficiency(tgov) # see PSID: src/models/generator_models/tg_models.jl#L86
            if typeof(tgov) == TGFixed
                sp_init_dict[get_name(g)]["τm0"] = τm0 
            else
                error("Turbine Gov is not TGFixed... τm0 setpoint is only available for TGFixed.")
            end
        end
    end

    # Replace "generator-3-Trip" with "generator-3-1"
    # (`Trip` was for analysis in the original paper)
    if haskey(sp_init_dict, "generator-3-Trip")
        sp_init_dict["generator-3-1"] = sp_init_dict["generator-3-Trip"]
        delete!(sp_init_dict, "generator-3-Trip")
    end
    
    return sp_init_dict
end

# -----------------------------------------------------------------------------------------
# Build dict of Sienna bridge lines to save
# -----------------------------------------------------------------------------------------
function build_bridge_line_dict_Sienna(sys)
    # Example
    # :bridge01 => Dict(
    #    from_inst => 0, to_inst => 0, 
    #    from_bus => 5, to_bus  => 5, 
    #    sienna => get_name(i)
    #    )
    bridge_dict = Dict{Symbol, Dict{Symbol,Union{Int64,String}}}()
    for i in get_components(DynamicBranch,sys)
        from_bus_sys = get_number(get_from(get_arc(i))) # number in full system, e.g. 15
        to_bus_sys = get_number(get_to(get_arc(i)))     # number in full system, e.g. 25
        from_instance = _get_9bus_instance(from_bus_sys) # subsystem instance, e.g. 1
        to_instance = _get_9bus_instance(to_bus_sys)     # subsystem instance, e.g. 2
        from_bus = from_bus_sys % 10                    # number in subsystem, e.g. 5
        to_bus = to_bus_sys % 10                        # number in subsystem, e.g. 5
        if from_instance != to_instance
            key = Symbol("bridge", from_instance, to_instance)
            value = Dict{Symbol,Union{Int64,String}}(
                :from_inst => from_instance,
                :to_inst => to_instance,
                :from_bus => from_bus,
                :to_bus => to_bus,
                :sienna_name => get_name(i),
            )
            bridge_dict[key] = value
            #println("$(rpad(get_name(i),19)) | R = $(get_r(i)) | X = $(get_x(i)) | B = $(get_b(i)) --- $(from_instance) to $(to_instance)")
        end
    end
    return bridge_dict
end

# -----------------------------------------------------------------------------------------
# Build dict of sienna names and state indices
# -----------------------------------------------------------------------------------------
function make_var_to_index_map_sienna(sim)
    # Dict to return
    # NOTE: Format is identical to global map, but with values instead of indices
    state_map_collapsed = Dict{String, Int64}()

    # Initial conditions in vector form and map to identify them
    state_map = PSID.make_global_state_map(sim.inputs)

    # Build map between the voltage bus labels (which are based on indices) and the voltage bus names
    #   get_voltage_buses_ix sets the V_XX names - but it is returning the wrong set of buses!!
    #   https://github.com/NREL-Sienna/PowerSimulationsDynamics.jl/blob/4a2ff3d7098ab488174041ed6e18fb92076ab435/src/post_processing/post_proc_common.jl#L20
    #   get bus count is 18, then findall in get_DAE_vector
    #   https://github.com/NREL-Sienna/PowerSimulationsDynamics.jl/blob/4a2ff3d7098ab488174041ed6e18fb92076ab435/src/base/simulation_inputs.jl#L130
    diff_voltage_names_MTK = map(x -> "V_" * string(x), get_bus_numbers(sim.sys))
    diff_voltage_names_Sienna = map(x -> "V_" * string(x), 1:length(get_bus_numbers(sim.sys)))
    diff_voltage_names_Sienna_to_MTK = Dict(zip(diff_voltage_names_Sienna, diff_voltage_names_MTK)) # e.g. "V_9" => "V_9, "V_10" => "V_11"

    for (device_Sienna, states) in state_map
        # A few exceptions where we want a different key
        if occursin("V_", device_Sienna)
            # Sienna names the voltages buses based on V_{index}, while MTK expects V_{bus_name}
            #   Sienna: V_1-V_9, V_10-V_18, ...
            #   MTK:    V_1-V_9, V_11-V_19, ... (to match orig raw file and make the 9bus blocks obvious)
            device = diff_voltage_names_Sienna_to_MTK[device_Sienna]
        elseif occursin("generator-3-Trip", device_Sienna)
            # The raw file was from a paper that used this "Trip" label. We don't need it for this paper.
            device = "generator-3-1"
        else
            device = device_Sienna 
        end

        # Collapse 
        for (name,index) in states
            key = device*"_"*string(name)
            state_map_collapsed[key] = index
        end 
    end

    return state_map_collapsed
end
