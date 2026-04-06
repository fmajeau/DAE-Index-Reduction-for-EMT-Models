# Set up the package environment
cd(@__DIR__)
using Pkg
Pkg.activate("..")

ENV["GKSwstype"] = "100" # non-interactive headless mode for plots (on cluster) 

# Import packages
using OrdinaryDiffEq # needed to use interpolation (i.e. sol(t))
using LinearAlgebra
using JLD2
using ModelingToolkit # needed to load .jld2 of MTK solution object
using Plots
using Printf
using Suppressor

include("./utils/helper_functions_analysis.jl")

# This script uses the following:
#   sienna/result_files/solution_$(SYSTEM)_$(GEN_MIX).jld2
#   sienna/result_files/varmap_$(SYSTEM)_$(GEN_MIX).jld2
#   mtk/result_files/solution_$(SYSTEM)_$(GEN_MIX).jld2
#   mtk/result_files/varmap_$(SYSTEM)_$(GEN_MIX).jld2
# to create the following:
#   analysis/validation_files/solution_norms_{SYSTEM}_{GEN_MIX}.jld2
#   analysis/validation_files/varmap_{SYSTEM}_{GEN_MIX}.jld2

# This script uses the following:
#   sienna/result_files/eigs_$(SYSTEM)_$(GEN_MIX).jld2
#   mtk/result_files/eigs_$(SYSTEM)_$(GEN_MIX).jld2
# to create the following:
#   analysis/validation_files/eigs_norms.jld2
#   analysis/validation_files/scatter_eigs_{SYSTEM}_{GEN_MIX}.png

# -----------------------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------------------
# For bash 
#@assert length(ARGS) == 2 "Provide N_INSTANCES as 1st arg, GEN_MIX as 2nd arg"
#N_INSTANCES_ALL = [parse(Int, i) for i in split(string(ARGS[1]), ',')] # e.g. [1,2,4]
#GEN_MIX = ARGS[2] # e.g. "2sg1inv"  
#@assert GEN_MIX == "2sg1inv" "Only set up for GEN_MIX=\"2sg1inv\" at the moment"

# For VSCode
N_INSTANCES_ALL = [1,2,4,8,16,32,64,128]
GEN_MIX = "2sg1inv"

# -----------------------------------------------------------------------------------------
# Create folder and set constants
# -----------------------------------------------------------------------------------------
# Make directory for jld2 files (no effect if it already exists)
sienna_load_dir = "../sienna/result_files"
mtk_load_dir = "../mtk/result_files"
save_dir = "validation_files"
mkpath(joinpath(dirname(@__FILE__),"$(save_dir)"))

# Choose norm 
NORM = Inf

# -----------------------------------------------------------------------------------------
# Calculate difference norms of trajectories
# -----------------------------------------------------------------------------------------
for N_INSTANCES in N_INSTANCES_ALL

    # -------------------------------------------------------------------------------------
    # Define system
    # -------------------------------------------------------------------------------------
    N_BUSES = 6*N_INSTANCES
    SYSTEM = "$(N_BUSES)Bus"
    instance_list = get_9bus_instances(SYSTEM) # e.g. [0,1,2]
    println("Starting traj norms for $(SYSTEM)..."); flush(stdout);

    # -----------------------------------------------------------------------------------------
    # Load solution objects
    # -----------------------------------------------------------------------------------------
    # Load Sienna ODESolution object
    @suppress_err begin
    sol_sienna_orig = @suppress load_object(joinpath(dirname(@__FILE__),"$(sienna_load_dir)/solution_$(SYSTEM)_$(GEN_MIX).jld2"));

    # Load MTK ODESolution object
    sol_mtk_orig = @suppress load_object(joinpath(dirname(@__FILE__),"$(mtk_load_dir)/solution_$(SYSTEM)_$(GEN_MIX).jld2"));

    # Load corresponding Sienna variable map
    map_sienna = @suppress load_object(joinpath(dirname(@__FILE__),"$(sienna_load_dir)/varmap_$(SYSTEM)_$(GEN_MIX).jld2"));

    # Load corresponding MTK variable map
    map_mtk = @suppress load_object(joinpath(dirname(@__FILE__),"$(mtk_load_dir)/varmap_$(SYSTEM)_$(GEN_MIX).jld2"));
    
    # Create s2m_all (TODO: make this not just included script...)
    s2m_all = map_sienna_to_mtk(SYSTEM, map_sienna, map_mtk)

    # -----------------------------------------------------------------------------------------
    # Interpolate Sienna and MTK solutions to allow comparison
    # -----------------------------------------------------------------------------------------
    # Our solution objects include the exact integrator steps. 
    # To compare them directly, we need to interpolate to a common set of points.
    time_step = 0.001 #TODO: maybe make bash arg?
    t = collect(0.0:time_step:30.0)
    sol_sienna = sol_sienna_orig(t)
    sol_mtk = sol_mtk_orig(t)

    # -----------------------------------------------------------------------------------------
    # Some of the Sienna and MTK vars are defined differently, adjust for that
    # -----------------------------------------------------------------------------------------
    # Make coeffs to adjust between different variables
    coeffs = Dict{String,Float64}()
    Sb_sys = 100.0
    Sb_gen = Dict(1 => 500.0, 2 => 250.0, 3 => 100.0) # TODO: get from real model at some point?
    for inst in instance_list
        INSTm = SYSTEM == "6Bus" ? "" : "sys$(string(inst))_" # 6Bus system doesn't have sub systems like sys0,sys1,etc.
        INSTm = "sys$(string(inst))_" # 6Bus system doesn't have sub systems like sys0,sys1,etc.
        # id/iq       in MTK    : Sb_sys, flowing into gen
        # ir_hs/ii_hs in Sienna : Sb_gen, flowing into grid
        coeffs_inst = Dict(
            "$(INSTm)xfmr4S_id" => -(Sb_sys/Sb_gen[1]), # flows 4 to S (into gen), negate to match sienna
            "$(INSTm)xfmr4S_iq" => -(Sb_sys/Sb_gen[1]), # flows 4 to S (into gen), negate to match sienna
            "$(INSTm)xfmrS7_iq" => Sb_sys/Sb_gen[2],    # flows S to 7 (out of gen), keep positive to match sienna
            "$(INSTm)xfmrS7_id" => Sb_sys/Sb_gen[2],    # flows S to 7 (out of gen), keep positive to match sienna
            "$(INSTm)xfmr9S_id" => -(Sb_sys/Sb_gen[3]), # flows 9 to S (into gen), negate to match sienna
            "$(INSTm)xfmr9S_iq" => -(Sb_sys/Sb_gen[3]), # flows 9 to S (into gen), negate to match sienna
            "$(INSTm)gen2_id" => -(Sb_sys/Sb_gen[2]),   # flows gen terminal to ground (into gen), negate to match sienna
            "$(INSTm)gen2_iq" => -(Sb_sys/Sb_gen[2]),   # flows gen terminal to ground (into gen), negate to match sienna
            )
        merge!(coeffs,coeffs_inst)
    end


    # -----------------------------------------------------------------------------------------
    # Calculate stator flux for MTK
    # -----------------------------------------------------------------------------------------
    # TODO: move this into a function at some point? 
    # Sienna has ψd, ψq, but MTK does not.
    # Need to calculate ψd, ψq in MTK using the other MTK states so we can compare.
    # Diff states: eq_p, ed_p, ψd_pp, ψq_pp (definitely have)
    # Alg states: Id, Iq, 
    # Parameters: Xd_pp, Xq_pp, γd1, γq1 (definitely have)
    # Sienna has psi. I could try and calculate psi from the MTK values in order to compare that too?
    # Then I would have everything except the algebraic variables. 
    norms_dict = Dict()
    for inst in instance_list
        INSTs = inst == 0 ? "" : string(inst)
        INSTm = SYSTEM == "6Bus" ? "" : "sys$(string(inst))_"
        INSTm = "sys$(string(inst))_"
        # Sienna
        gen3_ψd_sienna = getindex.(sol_sienna.u, map_sienna["generator-$(INSTs)3-1_ψd"])
        gen3_ψq_sienna = getindex.(sol_sienna.u, map_sienna["generator-$(INSTs)3-1_ψq"])
        gen1_ψd_sienna = getindex.(sol_sienna.u, map_sienna["generator-$(INSTs)1-1_ψd"])
        gen1_ψq_sienna = getindex.(sol_sienna.u, map_sienna["generator-$(INSTs)1-1_ψq"])

        # Parameters for both gens.
        Xd_p = 0.169    # [pu] 
        Xq_p = 0.228    # [pu] 
        Xd_pp = 0.135   # [pu] 
        Xq_pp = 0.2     # [pu] 
        Xl = 0.13       # [pu] 
        γd1 = (Xd_pp - Xl) / (Xd_p - Xl)
        γq1 = (Xq_pp - Xl) / (Xq_p - Xl) 

        # Generator 3 (ψd)
        ψd_pp = getindex.(sol_mtk.u, map_mtk["$(INSTm)gen3_ψd_pp"])
        eq_p = getindex.(sol_mtk.u, map_mtk["$(INSTm)gen3_eq_p"])
        Id = getindex.(sol_mtk.u, map_mtk["$(INSTm)gen3_Id"])
        gen3_ψd_mtk =  - (Xd_pp*Id) + (γd1*eq_p) + ((1-γd1)*ψd_pp)  # Id

        # Generator 3 (ψq)
        ψq_pp = getindex.(sol_mtk.u, map_mtk["$(INSTm)gen3_ψq_pp"])
        ed_p = getindex.(sol_mtk.u, map_mtk["$(INSTm)gen3_ed_p"])
        Iq = getindex.(sol_mtk.u, map_mtk["$(INSTm)gen3_Iq"])
        gen3_ψq_mtk =  - (Xq_pp*Iq) - (γq1*ed_p) + ((1-γq1)*ψq_pp)  # Iq

        # Generator 1 (ψd)
        ψd_pp = getindex.(sol_mtk.u, map_mtk["$(INSTm)gen1_ψd_pp"])
        eq_p = getindex.(sol_mtk.u, map_mtk["$(INSTm)gen1_eq_p"])
        Id = getindex.(sol_mtk.u, map_mtk["$(INSTm)gen1_Id"])
        gen1_ψd_mtk =  - (Xd_pp*Id) + (γd1*eq_p) + ((1-γd1)*ψd_pp)  # Id

        # Generator 1 (ψq)
        # Note: we don't have explicit access to Iq for gen 1 so have to calculate it first.
        ψq_pp = getindex.(sol_mtk.u, map_mtk["$(INSTm)gen1_ψq_pp"])
        ed_p = getindex.(sol_mtk.u, map_mtk["$(INSTm)gen1_ed_p"])
        xfmrS4_id = -getindex.(sol_mtk.u, map_mtk["$(INSTm)xfmr4S_id"])
        xfmrS4_iq = -getindex.(sol_mtk.u, map_mtk["$(INSTm)xfmr4S_iq"])
        xfmrSg_41_id = getindex.(sol_mtk.u, map_mtk["$(INSTm)xfmrSg_41_id"])
        xfmrSg_41_iq = getindex.(sol_mtk.u, map_mtk["$(INSTm)xfmrSg_41_iq"])
        xfmr1S_id = xfmrS4_id + xfmrSg_41_id
        xfmr1S_iq = xfmrS4_iq + xfmrSg_41_iq
        if inst == 0
            δ = getindex.(sol_sienna.u, map_sienna["generator-$(INSTs)1-1_δ"])[1] # i know.. using sienna.. but it's a constant
        else 
            δ = getindex.(sol_mtk.u, map_mtk["$(INSTm)gen1_δ"])
        end
        #Id = (1.0/5.0)*((sin(δ)*xfmr1S_id) - (cos(δ)*xfmr1S_iq))
        Iq = (1.0/5.0)*((cos.(δ).*xfmr1S_id) + (sin.(δ).*xfmr1S_iq))
        gen1_ψq_mtk =  - (Xq_pp*Iq) - (γq1*ed_p) + ((1-γq1)*ψq_pp)  # Iq

        # Norms
        norm_gen3_ψd = norm((gen3_ψd_sienna-gen3_ψd_mtk), NORM)
        norm_gen3_ψq = norm((gen3_ψq_sienna-gen3_ψq_mtk), NORM)
        norm_gen1_ψd = norm((gen1_ψd_sienna-gen1_ψd_mtk), NORM)
        norm_gen1_ψq = norm((gen1_ψq_sienna-gen1_ψq_mtk), NORM)
        norms_dict["generator-$(INSTs)3-1_ψd"] = norm_gen3_ψd
        norms_dict["generator-$(INSTs)3-1_ψq"] = norm_gen3_ψq
        norms_dict["generator-$(INSTs)1-1_ψd"] = norm_gen1_ψd
        norms_dict["generator-$(INSTs)1-1_ψq"] = norm_gen1_ψq

    end

    # -----------------------------------------------------------------------------------------
    # Calculate norm of difference between Sienna and MTK
    # -----------------------------------------------------------------------------------------
    for (key_sienna,key_mtk) in sort(s2m_all)
        coeff = key_mtk in keys(coeffs) ? coeffs[key_mtk] : 1
        x_sienna = getindex.(sol_sienna.u, map_sienna[key_sienna])
        x_mtk = getindex.(coeff.*(sol_mtk.u), map_mtk[key_mtk])
        norm_of_diff = norm((x_sienna-x_mtk), NORM) 
        norms_dict[key_sienna] = norm_of_diff
    end

    # -----------------------------------------------------------------------------------------
    # Save norms to file
    # -----------------------------------------------------------------------------------------
    @suppress save_object(joinpath(dirname(@__FILE__),"$(save_dir)/solution_norms_$(SYSTEM)_$(GEN_MIX).jld2"), norms_dict);
    
    end # end of suppress_err
end

# -----------------------------------------------------------------------------------------
# Calculate difference norms of eigenvalues
# -----------------------------------------------------------------------------------------
eigs_dict = Dict{}() # SYSTEM => float (only one norm per system)
for N_INSTANCES in N_INSTANCES_ALL
    # Define system
    N_BUSES = 6*N_INSTANCES
    SYSTEM = "$(N_BUSES)Bus"
    println("Starting eig norms for $(SYSTEM)..."); flush(stdout);

    # Load eigenvalues
    eigs_sienna = @suppress load_object(joinpath(dirname(@__FILE__),"$(sienna_load_dir)/eigs_$(SYSTEM)_$(GEN_MIX).jld2"));
    eigs_mtk = @suppress load_object(joinpath(dirname(@__FILE__),"$(mtk_load_dir)/eigs_$(SYSTEM)_$(GEN_MIX).jld2"));

    # Remove zero-valued eigenvalue, refers to ref omega 
    # TODO: probably do this in a better way?
    eigs_sienna_nonzero = eigs_sienna[1:end-1] 

    # Calculate norm difference
    eigs_dict[N_INSTANCES] = norm((eigs_sienna_nonzero - eigs_mtk), NORM)

    # Make plot to see if they are the same
    p = scatter(
        real.(eigs_sienna_nonzero), imag.(eigs_sienna_nonzero);
        label = "eigs_sienna",
        marker = (:circle, 6),
        color = :blue)
    scatter!(p, 
        real.(eigs_mtk), imag.(eigs_mtk);
        label = "eigs_mtk",
        marker = (:cross, 6),
        color = :red)
    xlabel!("Real part")
    ylabel!("Imaginary part")
    title!("Eigenvalues for $(SYSTEM) \n max inf norm = $(round(eigs_dict[N_INSTANCES],digits=4))")
    savefig(p, joinpath(dirname(@__FILE__),"$(save_dir)/scatter_eigs_$(SYSTEM)_$(GEN_MIX)"))

end

# Save norms to file (one dict entry per system)
@suppress save_object(joinpath(dirname(@__FILE__),"$(save_dir)/eigs_norms.jld2"), eigs_dict);
 