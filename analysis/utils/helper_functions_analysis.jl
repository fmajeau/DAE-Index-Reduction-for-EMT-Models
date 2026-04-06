# -----------------------------------------------------------------------------------------
# Get list of 9bus instance indices in a system
# -----------------------------------------------------------------------------------------
function get_9bus_instances(SYSTEM)
    """
    Extracts a number from a string (e.g., "12Bus"), divides it by 6, and returns a 
    zero-indexed list of multiples of 6. Assumes a number is always present and is a 
    multiple of 6.
    """
    match_result = match(r"\d+", SYSTEM)
    num_buses = parse(Int, match_result.match)
    num_multiples = Int(num_buses / 6)
    return collect(0:(num_multiples - 1))
end

# -----------------------------------------------------------------------------------------
# Get map between Sienna and MTK variable names (only vars that are equal or related by a scalar)
# -----------------------------------------------------------------------------------------
function map_sienna_to_mtk(SYSTEM, map_sienna, map_mtk)
    # SYSTEM     -- "6Bus", "12Bus", etc
    # map_sienna -- Dict{String,Int64}() variable names => corresponding indices in simulation results
    # map_mtk    -- Dict{String,Int64}() variable names => corresponding indices in simulation results
    # s2m_all    -- Dict{String,String}() sienna var name => mtk var name (only those that are 1-1)

    # -----------------------------------------------------------------------------------------
    # Define some stuff. 
    # -----------------------------------------------------------------------------------------
    # Sienna bus number => MTK bus number 
    s2m_bus_numbers = Dict(
        "1"=>"4", 
        "2"=>"7", 
        "3"=>"9", 
        "5" =>"5", 
        "6"=>"6", 
        "8"=>"8"
        )

    # gen number in sienna => name of xfmr high side inductor
    s2m_gen_to_xfmr_hs = Dict(
        "1" => "4S", # (Bus)4 to S(hunt)
        "2" => "S7", # S(hunt) to (Bus)7 
        "3" => "9S", # (Bus)9 to S(hunt)
        )

    # Sienna inverter variable name => MTK inverter variable name
    s2m_inv_vars = Dict(
        "θ_oc" => "θoc",
        "p_oc" => "pm",
        "q_oc" => "qm",
        "ϕd_ic" => "ϕD",
        "ϕq_ic" => "ϕQ",
        "ξd_ic" => "ξD",
        "ξq_ic" => "ξQ",
        "γd_ic" => "γD",
        "γq_ic" => "γQ",
        "ir_cnv" => "icvd",
        "ii_cnv" => "icvq",
        "vr_filter" => "vd",
        "vi_filter" => "vq",
        "ir_filter" => "id",
        "ii_filter" => "iq",
        "ir_hs" => nothing,
        "ii_hs" => nothing,
        )

    get_9bus_instance(bus) = Int64(floor(parse(Int,bus)/10))

    # -----------------------------------------------------------------------------------------
    # LINES
    # -----------------------------------------------------------------------------------------
    pat = r"^Bus\s*(\d+)\s*-\s*Bus\s*(\d+)\s*-\s*i_1_Il_(I|R)$" # This DOES capture Bus 3, 13, etc)
    names_lines = [k for k in keys(map_sienna) if occursin(pat, k)]
    s2m_lines = Dict{String,String}()

    for s in names_lines
        p = match(pat, s)
        if p !== nothing
            # Get captured Sienna 
            from_s = p.captures[1]
            to_s = p.captures[2]
            type_s = p.captures[3]
            
            #Get instances  
            from_inst = get_9bus_instance(from_s)
            to_inst = get_9bus_instance(to_s)

            # Convert to MTK
            from_m = s2m_bus_numbers[last(from_s,1)]
            to_m = s2m_bus_numbers[last(to_s,1)]
            type_m = type_s == "I" ? "iq" : "id"

            # Build MTK name
            if from_inst == to_inst
                #if SYSTEM == "6Bus"
                #    m = "line$(from_m)$(to_m)_$(type_m)"
                #else
                m = "sys$(from_inst)_line$(from_m)$(to_m)_$(type_m)" # either from_inst or to_inst
                #end
            else
                m = "bridge$(from_inst)$(to_inst)_lineFT_$(type_m)"
            end
            # Check it exists, add to dict
            if m in keys(map_mtk)
                s2m_lines[s] = m
            end
        else
            @warn "didn’t match pattern" s
        end
    end

    # -----------------------------------------------------------------------------------------
    # BUSES
    # -----------------------------------------------------------------------------------------
    pat = r"^V_(\d+)_(R|I)$"
    names_buses = [k for k in keys(map_sienna) if occursin(pat, k)]
    s2m_buses = Dict{String,String}()

    for s in names_buses
        p = match(pat, s)
        if p !== nothing
            # Get captured Sienna 
            bus_s = p.captures[1]
            type_s = p.captures[2]

            # Convert to MTK 
            inst = get_9bus_instance(bus_s)
            bus_m = s2m_bus_numbers[last(bus_s,1)]
            type_m = type_s == "R" ? :vd : :vq

            # Build MTK name
            #if SYSTEM == "6Bus"
            #    m = "shunt$(bus_m)_$(type_m)"
            #else
            m = "sys$(inst)_shunt$(bus_m)_$(type_m)"
            #end
            # Check it exists, add to dict
            if m in keys(map_mtk)
                s2m_buses[s] = m
            end
        else
            @warn "didn’t match pattern" s
        end
    end

    # -----------------------------------------------------------------------------------------
    # SGs
    # -----------------------------------------------------------------------------------------
    pat = r"^generator-(\d*(1|3))-1_(.+)$"
    names_sgs = [k for k in keys(map_sienna) if occursin(pat, k)]
    s2m_sgs = Dict{String,String}()

    for s in names_sgs 
        p = match(pat, s)
        if p !== nothing
            # Get captured Sienna 
            bus = p.captures[1] # 1,3,11,13,21,23, etc
            gen = p.captures[2] # last digit of bus (1 or 3)
            var = p.captures[3] # e.g. "eq_p", "ed_p", etc

            # Build MTK name
            inst = get_9bus_instance(bus)
            #if SYSTEM == "6Bus"
            #    m = "gen$(gen)_$(var)"
            #else 
            m = "sys$(inst)_gen$(gen)_$(var)"
            #end
            # Check it exists, add to dict
            if m in keys(map_mtk)
                s2m_sgs[s] = m
            end
        else
            @warn "didn’t match pattern" s
        end
    end

    # -----------------------------------------------------------------------------------------
    # INVs
    # -----------------------------------------------------------------------------------------
    pat = r"^generator-(\d*(2))-1_(.+)$"
    names_invs = [k for k in keys(map_sienna) if occursin(pat, k)]
    s2m_invs = Dict{String,String}()

    for s in names_invs
        p = match(pat, s)
        if p !== nothing
            # Get captured Sienna 
            bus = p.captures[1] # 2,12,22, etc
            gen = p.captures[2]  # last digit of bus (2)
            var_s = p.captures[3]  # e.g. "eq_p", "ed_p", etc

            # Convert to MTK 
            inst = get_9bus_instance(bus)
            var_m = s2m_inv_vars[var_s]

            # Build MTK name
            #if SYSTEM == "6Bus"
            #    m = "gen$(gen)_$(var_m)"
            #else
            m = "sys$(inst)_gen$(gen)_$(var_m)"
            #end
            # Check it exists, add to dict
            if m in keys(map_mtk)
                s2m_invs[s] = m
            end
        else
            @warn "didn’t match pattern" s
        end
    end

    # -----------------------------------------------------------------------------------------
    # XFMRs
    # -----------------------------------------------------------------------------------------
    pat = r"^generator-(\d*(1|2|3))-1_(ir|ii)_hs$"
    names_xfmr = [k for k in keys(map_sienna) if occursin(pat, k)]
    s2m_xfmrs = Dict{String,String}()

    for s in names_xfmr
        p = match(pat, s)
        if p !== nothing
            # Get captured Sienna 
            bus = p.captures[1] # 1,2,3,11,12,13,21,22,23 etc
            gen = p.captures[2] # last digit of bus (1,2,3)
            type_s = p.captures[3]  # r or i

            # Convert to MTK 
            inst = get_9bus_instance(bus)
            type_m = type_s == "ir" ? "id" : "iq"
            xfmr_m = s2m_gen_to_xfmr_hs[gen]

            # Build MTK name
            #if SYSTEM == "6Bus"
            #    m = "xfmr$(xfmr_m)_$(type_m)"
            #else
            m = "sys$(inst)_xfmr$(xfmr_m)_$(type_m)"
            #end

            # Check it exists, add to dict
            if m in keys(map_mtk)
                s2m_xfmrs[s] = m

            end
        else
            @warn "didn’t match pattern" s
        end
    end

    # -----------------------------------------------------------------------------------------
    # Combine into one dict
    # -----------------------------------------------------------------------------------------
    s2m_all = merge(s2m_buses, s2m_lines, s2m_xfmrs, s2m_sgs, s2m_invs);

    # -----------------------------------------------------------------------------------------
    # Check what is missing on both sides 
    # -----------------------------------------------------------------------------------------
    s_unmapped = Dict{String,Any}();
    for s in keys(map_sienna)
        if !(s in keys(s2m_all))
            s_unmapped[s] = nothing
        end
    end
    m_unmapped = Dict{String,Any}()
    for m in keys(map_mtk)
        if !(m in values(s2m_all))
            m_unmapped[m] = nothing
        end
    end

    # We expect flux and ref delta to be unmapped
    #print_ordered_dict(s_unmapped);
    # We expect all 11 alg variables per system + 4 shunt currents per system 
    #print_ordered_dict(m_unmapped);

    return s2m_all
end