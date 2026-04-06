# Set up the package environment
cd(@__DIR__)
using Pkg
Pkg.activate("..")

ENV["GKSwstype"] = "100" # non-interactive headless mode for plots (on cluster) 

# Import packages
using JLD2
using Plots
using Plots.PlotMeasures
using Printf
using Suppressor
using Statistics
using OrdinaryDiffEq # needed to use interpolation (i.e. sol(t))
using ModelingToolkit # needed to load .jld2 of MTK solution object
using LaTeXStrings
pgfplotsx() # REMEMBER TO DO `ml texlive` on cluster

include("./utils/helper_functions_analysis.jl")

# NOTE: can be run independently as long as there are solution_norm files in analysis/validation_files.

# This script uses the following:
#   sienna/result_files/solution_$(SYSTEM)_$(GEN_MIX).jld2
#   sienna/result_files/varmap_$(SYSTEM)_$(GEN_MIX).jld2
#   mtk/result_files/solution_$(SYSTEM)_$(GEN_MIX).jld2
#   mtk/result_files/varmap_$(SYSTEM)_$(GEN_MIX).jld2
# And creates the following:
#   validation_files/validation_trajectory_samples_$(SYSTEM)_$(GEN_MIX).png

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
# Define directories
# -----------------------------------------------------------------------------------------

# Make directory for jld2 files (no effect if it already exists)
sienna_load_dir = "../sienna/result_files"
mtk_load_dir = "../mtk/result_files"
save_dir = "validation_files"
mkpath(joinpath(dirname(@__FILE__),"$(save_dir)"))

# -----------------------------------------------------------------------------------------
# Make plots of a few sample trajectories
# -----------------------------------------------------------------------------------------
trajectories = Dict(1=>Dict(), 2=>Dict(), 3=>Dict())
time_step = 0.001
t = collect(0.0:time_step:30.0)
t = collect(0.0:time_step:8.0)

# Define some settings
default(
    fontfamily="Times", 
    plot_titlefontsize=18,
    titlefont=16, 
    guidefont=14, # axis labels
    legendfontsize=12, 
    tickfont=11,
    dpi=1200,
    plot_titlefontcolor = :black,
    titlefontcolor = :black,
    legendfontcolor = :black,
    tickfontcolor = :black,
    guidefontcolor = :black,
    legendfonthalign = :left, 
    )

for N_INSTANCES in N_INSTANCES_ALL
    # Define system
    N_BUSES = 6*N_INSTANCES
    SYSTEM = "$(N_BUSES)Bus"

    # -------------------------------------------------------------------------------------
    # Define system
    # -------------------------------------------------------------------------------------
    N_BUSES = 6*N_INSTANCES
    SYSTEM = "$(N_BUSES)Bus"
    instance_list = get_9bus_instances(SYSTEM) # e.g. [0,1,2]
    println("Starting $(SYSTEM)...")

    # TODO: change this if you want more plots, but only using 9-bus for the paper
    if N_INSTANCES > 1 
        println("...Skipping plots for $(SYSTEM)...")
        continue 
    end

    # -----------------------------------------------------------------------------------------
    # Load solution objects
    # -----------------------------------------------------------------------------------------
    # Load Sienna ODESolution object
    sol_sienna_orig = @suppress load_object(joinpath(dirname(@__FILE__),"$(sienna_load_dir)/solution_$(SYSTEM)_$(GEN_MIX).jld2"));

    # Load MTK ODESolution object
    sol_mtk_orig = @suppress load_object(joinpath(dirname(@__FILE__),"$(mtk_load_dir)/solution_$(SYSTEM)_$(GEN_MIX).jld2"));

    # Load corresponding Sienna variable map
    map_sienna = @suppress load_object(joinpath(dirname(@__FILE__),"$(sienna_load_dir)/varmap_$(SYSTEM)_$(GEN_MIX).jld2"));

    # Load corresponding MTK variable map
    map_mtk = @suppress load_object(joinpath(dirname(@__FILE__),"$(mtk_load_dir)/varmap_$(SYSTEM)_$(GEN_MIX).jld2"));

    # -----------------------------------------------------------------------------------------
    # Interpolate Sienna and MTK solutions to allow comparison
    # -----------------------------------------------------------------------------------------
    # Our solution objects include the exact integrator steps. 
    # To compare them directly, we need to interpolate to a common set of points.
    sol_sienna = sol_sienna_orig(t)
    sol_mtk = sol_mtk_orig(t)

    # Select a subset of states to plot 
    INST = N_INSTANCES-1 # last instance
    INSTs = INST == 0 ? "" : string(INST)
    INSTm = "sys$(string(INST))_"
    system_name = "$(9*N_INSTANCES)-bus"

    # GEN1 (lightest)
    COLOR_GEN1_DARK  = colorant"#D99B2F"  # rich gold
    COLOR_GEN1_LIGHT = colorant"#F2D78B"  # light gold

    # GEN2 (middle)
    COLOR_GEN2_DARK  = colorant"#A63A78"  # raspberry/magenta
    COLOR_GEN2_LIGHT = colorant"#D88FBF"  # pink‑mauve

    # GEN3 (darkest)
    COLOR_GEN3_DARK  = colorant"#005E46"  # deep green
    COLOR_GEN3_LIGHT = colorant"#66C2A5"  # light teal

    trajectories[1]["Gen 1 (SG)"] =  # ω
        Dict(
            :symbolic => getindex.(sol_mtk.u, map_mtk["$(INSTm)gen1_ω"]),
            :proposed => getindex.(sol_sienna.u, map_sienna["generator-$(INSTs)1-1_ω"]),
            :ylabel => "Per unit",
            :color => COLOR_GEN1_DARK,
            :color2 => COLOR_GEN1_LIGHT,
            :subtitle => "Angular Frequency of Rotor",
        )
    trajectories[1]["Gen 3 (SG)"] = # ω
        Dict(
            :symbolic => getindex.(sol_mtk.u, map_mtk["$(INSTm)gen3_ω"]),
            :proposed => getindex.(sol_sienna.u, map_sienna["generator-$(INSTs)3-1_ω"]),
            :ylabel => "Per unit",
            :color => COLOR_GEN3_DARK,
            :color2 => COLOR_GEN3_LIGHT,
            :subtitle => "Rotor Angular Frequency (SG)",
        )
    trajectories[2]["Gen 1 (SG)"] = # δ
        Dict(
            :symbolic => getindex.(sol_sienna.u, map_sienna["generator-$(INSTs)1-1_δ"]),#map_mtk["$(INSTm)gen1_δ"]),
            :proposed => getindex.(sol_sienna.u, map_sienna["generator-$(INSTs)1-1_δ"]),
            :ylabel => "Radians",
            :color => COLOR_GEN1_DARK,
            :color2 => COLOR_GEN1_LIGHT,
            :subtitle => "Rotor Angle (SG) or Outer Loop Angle (GFM)",
        )
    trajectories[2]["Gen 2 (GFM)"] = # θ
        Dict(
            :symbolic => getindex.(sol_mtk.u, map_mtk["$(INSTm)gen2_θoc"]),
            :proposed => getindex.(sol_sienna.u, map_sienna["generator-$(INSTs)2-1_θ_oc"]),
            :ylabel => "Radians",
            :color => COLOR_GEN2_DARK,
            :color2 => COLOR_GEN2_LIGHT,
            :subtitle => "Rotor Angle (SG) or Outer Loop Angle (GFM)",
        )
    trajectories[2]["Gen 3 (SG)"] =  # δ
        Dict(
            :symbolic => getindex.(sol_mtk.u, map_mtk["$(INSTm)gen3_δ"]),
            :proposed => getindex.(sol_sienna.u, map_sienna["generator-$(INSTs)3-1_δ"]),
            :ylabel => "Radians",
            :color => COLOR_GEN3_DARK,
            :color2 => COLOR_GEN3_LIGHT,
            :subtitle => "Rotor Angle (SG) or Outer Loop Angle (GFM)",
        )
    trajectories[3]["Gen 1 (SG)"] =  # HIGH SIDE OF TRANSFOMER
        Dict(
            :symbolic => sqrt.(getindex.(sol_mtk.u, map_mtk["$(INSTm)shunt4_vd"]).^2 + getindex.(sol_mtk.u, map_mtk["$(INSTm)shunt4_vq"]).^2),
            :proposed => sqrt.(getindex.(sol_sienna.u, map_sienna["V_$(INSTs)1_R"]).^2+ getindex.(sol_sienna.u, map_sienna["V_$(INSTs)1_I"]).^2),
            :ylabel => "Per unit",
            :color => COLOR_GEN1_DARK,
            :color2 => COLOR_GEN1_LIGHT,
            :subtitle => "Voltage Magnitude on High-Side of Transformer (SG, GFM)",
        )
    trajectories[3]["Gen 2 (GFM)"] = 
        Dict(
            :symbolic => sqrt.(getindex.(sol_mtk.u, map_mtk["$(INSTm)shunt7_vd"]).^2 + getindex.(sol_mtk.u, map_mtk["$(INSTm)shunt7_vq"]).^2),
            :proposed => sqrt.(getindex.(sol_sienna.u, map_sienna["V_$(INSTs)2_R"]).^2+ getindex.(sol_sienna.u, map_sienna["V_$(INSTs)2_I"]).^2),
            :ylabel => "Per unit",
            :color => COLOR_GEN2_DARK,
            :color2 => COLOR_GEN2_LIGHT,
            :subtitle => "Voltage Magnitude on High-Side of Transformer (SG, GFM)",
        )

    trajectories[3]["Gen 3 (SG)"] = 
        Dict(
            :symbolic => sqrt.(getindex.(sol_mtk.u, map_mtk["$(INSTm)shunt9_vd"]).^2 + getindex.(sol_mtk.u, map_mtk["$(INSTm)shunt9_vq"]).^2),
            :proposed => sqrt.(getindex.(sol_sienna.u, map_sienna["V_$(INSTs)3_R"]).^2+ getindex.(sol_sienna.u, map_sienna["V_$(INSTs)3_I"]).^2),
            :ylabel => "Per unit",
            :color => COLOR_GEN3_DARK,
            :color2 => COLOR_GEN3_LIGHT,
            :subtitle => "Voltage Magnitude on High-Side of Transformer (SG, GFM)",
        )

    # -----------------------------------------------------------------------------------------
    # Plot the trajectories
    # -----------------------------------------------------------------------------------------
    ks = sort(collect(keys(trajectories)))  # sort keys

    # SUBPLOTS
    n_plots = 3 # number of real plots
    p = plot(
        layout = grid(3,1),
        size=(700, 650), 
        plot_title="Load Step in $(system_name) Network Using Both Index-Reduced Models",
        )

    # Three subplots with trajectories
    for i = 1:n_plots
        trajs = trajectories[i] # 1st, 2nd, 3rd plot
        ks = sort(collect(keys(trajs))) # state variables on the plot
        for k in ks
            plot!(
                p[i],
                t, trajs[k][:symbolic],
                linestyle = :solid,
                linecolor = trajs[k][:color],
                linewidth = 4,
                titlefont = :grey30,
                label = "$(k) - General", #$(ks[idx2])
                legend = false,
            )
        end
        for k in ks
            if i == 3
                plot!(
                    p[i],
                    t, trajs[k][:proposed],
                    linestyle = :dash,
                    linecolor = trajs[k][:color2], #lighten(parse(Colorant, trajs[k][:color]), 0.2), #:cyan,
                    linewidth = 3,
                    titlefont = :grey30,
                    # DIFFERENT
                    legend=(0.0, -0.4),
                    label = "$(k) - Custom\\kern2mm",
                    legend_column = 3,
                    yticks = 1.02:0.02:1.08,
                    xlabel = "Time (s)",
                )
            else 
                plot!(
                    p[i],
                    t, trajs[k][:proposed],
                    linestyle = :dash,
                    linecolor = trajs[k][:color2],
                    linewidth = 3,
                    titlefont = :grey30,
                    # DIFFERENT
                    legend = false,
                    label = "$(k) - Custom\\kern2mm",
                ) 
                if i == 1 plot!(p[i], yrange=(0.9998,1.0033)) else nothing end
                if i == 2 plot!(p[i], yrange=(0.15,1.25)) else nothing end
            end
            ylabel!(p[i], trajs[k][:ylabel])
            title!(p[i], trajs[k][:subtitle])
        end

    end

    savefig(p, joinpath(dirname(@__FILE__),"$(save_dir)/validation_trajectory_samples_$(SYSTEM)_$(GEN_MIX).pdf"))

end
