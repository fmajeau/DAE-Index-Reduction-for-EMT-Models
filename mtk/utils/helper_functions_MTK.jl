# -----------------------------------------------------------------------------------------
# Get list of 9bus instance indices in a system
# -----------------------------------------------------------------------------------------
function _get_9bus_instances(SYSTEM)
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
# Build 9Bus-instance-specific gen parameters to pass in to MTK subsystems
# -----------------------------------------------------------------------------------------
function _build_params_gen_setpoints(sp, instance)
    gen_sp_instance = Dict{String,Dict{String,Float64}}()
    i = instance == 0 ? "" : string(instance)
    for g in 1:3
        gen_sp_instance["generator-$(g)-1"] = sp["generator-$(i)$(g)-1"]
    end
    return gen_sp_instance
end

# -----------------------------------------------------------------------------------------
# Build 9Bus-instance-specific load parameters to pass in to MTK subsystems
# -----------------------------------------------------------------------------------------
function _build_params_load_voltages(x0, instance)
    load_v_instance = Dict{String,Dict{Symbol,Float64}}()
    i = instance == 0 ? "" : string(instance)
    for l in [5,6,8]
        load_v_instance["V_$(l)"] = x0["V_$(i)$(l)"]
    end
    return load_v_instance
end

# -----------------------------------------------------------------------------------------
# Build full system dictionary of MTK initial conditions from Sienna initial conditions
# -----------------------------------------------------------------------------------------
function _build_initial_condition_dict_MTK_from_Sienna(sys, x0_init_dict, Sb_gens; instance=0)

    # Build a dictionary to store the MTK initial conditions
    # NOTE: Unordered, so just use the symbolic names.
    u0_dict = Dict{Union{SymbolicUtils.BasicSymbolic{Real},Num}, Float64}()

    # Define prefix based on 9bus instance
    X = instance == 0 ? string() : string(instance) 

    # Grab system base 
    # TODO: if I remove the default for this it will also have to be passed in...
    Sb_sys = ModelingToolkit.getdefault(sys.Sb_sys)

    # Have to pass in Sb_gen because they aren't defaults and thus I can't access them in 
    # stable way until I create an ODEProblem (can't use getdefault directly and apparently 
    # indexing into parameters(sys) like this is unstable: ModelingToolkit.getdefault(parameters(sys)[i])
    Sb_gen_1 = Sb_gens[1]
    Sb_gen_2 = Sb_gens[2]
    Sb_gen_3 = Sb_gens[3]

    # -----------------------------------------------------------------------------------------
    # Dynamic bus voltages (i.e. w/ capacitors)
    # -----------------------------------------------------------------------------------------

    # Create a map between sienna device names and mtk device names 
    # TODO: This is HARD CODED - update this dictionary if you change the MTK model
    names_DynamicCapacitor = Dict(
        sys.shunt4 => "V_$(X)1",
        sys.shunt5 => "V_$(X)5",
        sys.shunt6 => "V_$(X)6",
        sys.shunt7 => "V_$(X)2",
        sys.shunt8 => "V_$(X)8",
        sys.shunt9 => "V_$(X)3",
    )

    # Grab the corresponding IC value from Sienna and store in MTK IC dict
    for (name_MTK, name_Sienna) in names_DynamicCapacitor
        # Variable name mapping for Sauer & Pai SGs (ref)
        MTK_to_Sienna_DynamicCapacitor = Dict(
            name_MTK.vd     => :R,
            name_MTK.vq     => :I,
        )
        for (var_MTK, var_Sienna) in MTK_to_Sienna_DynamicCapacitor
            u0_dict[var_MTK] = x0_init_dict[name_Sienna][var_Sienna]
        end
    end

    # -----------------------------------------------------------------------------------------
    # Dynamic line currents
    # -----------------------------------------------------------------------------------------

    # Create a map between sienna device names and mtk device names 
    # TODO: This is HARD CODED - update this dictionary if you change the MTK model
    if X==""
        X1 = X 
    else
        X1 = " "*X
    end
    names_DynamicImpedance_lines = Dict(
        sys.line54 => "Bus $(X)5-Bus$(X1)1-i_1",
        sys.line78 => "Bus $(X)2-Bus $(X)8-i_1",
        sys.line64 => "Bus $(X)6-Bus$(X1)1-i_1",
        sys.line75 => "Bus $(X)2-Bus $(X)5-i_1",
        sys.line89 => "Bus $(X)8-Bus $(X)3-i_1",
        sys.line96 => "Bus $(X)3-Bus $(X)6-i_1",
    )

    # Grab the corresponding IC value from Sienna and store in MTK IC dict
    for (name_MTK, name_Sienna) in names_DynamicImpedance_lines
        # Variable name mapping for Sauer & Pai SGs (ref)
        MTK_to_Sienna_DynamicImpedance_lines = Dict(
            name_MTK.id     => :Il_R,
            name_MTK.iq     => :Il_I,
        )
        for (var_MTK, var_Sienna) in MTK_to_Sienna_DynamicImpedance_lines
            u0_dict[var_MTK] = x0_init_dict[name_Sienna][var_Sienna]
        end
    end
  
    # -----------------------------------------------------------------------------------------
    # Generators
    # -----------------------------------------------------------------------------------------

    # Create a map between sienna device names and mtk device names 
    # TODO: This is HARD CODED - update these dictionaries if you change the MTK model
    if instance==0
        names_GenModelRef = Dict(
            sys.gen1 => "generator-$(X)1-1")
        names_GenModel = Dict(
            sys.gen3 => "generator-$(X)3-1")
    else
        names_GenModelRef = Dict()
        names_GenModel = Dict(
            sys.gen1 => "generator-$(X)1-1",
            sys.gen3 => "generator-$(X)3-1")
    end
    names_InvModel = Dict(sys.gen2 => "generator-$(X)2-1")

    # SG - REFERENCE
    for (name_MTK, name_Sienna) in names_GenModelRef
        # Variable name mapping for Sauer & Pai SGs (ref)
        MTK_to_Sienna_GenModelRef = Dict(
            name_MTK.ψq     => :ψq,
            name_MTK.ψd     => :ψd ,
            name_MTK.eq_p   => :eq_p,
            name_MTK.ed_p   => :ed_p,
            name_MTK.ψd_pp  => :ψd_pp,
            name_MTK.ψq_pp  => :ψq_pp,
            name_MTK.ω      => :ω,
            name_MTK.Vf     => :Vf,
            name_MTK.Vr1    => :Vr1,
            name_MTK.Vr2    => :Vr2,
            name_MTK.Vm     => :Vm,
        )
        for (var_MTK, var_Sienna) in MTK_to_Sienna_GenModelRef
            u0_dict[var_MTK] = x0_init_dict[name_Sienna][var_Sienna]
        end

    end

    # SG - NON-REFERENCE
    for (name_MTK, name_Sienna) in names_GenModel
        # Variable name mapping for Sauer & Pai SGs (non-ref)
        MTK_to_Sienna_GenModel = Dict(
            name_MTK.ψq     => :ψq,
            name_MTK.ψd     => :ψd ,
            name_MTK.eq_p   => :eq_p,
            name_MTK.ed_p   => :ed_p,
            name_MTK.ψd_pp  => :ψd_pp,
            name_MTK.ψq_pp  => :ψq_pp,
            name_MTK.δ      => :δ,
            name_MTK.ω      => :ω,
            name_MTK.Vf     => :Vf,
            name_MTK.Vr1    => :Vr1,
            name_MTK.Vr2    => :Vr2,
            name_MTK.Vm     => :Vm,
            # :ir_hs is used for DynamicImpedanceDQ on high side of transformer (network RF, but gen power base)
            # :ii_hs is used for DynamicImpedanceDQ on high side of transformer
        )
        for (var_MTK, var_Sienna) in MTK_to_Sienna_GenModel
            u0_dict[var_MTK] = x0_init_dict[name_Sienna][var_Sienna]
        end
    end

    # INVERTER
    for (name_MTK,name_Sienna) in names_InvModel
        MTK_to_Sienna_InvModel = Dict(
            name_MTK.θoc => :θ_oc,
            name_MTK.pm => :p_oc,
            name_MTK.qm => :q_oc,
            name_MTK.ξD => :ξd_ic,
            name_MTK.ξQ => :ξq_ic,
            name_MTK.γD => :γd_ic,
            name_MTK.γQ => :γq_ic,
            name_MTK.ϕD => :ϕd_ic,
            name_MTK.ϕQ => :ϕq_ic,
            name_MTK.icvd => :ir_cnv,
            name_MTK.icvq => :ii_cnv,
            name_MTK.vd => :vr_filter,
            name_MTK.vq => :vi_filter,
            # :ir_hs is used for DynamicImpedanceDQ on high side of transformer (network RF, but gen power base)
            # :ii_hs is used for DynamicImpedanceDQ on high side of transformer
        )
        x0_dict = x0_init_dict[name_Sienna] # Sienna ICs for this device only
        for (var_MTK, var_Sienna) in MTK_to_Sienna_InvModel
            u0_dict[var_MTK] = x0_dict[var_Sienna]
        end
        # Do the ones that need a base conversion.
        MTK_to_Sienna_InvModel = Dict(
            name_MTK.id => :ir_filter, # id is in network base (MTK chose id over iD) but ir_filter is in gen base...
            name_MTK.iq => :ii_filter, # same ^ 
        )
        for (var_MTK, var_Sienna) in MTK_to_Sienna_InvModel
            # NOTE: Filter equations define positive id and iq as injections into the grid, but the OnePortDQ 
            #  definitions define positive id and iq as flow from positive to negative voltage, which would be 
            #  a withdrawal from the grid (gen bus --> ground). Negative sign accounts for this.
            u0_dict[var_MTK] = -x0_dict[var_Sienna] * (Sb_gen_2 / Sb_sys) # sienna is in Sb_gen, .id/.iq is in Sb_sys
        end
    end

    # -----------------------------------------------------------------------------------------
    # Transformers - INV
    # -----------------------------------------------------------------------------------------
    # NOTE: this is a weird one because right now we are grabbing the transformer current from
    # the inverter, because that is how the inverter it implemented in Sienna and in MTK we 
    # separate it out. The other inverter states were already handled. 

    # Create a map between sienna device names and mtk device names 
    # TODO: This is HARD CODED - update this dictionary if you change the MTK model
    names_DynamicImpedance_xfmrs = Dict(sys.xfmrS7 => "generator-$(X)2-1") ## WORKS FOR SERIES

    # Grab the corresponding IC value from Sienna and store in MTK IC dict
    for (name_MTK, name_Sienna) in names_DynamicImpedance_xfmrs
        # Variable name mapping for Sauer & Pai SGs (ref)
        MTK_to_Sienna_DynamicImpedance_xfmrs = Dict(
            name_MTK.id     => :ir_hs, # ir_hs is in gen base, id is in network base - they both flow S to 7
            name_MTK.iq     => :ii_hs, # ii_hs is in gen base, iq is in network base - they both flow S to 7
        )
        for (var_MTK, var_Sienna) in MTK_to_Sienna_DynamicImpedance_xfmrs
            u0_dict[var_MTK] = x0_init_dict[name_Sienna][var_Sienna] * (Sb_gen_2 / Sb_sys)
        end
    end

    # Set dummy derivatives (transformer shunt currents at inverter) to zero
    # (shunt current deriv = sum of the low and high side, both of which are states so d/dt=0)
    # Have to do it this way because the dummy derivatives are not technically affiliated 
    # with subsystems (i.e. sys.xfmrSg_27.idˍt not sys.sys0.xfmr...)
    u0_dict[D(sys.xfmrSg_27.id)] = 0.0
    u0_dict[D(sys.xfmrSg_27.iq)] = 0.0

    # -----------------------------------------------------------------------------------------
    # Transformers - SGs
    # --------------------------------------------------------------------
    # This section is different because we have to back calculate.... 
    # Back calculate the rest of the initial values in the transformer.
    # Roughly the same process for both SG transformers.
    # NOTE: it is a bit lucky/nice that both of these xmfrs are defined in the raw file 
    #  as H>L, so we can have this directional consistency of HS,SG,SL 
    xfmr_dict = Dict(
        :gen1 => Dict(
            :gen => sys.gen1,
            :shuntH => sys.shunt4, # pi line capacitor
            :HS => sys.xfmr4S,  
            :SG => sys.xfmrSg_41,
            :SL => sys.xfmrS1,
            :sienna_gen_name => "generator-$(X)1-1",
            :Sb_gen => Sb_gen_1,
        ),
        :gen3 => Dict(
            :gen => sys.gen3,
            :shuntH => sys.shunt9,  # pi line capacitor
            :HS => sys.xfmr9S,      # High side to Shunt
            :SG => sys.xfmrSg_93,   # Shunt to Ground
            :SL => sys.xfmrS3,      # Shunt to Low side
            :sienna_gen_name => "generator-$(X)3-1",
            :Sb_gen => Sb_gen_3,
        ),
    )

    function DQ_to_dq(δ)
        return [
            sin(δ) cos(δ)
            -cos(δ) sin(δ)
        ]
    end

    for (gen, xfmr) in xfmr_dict
        # Roughly following the causalized order since we have the sienna ICs already

        # stator IdIq (dq) >> iLS (ri) >> * >> iSH (ri)
        #                                 v
        #                              iSG (ri)
        #   (1) Id,Iq = f(:e_p,:ψ,:ψ_pp) 
        #   (2) iLS = f(:δ,Id,Iq) 
        #   (3) iSH = (:ir_hs, :ii_hs)
        #   (4) iSG = f(iLS,iSH)

        # Get parameters
        Sb_gen = xfmr[:Sb_gen] #ModelingToolkit.getdefault(xfmr[:gen].Sb_gen)
        X_HS = ModelingToolkit.getdefault(xfmr[:HS].X)
        X_SL = ModelingToolkit.getdefault(xfmr[:SL].X)
        R_HS = ModelingToolkit.getdefault(xfmr[:HS].R)
        R_SL = ModelingToolkit.getdefault(xfmr[:SL].R)
        if (instance==0 && gen == :gen1)
            δ = x0_init_dict["generator-1-1"][:δ] # not available in u0_dict because not a state variable
        else
            δ = u0_dict[xfmr[:gen].δ]
        end

        # (1) Solve for stator > xfmr interface current - generator RF (Id,Iq)
        R = ModelingToolkit.getdefault(xfmr[:gen].R)
        Xd_pp = ModelingToolkit.getdefault(xfmr[:gen].Xd_pp)
        Xq_pp = ModelingToolkit.getdefault(xfmr[:gen].Xq_pp)
        Xd_p = ModelingToolkit.getdefault(xfmr[:gen].Xd_p)
        Xq_p = ModelingToolkit.getdefault(xfmr[:gen].Xq_p)
        Xl = ModelingToolkit.getdefault(xfmr[:gen].Xl)
        γd1 = (Xd_pp - Xl) / (Xd_p - Xl)
        γq1 = (Xq_pp - Xl) / (Xq_p - Xl)
        γd2 = (1 - γd1) / (Xd_p - Xl)
        γq2 = (1 - γq1) / (Xq_p - Xl)
        ω = u0_dict[xfmr[:gen].ω]
        eq_p = u0_dict[xfmr[:gen].eq_p]
        ed_p = u0_dict[xfmr[:gen].ed_p]
        ψd = u0_dict[xfmr[:gen].ψd]
        ψq = u0_dict[xfmr[:gen].ψq]
        ψd_pp = u0_dict[xfmr[:gen].ψd_pp]
        ψq_pp = u0_dict[xfmr[:gen].ψq_pp]
        Id = (1.0 / Xd_pp) * (γd1 * eq_p - ψd + (1 - γd1) * ψd_pp)   #15.15 explicit form, injected into grid 
        Iq = (1.0 / Xq_pp) * (-γq1 * ed_p - ψq + (1 - γq1) * ψq_pp)  # NOTE: Id /Iq in most literature 
        
        # (2) Solve for the stator current but in the network rf 
        iLS = DQ_to_dq(δ) * [Id; Iq]
        iLS_d = iLS[1]
        iLS_q = iLS[2]
        
        # (3) Get current in 9S transformer - network RF (dq) (match to sienna sign convention for now, fix when building ICs)
        # In Sienna, these currents are in the network RF (dq) but the generator base (Sb_gen)
        # In Sienna, the xfmr states are also in Sb_gen, so do all these calcs in Sb_gen
        # >> network reference frame current injected into the grid at bus 9, so same direction as shunt to H (note later we use switch to H>S)
        iSH_d = x0_init_dict[xfmr[:sienna_gen_name]][:ir_hs] 
        iSH_q = x0_init_dict[xfmr[:sienna_gen_name]][:ii_hs]

        # (4) Solve for xfmr shunt (S to G) - network RF (dq) gen base (Sb_gen)
        iSG_d = iLS_d - iSH_d
        iSG_q = iLS_q - iSH_q

        # Get xfmr shunt voltage at equilibrium - network RF (dq) gen base (Sb_gen)
        vH_d = u0_dict[xfmr[:shuntH].vd]
        vH_q = u0_dict[xfmr[:shuntH].vq]
        vS_d = -(- vH_d - (R_HS * iSH_d) + (X_HS * iSH_q))  # these are V_3R and V_3I in the sienna implementation. 
        vS_q = -(- vH_q - (R_HS * iSH_q) - (X_HS * iSH_d))

        # Solve for stator > xfmr interface voltage - network RF (dq), gen base (Sb_gen), because .vd/.vq
        vL_d = -(- vS_d - (R_SL*iLS_d) + (X_SL*iLS_q))
        vL_q = -(- vS_q - (R_SL*iLS_q) - (X_SL*iLS_d))

        # Solve for stator > xfmr interface voltage - gen RF, gen base (Sb_gen)
        VL_d = vL_d * sin(δ) - vL_q * cos(δ)
        VL_q = vL_d * cos(δ) + vL_q * sin(δ)

        # Set the initial conditions of differential variables
        # -----------------------------------------------------
        # Gen 3             Gen 1
        # xfmr9S₊id(t)      xfmr4S₊id(t)    = Needs to be network RF, Sb_sys. Use Sienna's :ir_hs, which is in network RF but Sb_gen.
        # xfmr9S₊iq(t)      xfmr4S₊iq(t)    = Needs to be network RF, Sb_sys. Use Sienna's :ii_hs, which is in network RF but Sb_gen.
        # xfmrSg_93₊id(t)   xfmrSg_41₊id(t) = Needs to be in network RF. Back calculate from :ir_hs
        # xfmrSg_93₊iq(t)   xfmrSg_41₊iq(t) = Needs to be in network RF. Back calculate from :ir_hs
        # >> In MTK, id and iq are the connection currents so they are always in the network base !!! 
        # >> All of the gen interface impedances and currents from Sienna are in Sb_gen, so we did our calcs in that 
        u0_dict[xfmr[:HS].id] = (Sb_gen/Sb_sys) * (-iSH_d)
        u0_dict[xfmr[:HS].iq] = (Sb_gen/Sb_sys) * (-iSH_q)
        u0_dict[xfmr[:SG].id] = (Sb_gen/Sb_sys) * iSG_d
        u0_dict[xfmr[:SG].iq] = (Sb_gen/Sb_sys) * iSG_q

        # Set the initial conditions of algebraic variables
        # -----------------------------------------------------
        # Gen 3         Gen 1
        # gen3₊vd(t)                    = vL_d (terminal voltage in network RF)
        # gen3₊vq(t)    gen1₊vq(t)      = vL_q
        # gen3₊Id(t)    gen1₊Id(t)      use stator equation w/ ψ, keep in Sb_gen
        # gen3₊Iq(t)                    use stator equation w/ ψ
        # gen3₊Iqˍt(t)                  = 0
        #               gen1₊iqˍt(t)    = 0 MAYBE THIS IS NOT ZERO ??? = Id sin(δ) + iIq cos(δ)
        #               gen1₊Idˍt(t)    = 0
        u0_dict[xfmr[:gen].vq] = vL_q  # vq is in the network RF (pin value), as is vL_q  
        u0_dict[xfmr[:gen].Id] = Id
        if !(instance=="" && gen==:gen1)  # everything except ref bus I think?
            u0_dict[xfmr[:gen].vd] = vL_d
            u0_dict[xfmr[:gen].Iq] = Iq
        end

        # Set sg xfmr dummy derivative values 
        #gen_str = string(gen) # e.g. "gen1", "gen2"
        if (instance==0 && gen == :gen1)
            u0_dict[D(xfmr[:gen].iq)] = 0.0
            u0_dict[D(xfmr[:gen].Id)] = -(2*pi*60.0/Xd_pp) * (R*Id + ω*ψq + VL_d) # I think these ended up being zero after all
        else
            #try
            u0_dict[D(xfmr[:gen].Iq)] = -(2*pi*60.0/Xq_pp) * (R*Iq - ω*ψd + VL_q) # I think these ended up being zero after all
            #catch
            #    println("Didn't find $(gen_str)₊Iqˍt in instance $(instance)")
            #end
        end

        # We don't need ψd,ψq anymore because they aren't MTK states.
        delete!(u0_dict, xfmr[:gen].ψd)
        delete!(u0_dict, xfmr[:gen].ψq)
    end

    return u0_dict

end

# -----------------------------------------------------------------------------------------
# Build dict of mtk names and state indices
# -----------------------------------------------------------------------------------------
function make_var_to_index_map_mtk(sys)
    mtk_map = Dict{String, Int64}()
    for i in 1:length(unknowns(sys))
        var = unknowns(sys)[i]
        var = string(var)
        var = replace(var,"(t)" => "")
        var = replace(var,"₊" => "_")
        mtk_map[var] = i
    end
    return mtk_map
end

# -----------------------------------------------------------------------------------------
# Evaluate jacobian at the initial condition
# -----------------------------------------------------------------------------------------
function get_jacobian_evaluated_at_u0_forwarddiff(prob, p0)
    t0 = prob.tspan[1]
    function diff_function(u)
        du = zero(u)
        prob.f(du,u,p0,t0)
        du
    end
    return ForwardDiff.jacobian(diff_function, prob.u0)
end

# -----------------------------------------------------------------------------------------
# Evaluate jacobian at the initial condition
# -----------------------------------------------------------------------------------------
function get_jacobian_evaluated_at_u0_symbolic(prob, p0)
    # Just wrapping this to avoid global scope slowdowns
    return prob.f.jac(prob.u0, p0, prob.tspan[1])
end

# -----------------------------------------------------------------------------------------
# Calculate eigenvalues of reduced matrix
# -----------------------------------------------------------------------------------------
function calculate_reduced_eigenvalues(A, diff_count, alg_count)
    # Build reduced Jacobian using schur complement (only possible w/ index-1)
    idx1 = 1:diff_count
    idx2 = (diff_count+1):(diff_count+alg_count)
    J11 = A[idx1,idx1] # ∂f/∂x
    J12 = A[idx1,idx2] # ∂f/∂z
    J21 = A[idx2,idx1] # ∂g/∂x
    J22 = A[idx2,idx2] # ∂g/∂z  (nonsingular if system is index-1)

    # Calculate schur complement efficiently:
    #   A_red = J11 - J12 * inv(J22) * J21
    J22_fact = factorize(J22)  # factorize to make inverse faster
    X = J22_fact \ Matrix(J21) # linear solve of J22*X = J21 to get X = inv(J22)*J21
    # ^NOTE: for A\b, A can be sparse, but b cannot. Since Matrix(J21) is dense, X is dense
    A_red = J11 - J12 * X      # finally, evaluate schur complement (since X is dense, A_red is dense)
    
    # Return eigenvalues
    return eigvals(A_red)
end

# -----------------------------------------------------------------------------------------
# Build MTK model using Sienna initial conditions
# -----------------------------------------------------------------------------------------
function build_MTK_model(SYSTEM, x0, sp, bridges)
    @suppress_err begin # this is just to suppress the warning about flow variables from MTK since it overwhelms the terminal output
    # -------------------------------------------------------------------------------------
    # Build MTK sys
    # -------------------------------------------------------------------------------------
    # Get info about this specific system 
    instance_list = _get_9bus_instances(SYSTEM) # e.g. 36Bus => four 9Bus instances => [0,1,2,3]

    # Declare vectors to fill as we loop through 
    subsystems = Vector{ODESystem}()   # subsystems that will combine to make full MTK system (9buses and bridges)
    connections = Vector{Equation}()  # connections that dictate how to connect those subsystems 
    dict_9bus_subsystems = Dict{Int64,ODESystem}() # e.g. 1 => sys1 (where sys1 is the actual subsystem object)    
    
    # (1) Build 9Bus subsystems 
    for inst in instance_list
        println("Starting build of 9Bus instance $(inst)...")

        # Get set points for this particular instance
        gen_sp = _build_params_gen_setpoints(sp, inst);
        load_v = _build_params_load_voltages(x0, inst);

        # Define instance-based name for this new subsystem (useful once it is a part of the full system)
        # e.g. if full system is `sys` and subsystem_name is `sys1`, we can access it with `sys.sys1`
        subsystem_name = Symbol("sys", inst) # e.g. sys0, sys1, sys2, ...

        # Build MTK 9Bus instance 
        if inst == 0
            # Reference bus is always located in 9Bus instance 0 @ generator-1-1
            subsystem = Model9Bus_2sg1inv(; 
                name = subsystem_name,
                # Gen base powers 
                Sb_gen_1 = gen_sp["generator-1-1"]["Sb_gen"],
                Sb_gen_2 = gen_sp["generator-2-1"]["Sb_gen"],
                Sb_gen_3 = gen_sp["generator-3-1"]["Sb_gen"],
                # Gen 1 reference angle (Model9Bus_2sg1inv only)
                δ_ref = x0["generator-1-1"][:δ], 
                # Gen 1 set points (sg)
                V_ref_1 = gen_sp["generator-1-1"]["V_ref"],
                τm0_1 = gen_sp["generator-1-1"]["τm0"],
                # Gen 2 set points (inv)
                V_ref_2 = gen_sp["generator-2-1"]["V_ref"], 
                ω_ref_2 = gen_sp["generator-2-1"]["ω_ref"], 
                p_ref_2 = gen_sp["generator-2-1"]["P_ref"], 
                q_ref_2 = gen_sp["generator-2-1"]["Q_ref"],
                # Gen 3 set points (sg)
                V_ref_3 = gen_sp["generator-3-1"]["V_ref"],
                τm0_3 = gen_sp["generator-3-1"]["τm0"],
                # Load voltage set points
                V_5 = [load_v["V_5"][:R], load_v["V_5"][:I]],
                V_6 = [load_v["V_6"][:R], load_v["V_6"][:I]],
                V_8 = [load_v["V_8"][:R], load_v["V_8"][:I]],
                );
        else 
            # All other 9Bus instances do not have reference 
            # e.g. @named sys1 = Model9Bus_2sg1inv_NoRefBus();
            subsystem = Model9Bus_2sg1inv_NoRefBus(;
                name = subsystem_name, 
                # Gen base powers 
                Sb_gen_1 = gen_sp["generator-1-1"]["Sb_gen"],
                Sb_gen_2 = gen_sp["generator-2-1"]["Sb_gen"],
                Sb_gen_3 = gen_sp["generator-3-1"]["Sb_gen"],
                # Gen 1 set points (sg)
                V_ref_1 = gen_sp["generator-1-1"]["V_ref"],
                τm0_1 = gen_sp["generator-1-1"]["τm0"],
                # Gen 2 set points (inv)
                V_ref_2 = gen_sp["generator-2-1"]["V_ref"], 
                ω_ref_2 = gen_sp["generator-2-1"]["ω_ref"], 
                p_ref_2 = gen_sp["generator-2-1"]["P_ref"], 
                q_ref_2 = gen_sp["generator-2-1"]["Q_ref"],
                # Gen 3 set points (sg)
                V_ref_3 = gen_sp["generator-3-1"]["V_ref"],
                τm0_3 = gen_sp["generator-3-1"]["τm0"],
                # Load voltage set points
                V_5 = [load_v["V_5"][:R], load_v["V_5"][:I]],
                V_6 = [load_v["V_6"][:R], load_v["V_6"][:I]],
                V_8 = [load_v["V_8"][:R], load_v["V_8"][:I]],
                );
        end
        
        # Add subsystem to list of subsystems
        push!(subsystems, subsystem)
        dict_9bus_subsystems[inst] = subsystem
    end

    # (2) Build bridges between instances 
    # TODO: See notes in SystemDefinitions_MTK.jl > Bridge_SeriesImpedance()
    println("Starting bridges...")
    for (key,values) in bridges 
        # Grab bridge info
        instX = values[:from_inst]
        instY = values[:to_inst]
        busX = values[:from_bus]
        busY = values[:to_bus]

        # Get subsystems we created above
        sysX = dict_9bus_subsystems[instX]
        sysY = dict_9bus_subsystems[instY]

        # Define bridge subsystem 
        bridgeXY = Bridge_SeriesImpedance(;name = key) # e.g. bridge01

        # Update B at the connecting buses to include bridge shunt susceptance 
        B_bridge = 0.0745; # shunt B value for just one side of the pi line
        shuntX = ModelingToolkit.getproperty(sysX, Symbol("shunt", busX)) # these are the actual objects!
        shuntY = ModelingToolkit.getproperty(sysY, Symbol("shunt", busY)) # these are the actual objects!
        shuntX.B = ModelingToolkit.getdefault(shuntX.B) + B_bridge
        shuntY.B = ModelingToolkit.getdefault(shuntY.B) + B_bridge

        # Define connection that dictates how bridge interacts with the other subsystems
        connectionXY_X = connect(bridgeXY.lineFT.p, shuntX.p)
        connectionXY_Y = connect(bridgeXY.lineFT.n, shuntY.p)

        # Add bridge to list of subsystems
        push!(subsystems, bridgeXY)

        # Add connections to list of connections
        push!(connections, connectionXY_X)
        push!(connections, connectionXY_Y)
    end

    # Build full system
    println("Building full system...")
    @mtkbuild sys = ODESystem(
        connections, t;
        systems=subsystems
    )

    # -------------------------------------------------------------------------------------
    # Build MTK initial conditions
    # -------------------------------------------------------------------------------------
    u0_dict = Dict{Union{SymbolicUtils.BasicSymbolic{Real},Num}, Float64}() # this will include all subsystems (9Bus instances and bridges)

    # Get initial conditions from Sienna for each subsystem
    for inst in instance_list
        subsystem = dict_9bus_subsystems[inst] # e.g. sys0, sys1, sys2, ...
        gen_sp = _build_params_gen_setpoints(sp, inst);
        Sb_gens = Vector{Float64}([
            gen_sp["generator-1-1"]["Sb_gen"], 
            gen_sp["generator-2-1"]["Sb_gen"], 
            gen_sp["generator-3-1"]["Sb_gen"]
            ])
        u0_dictINST = _build_initial_condition_dict_MTK_from_Sienna(subsystem, x0, Sb_gens; instance=inst);
        merge!(u0_dict, u0_dictINST)
    end
    # Get initial conditions from Sienna for each bridge line
    for (key,values) in bridges 
        bridgeXY = key # e.g. bridge01, bridge02, ...
        sienna_name = values[:sienna_name]
        u0_dictB = Dict{Union{SymbolicUtils.BasicSymbolic{Real},Num}, Float64}(
            unknowns(sys)[findfirst(x -> occursin("$(bridgeXY)₊lineFT₊id",x), string.(unknowns(sys)))] => x0[sienna_name][:Il_R],
            unknowns(sys)[findfirst(x -> occursin("$(bridgeXY)₊lineFT₊iq",x), string.(unknowns(sys)))] => x0[sienna_name][:Il_I],
        );
        merge!(u0_dict, u0_dictB)
    end

    return (sys, u0_dict)
    end # suppress
end