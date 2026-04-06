# Set up the package environment
cd(@__DIR__)
using Pkg
Pkg.activate("..")

ENV["GKSwstype"] = "100" # non-interactive headless mode for plots on cluster

# Import packages
using JLD2
using Plots
using Plots.PlotMeasures
using Printf
using Suppressor
using Statistics
pgfplotsx()

# NOTE: can be run independently as long as there are performance files in analysis/result_files.

# This script uses the following
#   performance_files_build/performance_build_MTK_
#   performance_files_build/performance_build_Sienna_
#   performance_files_solve/performance_solve_MTK_
#   performance_files_solve/performance_solve_Sienna
# to create
#   performance_plots/plot_performance_malloc.pdf
#   performance_plots/plot_performance_maxrss.pdf
#   performance_plots/plot_performance_runtime.pdf 

# -----------------------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------------------
# @assert length(ARGS) == 2 "Provide N_INSTANCES as 1st arg, GEN_MIX as 2nd arg"
# N_INSTANCES_ALL = [parse(Int, i) for i in split(string(ARGS[1]), ',')] # e.g. [1,2,4]
# GEN_MIX = ARGS[2] # e.g. "2sg1inv"  
# @assert GEN_MIX == "2sg1inv" "Only set up for GEN_MIX=\"2sg1inv\" at the moment"

# For VSCode
N_INSTANCES_ALL = [1,2,4,8,16,32,64,128]
GEN_MIX = "2sg1inv"

# -----------------------------------------------------------------------------------------
# Make all figures
# -----------------------------------------------------------------------------------------
# Make directory for plots (no effect if they already exists)
build_dir = "performance_files_build"
solve_dir = "performance_files_solve"
plot_dir = "performance_plots" 
mkpath(joinpath(dirname(@__FILE__),"$(plot_dir)"))


default(fontfamily="Computer Modern", 
    titlefont=18, legendfontsize=14, guidefont=16, 
    xtickfontsize = 10, ytickfontsize = 10,
    #size=(700, 400),
    size=(700, 360),
    markers = :utriangle,
    markersize = 7,
    linewidth = 2,
    dpi = 1200,
    #margin=1mm,
    titlefontcolor = :black,
    legendfontcolor = :black,
    tickfontcolor = :black,
    guidefontcolor = :black,
    legendfonthalign=:left,
    )

# -----------------------------------------------------------------------------------------
# Prepare Data
# -----------------------------------------------------------------------------------------

# Computes average value of a specified performance metric excluding the first run
function avg_excluding_first(inner::Dict, field::Symbol)
    # Sort runs by key
    sorted_runs = sort(collect(inner))  # gives Array of (run_key, tuple)
    # Drop the compile-heavy first run
    runs_to_average = sorted_runs[2:end]
    # Get values from desired field
    vals_to_average = [val[field] for (_run, val) in runs_to_average]
    return mean(vals_to_average)
end

function avg_excluding_first_multi(inner_set::Vector{Dict{Any, Any}}, field::Symbol)
    vals_to_average_all = []
    for inner in inner_set
        # Sort runs by key
        sorted_runs = sort(collect(inner))  # gives Array of (run_key, tuple)
        # Drop the compile-heavy first run
        runs_to_average = sorted_runs[2:end]
        #println(length(runs_to_average))
        # Get values from desired field
        vals_to_average = [val[field] for (_run, val) in runs_to_average]
        append!(vals_to_average_all,vals_to_average)
        #println(vals_to_average_all)
    end
    return mean(vals_to_average_all)
end

# Declare empty arrays that we will fill with averages
x_sienna = Int64[]
y_sienna_build_runtime = Union{Float64,Missing}[]
y_sienna_build_malloc = Union{Float64,Missing}[]
y_sienna_build_maxrss = Union{Float64,Missing}[]
y_sienna_solve_runtime = Union{Float64,Missing}[]
x_mtk = Int64[]
y_mtk_build_runtime = Union{Float64,Missing}[]
y_mtk_build_malloc = Union{Float64,Missing}[]
y_mtk_build_maxrss = Union{Float64,Missing}[]
y_mtk_solve_runtime = Union{Float64,Missing}[]

# Declare colors now so we can mark which values aren't ready yet
COLOR_MTK = colorant"#005CA8"
COLOR_SIENNA = colorant"#FF7000"
COLOR_INCOMPLETE = :green3
y_sienna_build_colors = fill(COLOR_SIENNA, 8)
y_sienna_solve_colors = fill(COLOR_SIENNA, 8)
y_mtk_build_colors = fill(COLOR_MTK, 8)
y_mtk_solve_colors = fill(COLOR_MTK, 8)

for N_INSTANCES in N_INSTANCES_ALL
    # -------------------------------------------------------------------------------------
    # DEFINE SYSTEM TO BUILD
    # -------------------------------------------------------------------------------------
    N_BUSES = 6*N_INSTANCES
    SYSTEM = "$(N_BUSES)Bus"
    println("------------ Starting $(SYSTEM)...")

    # Load Sienna Data
    push!(x_sienna, 9*N_INSTANCES)
    # --- BUILD (runtime, memalloc, maxrss)
    dict_sienna_build = @suppress load_object(joinpath(dirname(@__FILE__),"$(build_dir)/performance_build_Sienna_$(SYSTEM)_$(GEN_MIX).jld2"))
    push!(y_sienna_build_runtime, avg_excluding_first(dict_sienna_build, :time))
    push!(y_sienna_build_malloc,  avg_excluding_first(dict_sienna_build, :bytes)/(2^30))
    push!(y_sienna_build_maxrss,  avg_excluding_first(dict_sienna_build, :maxrss)/(2^30))
    # --- SOLVE
    # if N_INSTANCES in (64,128)
    #     push!(y_sienna_solve_runtime,   missing)
    #     y_sienna_solve_colors[7] = COLOR_INCOMPLETE
    #     y_sienna_solve_colors[8] = COLOR_INCOMPLETE
    # else
    dict_sienna_solve = @suppress load_object(joinpath(dirname(@__FILE__),"$(solve_dir)/performance_solve_Sienna_$(SYSTEM)_$(GEN_MIX).jld2"))
    push!(y_sienna_solve_runtime,   avg_excluding_first(dict_sienna_solve, :time))
    # end

    # Load MTK Data
    push!(x_mtk, 9*N_INSTANCES)
    # --- BUILD
    # if N_INSTANCES == 64
    #     dict_mtk_build = @suppress load_object(joinpath(dirname(@__FILE__),"$(build_dir)/performance_build_MTK_$(SYSTEM)_$(GEN_MIX)_progress_oldOOM.jld2"))
    #     push!(y_mtk_build_runtime, avg_excluding_first(dict_mtk_build,:time))
    #     push!(y_mtk_build_malloc,  avg_excluding_first(dict_mtk_build,:bytes)/(2^30))
    #     push!(y_mtk_build_maxrss,  avg_excluding_first(dict_mtk_build,:maxrss)/(2^30))
    #     y_mtk_build_colors[7] = COLOR_INCOMPLETE
    # else
    if N_INSTANCES == 128
        # dict_mtk_build = @suppress load_object(joinpath(dirname(@__FILE__),"$(build_dir)/performance_build_MTK_$(SYSTEM)_$(GEN_MIX)_progress_savedFeb20.jld2"))
        # #push!(y_mtk_build_runtime, dict_mtk_build[1][:time]) #only the first run is available right now
        # #push!(y_mtk_build_malloc,  dict_mtk_build[1][:bytes]/(2^30)) #only the first run is available right now
        # #push!(y_mtk_build_maxrss,  dict_mtk_build[1][:maxrss]/(2^30)) #only the first run is available right now
        # push!(y_mtk_build_runtime, avg_excluding_first(dict_mtk_build,:time))
        # push!(y_mtk_build_malloc,  avg_excluding_first(dict_mtk_build,:bytes)/(2^30))
        # push!(y_mtk_build_maxrss,  avg_excluding_first(dict_mtk_build,:maxrss)/(2^30))
        # #y_mtk_build_colors[8] = COLOR_INCOMPLETE

        dict_mtk_build = @suppress load_object(joinpath(dirname(@__FILE__),"$(build_dir)/performance_build_MTK_$(SYSTEM)_$(GEN_MIX)_progress_runs1and2.jld2"))
        dict_mtk_build2 = @suppress load_object(joinpath(dirname(@__FILE__),"$(build_dir)/performance_build_MTK_$(SYSTEM)_$(GEN_MIX)_progress_run3.jld2"))
        dict_mtk_build3 = @suppress load_object(joinpath(dirname(@__FILE__),"$(build_dir)/performance_build_MTK_$(SYSTEM)_$(GEN_MIX)_progress_run4.jld2"))
        push!(y_mtk_build_runtime, avg_excluding_first_multi([dict_mtk_build,dict_mtk_build2,dict_mtk_build3],:time))
        push!(y_mtk_build_malloc,  avg_excluding_first_multi([dict_mtk_build,dict_mtk_build2,dict_mtk_build3],:bytes)/(2^30))
        push!(y_mtk_build_maxrss,  avg_excluding_first_multi([dict_mtk_build,dict_mtk_build2,dict_mtk_build3],:maxrss)/(2^30))
    else
        dict_mtk_build = @suppress load_object(joinpath(dirname(@__FILE__),"$(build_dir)/performance_build_MTK_$(SYSTEM)_$(GEN_MIX).jld2"))
        push!(y_mtk_build_runtime, avg_excluding_first(dict_mtk_build, :time))
        push!(y_mtk_build_malloc,  avg_excluding_first(dict_mtk_build,:bytes)/(2^30))
        push!(y_mtk_build_maxrss,  avg_excluding_first(dict_mtk_build,:maxrss)/(2^30))
    end
    # --- SOLVE
    # if N_INSTANCES in (64,128)
    #     push!(y_mtk_solve_runtime, missing)
    #     y_mtk_solve_colors[7] = COLOR_INCOMPLETE
    #     y_mtk_solve_colors[8] = COLOR_INCOMPLETE
    # else
    dict_mtk_solve = @suppress load_object(joinpath(dirname(@__FILE__),"$(solve_dir)/performance_solve_MTK_$(SYSTEM)_$(GEN_MIX).jld2"))
    push!(y_mtk_solve_runtime,  avg_excluding_first(dict_mtk_solve, :time))
    #end

end

# Get readable ticks for x-axis (e.g. 8,9,10,20,30,...,90,100,200,300,...)
function get_xticks(x_values::Vector)
    ticks = Int[]
    labels = String[]
    hit_max_value = false
    push!(ticks, 8,10) # smallest system will always be 9 buses
    max_value = maximum(x_values)
    max_power = floor(Int, log10(max_value)) # e.g. max_value of 36 -> 1, max_value of 144 -> 2
    for p in 1:max_power
        for d in [2,4,6,8,10] #1:9
            tick = d * 10^p
            # Stop once we have gone past the max value
            if tick > max_value 
                if hit_max_value 
                    continue # stop
                else
                    hit_max_value = true # allow one more
                end
            end
            push!(ticks, tick)
        end
    end
    labels = string.(ticks)
    labels[1] = ""
    return (ticks, labels)
end

# Runtime
println("Runtime log10(MTK / Sienna):")
for i in eachindex(y_sienna_build_runtime)
    val = log10(y_mtk_build_runtime[i] / y_sienna_build_runtime[i])
    println("[$i] ", round(val, digits=3), " OOM")
end
# Malloc
println("\nMalloc log10(MTK / Sienna):")
for i in eachindex(y_sienna_build_malloc)
    val = log10(y_mtk_build_malloc[i] / y_sienna_build_malloc[i])
    println("[$i] ", round(val, digits=3), " OOM")
end
# MaxRSS
println("\nMaxRSS log10(MTK / Sienna):")
for i in eachindex(y_sienna_build_maxrss)
    val = log10(y_mtk_build_maxrss[i] / y_sienna_build_maxrss[i])
    println("[$i] ", round(val, digits=3), " OOM")
end

# Get readable ticks for y-axis (e.g. 10^-2, 10^-2, ... 10^5, ...)
function get_yticks(y_values::Vector)
    ticks = Float64[]
    labels = String[]
    hit_max_value = true
    min_value = minimum(y_values)
    max_value = maximum(y_values)
    min_power = floor(Int, log10(min_value)) # e.g. max_value of 36 -> 1, max_value of 144 -> 2
    max_power = ceil(Int, log10(max_value)) # e.g. max_value of 36 -> 1, max_value of 144 -> 2
    for p in min_power:max_power
        tick = 10.0^p
        # Stop once we have gone past the max value
        if tick > max_value 
            if hit_max_value 
                continue # stop
            else
                hit_max_value = true # allow one more
            end
        end
        push!(ticks, tick)
    end
    labels = [@sprintf "%.0e" i for i in ticks]
    return (ticks, labels)
end

# -----------------------------------------------------------------------------------------
# Plot Runtime
# -----------------------------------------------------------------------------------------
println("Plotting runtime")
(x_ticks, xlabels) = get_xticks(x_sienna)
(yticks, ylabels) = get_yticks(vcat(y_sienna_build_runtime,collect(skipmissing(y_sienna_solve_runtime)),collect(skipmissing(y_mtk_build_runtime)),collect(skipmissing(y_mtk_solve_runtime)),))
push!(yticks, yticks[end]*10) ## add one more to make it look nicer
p_runtime = Plots.plot(
    x_mtk, y_mtk_build_runtime;
    label = "Model Build - General IR  ",
    xlabel = "Number of Buses",
    ylabel = "Time [s]",
    title = "Wall Clock Runtime (Log-Log Scale)",
    legend = :topleft,
    xscale = :log10,
    yscale = :log10,
    xrange = (minimum(x_ticks), 1300), #maximum(x_ticks)),
    yrange = (minimum(yticks)*.75, maximum(yticks)),
    xticks = (x_ticks, xlabels),
    yticks = yticks, #:auto,
    linestyle = :solid,
    color = COLOR_MTK,
    markers = :circle,
    markersize = 5,
    markercolor = y_mtk_build_colors,
    markerstrokecolor = y_mtk_build_colors,
    extra_kwargs = :subplot,                     # send following options to the Axis
    pgfplotsx = Dict(
        "legend cell align" => "left",           # left‑justify legend text
        "legend image post style" => "xscale=2"  # wider legend sample
    )
)
Plots.plot!(
    p_runtime, 
    x_sienna, y_sienna_build_runtime;
    label = "Model Build - Custom IR",
    linestyle = :solid,
    color = COLOR_SIENNA,
    markers = :utriangle,
    markercolor = y_sienna_build_colors,
    markerstrokecolor = y_sienna_build_colors,
)
Plots.plot!(
    p_runtime, 
    x_sienna, y_mtk_solve_runtime;
    label = "Integration - General IR",
    linestyle = :dot,
    linewidth = 2,
    markerstrokewidth = 2,
    color = COLOR_MTK,
    markers = :circle,
    markersize = 5,
    markercolor = :white,
    markerstrokecolor = y_mtk_solve_colors,
)
Plots.plot!(
    p_runtime, 
    x_sienna, y_sienna_solve_runtime;
    label = "Integration - Custom IR",
    linestyle = :dot,
    linewidth = 2,
    markerstrokewidth = 2,
    color = COLOR_SIENNA,
    markers = :utriangle,
    markercolor = :white,
    markerstrokecolor = y_sienna_solve_colors,
)
#display(p_runtime)
savefig(p_runtime, joinpath(dirname(@__FILE__),"$(plot_dir)/plot_performance_runtime.pdf"))


# -----------------------------------------------------------------------------------------
# Plot Memory Allocated
# -----------------------------------------------------------------------------------------
println("Plotting memory allocated")
(xticks, xlabels) = get_xticks(x_sienna);
(yticks, ylabels) = get_yticks(vcat(collect(skipmissing(y_sienna_build_malloc)),collect(skipmissing(y_mtk_build_malloc))))
push!(yticks, yticks[end]*10) ## add one more to make it look nicer
p_memory = plot(
    x_mtk, y_mtk_build_malloc;
    label = "Model Build - General IR  ",
    xlabel = "Number of Buses",
    ylabel = "Memory [GiB]",
    title = "Total Allocated Memory (Log-Log Scale)", # Allocated During Build of Numerical Model",
    legend = :topleft,
    xscale = :log10,
    yscale = :log10,
    xrange = (minimum(xticks), 1300), #maximum(xticks)),
    yrange = (minimum(yticks), maximum(yticks)),
    xticks = (xticks, xlabels),
    yticks = yticks, #:auto,
    color = COLOR_MTK,
    markers = :circle,
    markersize = 5,
    markercolor = y_mtk_build_colors,
    markerstrokecolor = y_mtk_build_colors,
    extra_kwargs = :subplot,                     # send following options to the Axis
    pgfplotsx = Dict(
        "legend cell align" => "left",           # left‑justify legend text
        "legend image post style" => "xscale=2"  # wider legend sample
    )
)
plot!(
    p_memory, 
    x_sienna, y_sienna_build_malloc;
    label = "Model Build - Custom IR",
    color = COLOR_SIENNA,
    markers = :utriangle,
    markercolor = y_sienna_build_colors,
    markerstrokecolor = y_sienna_build_colors,
)
#display(p_memory)
savefig(p_memory, joinpath(dirname(@__FILE__),"$(plot_dir)/plot_performance_malloc.pdf"))

# -----------------------------------------------------------------------------------------
# Plot Max RSS
# -----------------------------------------------------------------------------------------
println("Plotting maxrss")
(xticks, xlabels) = get_xticks(x_sienna);
(yticks, ylabels) = get_yticks(vcat(collect(skipmissing(y_sienna_build_maxrss)),collect(skipmissing(y_mtk_build_maxrss)))) 
# push!(yticks, yticks[end]*10) ## add one more to make it look nicer
p_memory = plot(
    x_mtk, y_mtk_build_maxrss;
    label = "Model Build - General IR  ",
    xlabel = "Number of Buses",
    ylabel = "Memory [GiB]",
    title = "Maximum Resident Set Size (Log-Log Scale)",
    legend = :topleft,
    xscale = :log10,
    yscale = :log10,
    xrange = (minimum(xticks), 1300), #maximum(xticks)),
    yrange = (minimum(yticks), 10^2.1), #maximum(yticks)),
    xticks = (xticks, xlabels),
    yticks=yticks,
    color = COLOR_MTK,
    markers = :circle,
    markersize = 5,
    markercolor = y_mtk_build_colors,
    markerstrokecolor = y_mtk_build_colors,
    extra_kwargs = :subplot,                     # send following options to the Axis
    pgfplotsx = Dict(
        "legend cell align" => "left",           # left‑justify legend text
        "legend image post style" => "xscale=2"  # wider legend sample
    )
)
plot!(
    p_memory, 
    x_sienna, y_sienna_build_maxrss;
    label = "Model Build - Custom IR",
    color = COLOR_SIENNA,
    markers = :utriangle,
    markercolor = y_sienna_build_colors,
    markerstrokecolor = y_sienna_build_colors,
)
hline!(p_memory, 
    [8 16], 
    label=["8 GiB RAM" "16 GiB RAM"],#
    linestyle = [:dot :dash],
    marker=:none,
    linewidth=2,
    color=[:gray, :gray]
    )
#display(p_memory)
savefig(p_memory, joinpath(dirname(@__FILE__),"$(plot_dir)/plot_performance_maxrss.pdf"))


# Metrics available in @timed
# Source: https://docs.julialang.org/en/v1/base/base/#Base.@timed
# https://github.com/JuliaLang/julia/blob/44ecbcf92df9658751d1d6b94f48f33375ef2b17/base/timing.jl#L80
# time              ::Float64       # elapsed time in seconds
# bytes             ::Int64         # total bytes allocated
# gctime            ::Float64       # garbage collection time
# gcstats           ::Base.GC_Diff     
#   allocd          ::Int64         # Bytes allocated
#   malloc          ::Int64         # Number of GC aware malloc()
#   realloc         ::Int64         # Number of GC aware realloc()
#   poolalloc       ::Int64         # Number of pool allocation
#   bigalloc        ::Int64         # Number of big (non-pool) allocation
#   freecall        ::Int64         # Number of GC aware free()
#   total_time      ::Int64         # Time spent in garbage collection
#   pause           ::Int64         # Number of GC pauses
#   full_sweep      ::Int64         # Number of GC full collection
# lock_conflicts    ::Int64         # count 
# compile_time      ::Float64       # compilation time (sec)
# recompile_time    ::Float64       # recompilation time (sec)
# maxrss            ::UInt64        # Max resident set size for whole script... (not in @timed, added separately with MaxRSS)
