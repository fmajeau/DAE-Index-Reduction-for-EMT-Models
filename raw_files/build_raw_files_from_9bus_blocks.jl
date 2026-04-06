cd(@__DIR__)
using Pkg
Pkg.activate("..")

using Graphs
using Printf
using Random

# -----------------------------------------------------------------------------------------
# Define functions
# -----------------------------------------------------------------------------------------

# Get the global load bus numbers for a given 9Bus instance
function _get_global_load_buses(instance::Int)
    load_buses_local = [5,6,8]
    load_buses_global = ((instance - 1)*10) .+ load_buses_local
    return load_buses_global
end 

# Build a random undirected cycle graph of size n
# - Degree of every node will be exactly two (undirected cycle)
# - Node list is randomly permuted and edges are added consecutively
function _build_random_cycle_graph(n::Int)
    @assert n >= 1 "Cannot make a graph with $(n) nodes"
    G = SimpleGraph(n) # undirected
    if n == 2
        # Cannot have a simple undirected cycle with two nodes
        # Just connect the two nodes with single line
        add_edge!(G, 1, 2)
    elseif n > 2
        # Generate a random permutation of vertices 1 thru n
        p = randperm(n)
        # Add edges between consecutive vertices in the permutation
        for i in 1:(n-1)
            add_edge!(G, p[i], p[i+1])
        end
        # Close the cycle
        add_edge!(G, p[n], p[1])
    end
    return G
end

# Get branches (from_bus, to_bus) to connect 9Bus instances
function get_new_branches(n_instances::Int, selection_method::Function)

    @assert selection_method in [minimum, rand] "Selection method $(selection_method) not recognized"

    # Generate a graph where each node is connected to exactly two other nodes and the 
    # connections are randomly placed. Each node represents a 9Bus instance.
    # NOTE: if n=2, the two nodes will just be connected by a single line
    g = _build_random_cycle_graph(n_instances)

    # Each node is a 9Bus instance, so to connect them we must select a bus on either end 
    # of each edge  e.g. if an edge exists between 9Bus_instance1 and 9Bus_instance3, we must 
    # select a bus in {5,6,8} and a bus in {35,36,38} to place a branch
    used_buses = []
    new_branches = Vector{Tuple{Int64, Int64}}()
    for edge in edges(g)
        # Get the from and to instances (1 indexed)
        from_instance = src(edge)          # 1 indexed
        to_instance = dst(edge)            # 1 indexed

        # Define from and to bus options
        from_bus_options = _get_global_load_buses(from_instance)
        to_bus_options = _get_global_load_buses(to_instance)

        # Choose randomly from remaining available options
        # (We only want one instance-connecting line per load node)
        from_bus = minimum(setdiff(from_bus_options, used_buses)) # TODO: could set back to rand?
        to_bus = minimum(setdiff(to_bus_options, used_buses))     # TODO: could set back to rand?
        push!(used_buses, from_bus, to_bus) # keep track of what buses we have used, use max of 1 time
        push!(new_branches, (from_bus, to_bus))
    end

    return new_branches

end

# Build raw file with (9*n_instances) buses by connecting 9Bus instances
function build_raw_file_9n_from_9(n_instances::Int, extra_branch_pairs::Vector{Tuple{Int, Int}}, input_file::String, output_file::String)
    if n_instances == 1
        # Return early because no point in building 9Bus from 9Bus
        return
    end

    #input_file  = joinpath(dirname(@__FILE__), "../raw_files/9Bus.raw")
    increment       = 10  # fixed increment
    #total_buses     = n_instances * 9
    #output_file = joinpath(dirname(@__FILE__), "raw_files_9n/$(9*n_instances)Bus.raw")

    lines = readlines(input_file)

    # Regex patterns for various sections
    bus_r    = r"^\s*(\d+)\s*,\s*'Bus\s*([0-9]+)'\s*,\s*([^,]+)\s*,\s*(\d+)\s*,(.*)$"
    load_r   = r"^\s*(\d+)\s*,(.*)$"
    gen_r    = r"^\s*(\d+)\s*,(.*)$"
    branch_r = r"^\s*(\d+)\s*,\s*(\d+)\s*,(.*)$"
    # Transformer first‐line: from, to
    xf_first_r = r"^\s*(\d+)\s*,\s*(\d+)\s*,(.*)$"
    # Transformer subsequent lines: no indentation (or less indentation)
    xf_subsequent_r = r"^\s*\S.*$"  # able to detect non‑indented lines

    # Storage for each section
    bus_lines     = String[]
    load_lines    = String[]
    gen_lines     = String[]
    branch_lines  = String[]
    xf_blocks     = Vector{Vector{String}}()

    other_pre     = String[]  # up to end of bus
    other_mid1    = String[]  # load section
    other_mid2    = String[]  # generator section
    other_mid3    = String[]  # branch section
    other_mid4    = String[]  # transformer section data (including blocks)
    other_post    = String[]  # after transformer

    # flags
    saw_end_bus    = false
    saw_end_load   = false
    saw_end_gen    = false
    saw_end_branch = false
    saw_end_xf     = false

    # First we separate and gather blocks for transformer section
    current_block = String[]

    for line in lines
        stripped = strip(line)
        if !saw_end_bus
            if startswith(stripped, "0 / END OF BUS DATA")
                saw_end_bus = true
                push!(other_pre, line)
            else
                if occursin(bus_r, line)
                    push!(bus_lines, line)
                end
                push!(other_pre, line)
            end

        elseif saw_end_bus && !saw_end_load
            if startswith(stripped, "0 / END OF LOAD DATA")
                saw_end_load = true
                push!(other_mid1, line)
            else
                if occursin(load_r, line)
                    push!(load_lines, line)
                end
                push!(other_mid1, line)
            end

        elseif saw_end_load && !saw_end_gen
            if startswith(stripped, "0 / END OF GENERATOR DATA, BEGIN BRANCH DATA")
                saw_end_gen = true
                push!(other_mid2, line)
            else
                if occursin(gen_r, line)
                    push!(gen_lines, line)
                end
                push!(other_mid2, line)
            end

        elseif saw_end_gen && !saw_end_branch
            if startswith(stripped, "0 / END OF BRANCH DATA, BEGIN TRANSFORMER DATA")
                saw_end_branch = true
                push!(other_mid3, line)
            else
                if occursin(branch_r, line)
                    push!(branch_lines, line)
                end
                push!(other_mid3, line)
            end

        elseif saw_end_branch && !saw_end_xf
            # inside transformer section
            if startswith(stripped, "0 / END OF TRANSFORMER DATA, BEGIN AREA DATA")
                # end of transformer section
                saw_end_xf = true
                # if currently building a block, push it
                if !isempty(current_block)
                    push!(xf_blocks, copy(current_block))
                    empty!(current_block)
                end
                push!(other_mid4, line)  # the marker
            else
                # if line matches first line of block
                if occursin(xf_first_r, line)
                    # if we had a current_block in progress, push it
                    if !isempty(current_block)
                        push!(xf_blocks, copy(current_block))
                    end
                    # start new block
                    current_block = String[line]
                else
                    # this is a subsequent line belonging to the current transformer
                    push!(current_block, line)
                end
                push!(other_mid4, line)
            end

        else
            push!(other_post, line)
        end
    end

    # Duplicate Bus section as before
    # After parsing sections, in the bus duplication logic we adjust 4th field for duplicates of Bus1:
    new_bus_lines = String[]
    for inst in 1:(n_instances-1)
        for line in bus_lines
            m = match(bus_r, line)
            if m === nothing
                continue
            end
            old_busnum      = parse(Int, m.captures[1])
            old_busname_int = parse(Int, m.captures[2])
            field3          = m.captures[3]
            field4_orig     = m.captures[4]
            rest_fields     = m.captures[5]

            # Determine new 1st & 2nd fields:
            new_busnum      = old_busnum      + inst * increment
            new_busname_int = old_busname_int + inst * increment

            # Determine new 4th field:
            new_field4      = field4_orig
            if old_busnum == 1 && inst >= 1
                # This is a duplicate of Bus1 (Bus11, Bus21, …)
                new_field4 = "2"
            end

            # Build new line:
            new_line = @sprintf("    %d,'Bus %d',%s,%s,%s",
                                new_busnum, new_busname_int, field3, new_field4, rest_fields)
            push!(new_bus_lines, new_line)
        end
    end

    # Duplicate Load section
    new_load_lines = String[]
    for inst in 1:(n_instances-1)
        for line in load_lines
            m = match(load_r, line)
            if m === nothing
                continue
            end
            old_loadbusnum = parse(Int, m.captures[1])
            rest_line      = m.captures[2]

            # Determine new 1st field:
            new_loadbusnum = old_loadbusnum + inst * increment
            new_line       = @sprintf("    %d,%s", new_loadbusnum, rest_line)
            push!(new_load_lines, new_line)
        end
    end

    # Duplicate Generator section
    new_gen_lines = String[]
    for inst in 1:(n_instances-1)
        for line in gen_lines
            m = match(gen_r, line)
            if m === nothing
                continue
            end
            old_genbusnum = parse(Int, m.captures[1])
            rest_line     = m.captures[2]

            # Determine new 1st field:
            new_genbusnum = old_genbusnum + inst * increment
            new_line      = @sprintf("    %d,%s", new_genbusnum, rest_line)
            push!(new_gen_lines, new_line)
        end
    end

    # Duplicate Branch section
    new_branch_lines = String[]
    for inst in 1:(n_instances-1)
        for line in branch_lines
            m = match(branch_r, line)
            if m === nothing
                continue
            end
            old_frombus = parse(Int, m.captures[1])
            old_tobus   = parse(Int, m.captures[2])
            rest_line   = m.captures[3]

            # Determine new 1st & 2nd field:
            new_frombus = old_frombus + inst * increment
            new_tobus   = old_tobus   + inst * increment

            new_line    = @sprintf("    %d,    %d,%s", new_frombus, new_tobus, rest_line)
            push!(new_branch_lines, new_line)
        end
    end

    # Find the “template” branch row for (7,8)
    template_rest = nothing
    for line in branch_lines
        m = match(branch_r, line)  # branch_r = r"^\s*(\d+)\s*,\s*(\d+)\s*,(.*)$"
        if m !== nothing
            if parse(Int, m.captures[1]) == 7 && parse(Int, m.captures[2]) == 8
                template_rest = m.captures[3]
                break
            end
        end
    end
    if template_rest === nothing
        error("Base branch row 7,8 not found in branch_lines")
    end

    # Now for each extra pair, build a new branch row
    for (from_bus, to_bus) in extra_branch_pairs
        # Build the new line
        new_line = @sprintf("    %d,    %d,%s", from_bus, to_bus, template_rest)
        push!(new_branch_lines, new_line)
    end

    # Duplicate Transformer section (blocks)
    new_xf_blocks = Vector{Vector{String}}()
    for inst in 1:(n_instances-1)
        for block in xf_blocks
            # first line of block
            first_line = block[1]
            m = match(xf_first_r, first_line)
            if m === nothing
                continue
            end
            old_frombus = parse(Int, m.captures[1])
            old_tobus   = parse(Int, m.captures[2])
            rest_first  = m.captures[3]

            # Determine new 1st & 2nd field:
            new_frombus = old_frombus + inst * increment
            new_tobus   = old_tobus   + inst * increment

            new_first_line = @sprintf("    %d,    %d,%s", new_frombus, new_tobus, rest_first)

            # construct new block
            new_block = [new_first_line]  # changes to first line of each
            for subline in block[2:end]
                push!(new_block, subline) # no changes to the remaining lines
            end
            push!(new_xf_blocks, new_block)
        end
    end

    # Write out file
    open(output_file, "w") do io
        # Bus section
        for line in other_pre
            if startswith(strip(line), "0 / END OF BUS DATA")
                for nl in new_bus_lines
                    println(io, nl)
                end
                println(io, line)
            else
                println(io, line)
            end
        end

        # Load section
        for line in other_mid1
            if startswith(strip(line), "0 / END OF LOAD DATA")
                for nl in new_load_lines
                    println(io, nl)
                end
                println(io, line)
            else
                println(io, line)
            end
        end

        # Generator section
        for line in other_mid2
            if startswith(strip(line), "0 / END OF GENERATOR DATA, BEGIN BRANCH DATA")
                for nl in new_gen_lines
                    println(io, nl)
                end
                println(io, line)
            else
                println(io, line)
            end
        end

        # Branch section
        for line in other_mid3
            if startswith(strip(line), "0 / END OF BRANCH DATA, BEGIN TRANSFORMER DATA")
                for nl in new_branch_lines
                    println(io, nl)
                end
                println(io, line)
            else
                println(io, line)
            end
        end

        # Transformer section
        for line in other_mid4
            if startswith(strip(line), "0 / END OF TRANSFORMER DATA, BEGIN AREA DATA")
                # insert all new transformer blocks
                for block in new_xf_blocks
                    for bl in block
                        println(io, bl)
                    end
                end
                println(io, line)
            else
                println(io, line)
            end
        end

        # After
        for line in other_post
            println(io, line)
        end
    end

    println(@sprintf("Wrote %4d Bus system (%3d instances) to %s.", 9*n_instances, n_instances, output_file))
    return output_file
end

# Convert raw file build from instances of 9Bus into raw file build from instances of 6Bus
function build_raw_file_6n_from_9n(n_instances::Int, input_path::String, output_file::String)
    #= More details:
    The 6Bus system removes the transformers by:
    - Renaming any 4,7,9 numbers to 1,2,3
    - Removing transformer data 
    - Setting voltage of 1,2,3 to be same as network, since we are adding a dynamic model that handles the voltage.
    - Set voltage angle of Bus1 (slack) to 0
    As a result,
    - 1->4 is now just 1, and 1 is located where 4 was located
    - 2->7 is now just 2, and 2 is located where 7 was located 
    - 3->9 is now just 3, and 3 is located where 9 was located
    - Any line that connected to 4, now connects to 1. 
    - Any line that connected to 7, now connects to 2. 
    - Any line that connected to 9, now connects to 3. 
    =#
    remap = Dict(4=>1, 7=>2, 9=>3)
    open(input_path) do fin
        open(output_file, "w") do fout
            section = "BUS" # starting section
            bus_lines = String[] # Need to collect them first because they have to be sorted
            for line in eachline(fin)
                if occursin("END",line)
                    section = "OTHER"
                    if occursin("BUS DATA", line)
                        #sort_and_write!(bus_lines, fout)
                        # Sort buses by first field and write to output file
                        sorted = sort(bus_lines, by = line -> parse(Int, split(line, ",")[1]))
                        for l in sorted
                            println(fout, l)
                        end
                    end
                end

                if occursin("BEGIN BRANCH DATA", line)
                    section = "BRANCH"
                elseif occursin("BEGIN TRANSFORMER DATA", line)
                    section = "TRANSFORMER"
                    println(fout, line)  # keep boundary line
                    continue
                end

                if section == "TRANSFORMER"
                    # skip everything inside transformer section
                    continue
                end

                if section == "BUS"
                    stripped = strip(line)
                    # Keep comments or boundaries
                    if isempty(stripped) || occursin("/", stripped)
                        println(fout, line)
                        continue
                    end
                    # Split line into comma separated parts
                    parts = split(line, ',')
                    # Get bus number in full system and in original 9Bus system
                    bus_sys = parse(Int, strip(parts[1]))
                    bus_base = bus_sys % 10
                    # Rename if the base bus number is 4,7,9
                    if haskey(remap, bus_base)
                        # FIRST FIELD
                        bus_base_new = remap[bus_base]
                        bus_sys_new = bus_sys - bus_base + bus_base_new
                        parts[1] = "    "*string(bus_sys_new)
                        # SECOND FIELD
                        parts[2] = string("\'Bus $(bus_sys_new)\'")
                        # FOURTH FIELD 
                        if bus_sys_new == 1 
                            parts[2] = string("\'Bus$(bus_sys_new)\'") # no space for some reason
                            parts[4] = "3" # slack bus
                            parts[9] = "   0.0000"
                        else 
                            parts[4] = "2" # pv bus
                        end
                        #println(join(parts, ","))
                        push!(bus_lines, join(parts, ","))
                        continue
                    elseif bus_base in values(remap)
                        # Skip the lines that were base 1,2,3 since we just replaced them 
                        continue
                    else
                        # Keep all other buses as is (i.e. load buses)
                        #println(fout, line)
                        push!(bus_lines, line)
                        continue
                    end
                end

                if section == "BRANCH"
                    stripped = strip(line)
                    # Keep comments or boundaries
                    if isempty(stripped) || occursin("/", stripped)
                        println(fout, line)
                        continue
                    end
                    # Split line into comma separated parts
                    parts = split(line, ',')
                    for idx in (1,2)
                        bus_sys = parse(Int, strip(parts[idx])) # 3,13,23,43,53,
                        bus_base = bus_sys % 10 # e.g. 3
                        if haskey(remap, bus_base)
                            bus_base_new = remap[bus_base]
                            bus_sys_new = bus_sys - bus_base + bus_base_new
                            parts[idx] = "    $(bus_sys_new)"
                        end
                    end
                    println(fout, join(parts, ","))
                    continue
                end
                # other sections: pass through
                println(fout, line)
            end
        end
    end
    println(@sprintf("Wrote %4d Bus system (%3d instances) to %s.", 6*n_instances, n_instances, output_file))
end

# -----------------------------------------------------------------------------------------
# Build raw files
# -----------------------------------------------------------------------------------------

# Define list of raw files to build, in terms of the number of 9Bus instances
#n_instances_all = 2 .^ collect(0:7) # For VSCode
n_instances_all = [parse(Int, i) for i in split(string(ARGS[1]), ',')] # "1,2,4" => [1,2,4]

# Define 9Bus building block
filename_raw_9  = joinpath(dirname(@__FILE__), "raw_files_9n/9Bus.raw")

# Build raw files (this will replace existing files if they already exist)
for n_instances in n_instances_all

    # Get branches (from_bus,to_bus) to connect the 9Bus instances
    new_branches = get_new_branches(n_instances, rand)

    # Build raw file with (9*n_instances) buses by connecting 9Bus instances
    filename_raw_9n = joinpath(dirname(@__FILE__), "raw_files_9n/$(9*n_instances)Bus.raw")
    build_raw_file_9n_from_9(n_instances, new_branches, filename_raw_9, filename_raw_9n)

    # Build raw file with (6*n_instances) buses from (9*n_instances) raw file
    # NOTE: This collapses the step-up transformer behind the gen bus which was the easiest
    # way to implement index reduction in Sienna while retaining powerflow functionality
    # Example:
    #   (gnd)--gen--(1)--xfmr--(4)    ==>    (gnd)--gen--xfmr--(1)
    #   (gnd)--gen--(2)--xfmr--(7)    ==>    (gnd)--gen--xfmr--(2)
    #   (gnd)--gen--(3)--xfmr--(9)    ==>    (gnd)--gen--xfmr--(3)
    filename_raw_6n  = joinpath(dirname(@__FILE__), "raw_files_6n/$(6*n_instances)Bus.raw")
    raw_file_6n = build_raw_file_6n_from_9n(n_instances, filename_raw_9n, filename_raw_6n)

end

# Raw file 9Bus instance concept was based on these:
# Reference paper - https://www.sciencedirect.com/science/article/pii/S0378779622006587#b21 
# Raw File Options - https://github.com/Energy-MAC/CTESN_PSCC/blob/main/src/models/psse_files