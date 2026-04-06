include(joinpath(dirname(@__FILE__), "ComponentDefinitions_MTK.jl"))
using .ComponentDefinitions_MTK: GroundDQ, GenModelRef, GenModel, InvModel, 
    DynamicCapacitorDQ, DynamicImpedanceDQ, StaticImpedanceDQ, LoadConstantImpedance, 
    DynamicTransformerSeries_ωL, DynamicTransformerSeries_X 

# -----------------------------------------------------------------------------------------
# 9Bus with generator-1-1 as the reference (i.e. fixed δ)
# -----------------------------------------------------------------------------------------
@mtkmodel Model9Bus_2sg1inv begin
    @parameters begin
        ω0 = 2*pi*60.0    # [rad/s] angular frequency of rotating network reference frame
        Sb_sys = 100.0    # [MVA] system base power
        Sb_gen_1          # [MVA] gen 1 base power
        Sb_gen_2          # [MVA] gen 1 base power
        Sb_gen_3          # [MVA] gen 1 base power
        # Gen 1 set points (sg)
        δ_ref             # Ref angle (not in Model9Bus_2sg1inv_NoRef)
        V_ref_1
        τm0_1
        # Gen 2 set points (inv)
        V_ref_2
        ω_ref_2
        p_ref_2
        q_ref_2
        # Gen 3 set points (sg)
        V_ref_3
        τm0_3
        # Load voltage set points
        V_5[1:2]          # bus 5 [:R,:I]
        V_6[1:2]          # bus 6 [:R,:I]
        V_8[1:2]          # bus 8 [:R,:I]
    end 
    @components begin
        # Buses
        shunt4 = DynamicCapacitorDQ(ω0=ω0, B = 0.088 + 0.079)
        shunt5 = DynamicCapacitorDQ(ω0=ω0, B = 0.088 + 0.153)
        shunt6 = DynamicCapacitorDQ(ω0=ω0, B = 0.079 + 0.179)
        shunt7 = DynamicCapacitorDQ(ω0=ω0, B = 0.0745 + 0.153)
        shunt8 = DynamicCapacitorDQ(ω0=ω0, B = 0.1045 + 0.0745)
        shunt9 = DynamicCapacitorDQ(ω0=ω0, B = 0.1045 + 0.179)
        # Lines
        line54 = DynamicImpedanceDQ(ω0=ω0, R = 0.01,   X = 0.068)
        line78 = DynamicImpedanceDQ(ω0=ω0, R = 0.0085, X = 0.0576)
        line64 = DynamicImpedanceDQ(ω0=ω0, R = 0.017,  X = 0.092)
        line75 = DynamicImpedanceDQ(ω0=ω0, R = 0.032,  X = 0.161)
        line89 = DynamicImpedanceDQ(ω0=ω0, R = 0.0119, X = 0.1008)
        line96 = DynamicImpedanceDQ(ω0=ω0, R = 0.039,  X = 0.1738)
        # ----------
        # Transformers - INV + T-transformer + static transformer || SG + T-transformer
        xfmr4S = DynamicTransformerSeries_X(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_1, 
            R = 0.02, X = 0.05)  # impedances are in Sb_gen (not Sb_sys)
        xfmrS1 = DynamicTransformerSeries_X(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_1, 
            R = 0.02, X = 0.05) # impedances are in Sb_gen (not Sb_sys)
        xfmrSg_41 = DynamicTransformerSeries_X(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_1,
            R = 60.0, X = 150.0) # impedances are in Sb_gen (not Sb_sys)
        # NOTE THAT THIS XFMR IS A DIFFERENT SIGN CONVENTION THAN TEH OTHER TWO ... 2 -> S, S -> 7, ALSO FILTER HAS omegaL
        xfmr2S = DynamicTransformerSeries_ωL(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_2, 
            R = 0.01, L = 0.2)
        xfmrSg_27 = DynamicTransformerSeries_X(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_2,
            R = 60.0, X = 150.0) # impedances are in Sb_gen (not Sb_sys)
        xfmrS7 = DynamicTransformerSeries_X(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_2, 
            R = 0.02, X = 0.05)  # impedances are in Sb_gen (not Sb_sys)
        xfmr9S = DynamicTransformerSeries_X(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_3, 
            R = 0.02, X = 0.05)  # impedances are in Sb_gen (not Sb_sys)
        xfmrS3 = DynamicTransformerSeries_X(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_3, 
            R = 0.02, X = 0.05) # impedances are in Sb_gen (not Sb_sys)
        xfmrSg_93 = DynamicTransformerSeries_X(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_3,
            R = 60.0, X = 150.0) # impedances are in Sb_gen (not Sb_sys)
        # ----------
        # Loads
        load5 = LoadConstantImpedance(
            P = 1.25, Q = 0.5, 
            vd0 = V_5[1], vq0 = V_5[2],
            )
        load6 = LoadConstantImpedance(
            P = 0.9,  Q = 0.3, 
            vd0 = V_6[1], vq0 = V_6[2], 
            )
        load8 = LoadConstantImpedance(
            P = 1.0,  Q = 0.35, 
            vd0 = V_8[1], vq0 = V_8[2], 
            )
        # Gens 
        gen1 = GenModelRef(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_1, 
            V_ref=V_ref_1,
            τm0=τm0_1, # τm0 = P_ref*eff, assuming eff=1
            δ = δ_ref
            )
        gen2 = InvModel(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_2, 
            ω_ref=ω_ref_2, 
            v_ref=V_ref_2, 
            p_ref=p_ref_2, 
            q_ref=q_ref_2, 
            )
        gen3 = GenModel(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_3, 
            V_ref=V_ref_3, 
            τm0=τm0_3, 
            )
        # Ground
        ground = GroundDQ()
    end
    @equations begin
        # NOTE: each "connect" adds algebraic equations defining the voltages as equal and the currents as equal/opposite
        # Bus 1
        connect(ground.g, gen1.n)  # >>> match based on high/low voltage - current sign convention is adjusted in eqs
        #connect(gen1.p, xfmr41.n)
        connect(gen1.p, xfmrS1.n)
        connect(xfmrS1.p, xfmr4S.n)
        connect(xfmrS1.p, xfmrSg_41.p)
        connect(xfmrSg_41.n, ground.g)
        # Bus 2
        connect(ground.g, gen2.n)
        #connect(gen2.p, xfmr27.p) ### IF JUST THE FILTER.
        connect(gen2.p, xfmr2S.p)
        connect(xfmr2S.n, xfmrS7.p)
        connect(xfmr2S.n, xfmrSg_27.p)
        connect(xfmrSg_27.n, ground.g)
        # Bus 3
        connect(ground.g, gen3.n)
        #connect(gen3.p, xfmr93.n)
        connect(gen3.p, xfmrS3.n)
        connect(xfmrS3.p, xfmr9S.n)
        connect(xfmrS3.p, xfmrSg_93.p)
        connect(xfmrSg_93.n, ground.g)
        # Bus 4
        connect(shunt4.n, ground.g)
        #connect(shunt4.p, xfmr41.p)
        connect(shunt4.p, xfmr4S.p)
        connect(shunt4.p, line64.n)
        connect(shunt4.p, line54.n)
        # Bus 7
        connect(shunt7.n, ground.g)
        #connect(shunt7.p, xfmrS7.n)
        connect(shunt7.p, xfmrS7.n)
        connect(shunt7.p, line75.p)
        connect(shunt7.p, line78.p)
        # Bus 9
        connect(shunt9.n, ground.g)
        #connect(shunt9.p, xfmr93.p)
        connect(shunt9.p, xfmr9S.p)
        connect(shunt9.p, line89.n)
        connect(shunt9.p, line96.p)
        # Bus 5
        connect(load5.n, ground.g)
        connect(shunt5.n, ground.g)
        connect(shunt5.p, load5.p)
        connect(shunt5.p, line54.p)
        connect(shunt5.p, line75.n)
        # Bus 6
        connect(load6.n, ground.g)
        connect(shunt6.n, ground.g)
        connect(shunt6.p, load6.p)
        connect(shunt6.p, line96.n)
        connect(shunt6.p, line64.p)
        # Bus 8
        connect(load8.n, ground.g)
        connect(shunt8.n, ground.g)
        connect(shunt8.p, load8.p)
        connect(shunt8.p, line78.n)
        connect(shunt8.p, line89.p)
    end
end


# -----------------------------------------------------------------------------------------
# 9Bus with no reference generator
# -----------------------------------------------------------------------------------------
# NOTE: THIS IS NOT A STANDALONE MODEL
@mtkmodel Model9Bus_2sg1inv_NoRefBus begin
    @parameters begin
        ω0 = 2*pi*60.0    # [rad/s] angular frequency of rotating network reference frame
        Sb_sys = 100.0    # [MVA] system base power
        Sb_gen_1          # [MVA] gen 1 base power
        Sb_gen_2          # [MVA] gen 1 base power
        Sb_gen_3          # [MVA] gen 1 base power
        # Gen 1 set points (sg)
        V_ref_1
        τm0_1
        # Gen 2 set points (inv)
        V_ref_2
        ω_ref_2
        p_ref_2
        q_ref_2
        # Gen 3 set points (sg)
        V_ref_3
        τm0_3
        # Load voltage set points
        V_5[1:2]          # bus 5 [:R,:I]
        V_6[1:2]          # bus 6 [:R,:I]
        V_8[1:2]          # bus 8 [:R,:I]
    end 
    @components begin
        # Buses
        shunt4 = DynamicCapacitorDQ(ω0=ω0, B = 0.088 + 0.079)
        shunt5 = DynamicCapacitorDQ(ω0=ω0, B = 0.088 + 0.153)
        shunt6 = DynamicCapacitorDQ(ω0=ω0, B = 0.079 + 0.179)
        shunt7 = DynamicCapacitorDQ(ω0=ω0, B = 0.0745 + 0.153)
        shunt8 = DynamicCapacitorDQ(ω0=ω0, B = 0.1045 + 0.0745)
        shunt9 = DynamicCapacitorDQ(ω0=ω0, B = 0.1045 + 0.179)
        # Lines
        line54 = DynamicImpedanceDQ(ω0=ω0, R = 0.01,   X = 0.068)
        line78 = DynamicImpedanceDQ(ω0=ω0, R = 0.0085, X = 0.0576)
        line64 = DynamicImpedanceDQ(ω0=ω0, R = 0.017,  X = 0.092)
        line75 = DynamicImpedanceDQ(ω0=ω0, R = 0.032,  X = 0.161)
        line89 = DynamicImpedanceDQ(ω0=ω0, R = 0.0119, X = 0.1008)
        line96 = DynamicImpedanceDQ(ω0=ω0, R = 0.039,  X = 0.1738)
        # ----------
        # Transformers - INV + T-transformer + static transformer || SG + T-transformer
        xfmr4S = DynamicTransformerSeries_X(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_1, 
            R = 0.02, X = 0.05)  # impedances are in Sb_gen (not Sb_sys)
        xfmrS1 = DynamicTransformerSeries_X(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_1, 
            R = 0.02, X = 0.05) # impedances are in Sb_gen (not Sb_sys)
        xfmrSg_41 = DynamicTransformerSeries_X(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_1,
            R = 60.0, X = 150.0) # impedances are in Sb_gen (not Sb_sys)
        # NOTE THAT THIS XFMR IS A DIFFERENT SIGN CONVENTION THAN TEH OTHER TWO ... 2 -> S, S -> 7, ALSO FILTER HAS omegaL
        xfmr2S = DynamicTransformerSeries_ωL(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_2, 
            R = 0.01, L = 0.2)
        xfmrSg_27 = DynamicTransformerSeries_X(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_2,
            R = 60.0, X = 150.0) # impedances are in Sb_gen (not Sb_sys)
        xfmrS7 = DynamicTransformerSeries_X(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_2, 
            R = 0.02, X = 0.05)  # impedances are in Sb_gen (not Sb_sys)
        xfmr9S = DynamicTransformerSeries_X(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_3, 
            R = 0.02, X = 0.05)  # impedances are in Sb_gen (not Sb_sys)
        xfmrS3 = DynamicTransformerSeries_X(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_3, 
            R = 0.02, X = 0.05) # impedances are in Sb_gen (not Sb_sys)
        xfmrSg_93 = DynamicTransformerSeries_X(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_3,
            R = 60.0, X = 150.0) # impedances are in Sb_gen (not Sb_sys)
        # ----------
        # Loads
        load5 = LoadConstantImpedance(
            P = 1.25, Q = 0.5, 
            vd0 = V_5[1], vq0 = V_5[2],
            )
        load6 = LoadConstantImpedance(
            P = 0.9,  Q = 0.3, 
            vd0 = V_6[1], vq0 = V_6[2], 
            )
        load8 = LoadConstantImpedance(
            P = 1.0,  Q = 0.35, 
            vd0 = V_8[1], vq0 = V_8[2], 
            )
        # Gens 
        gen1 = GenModel(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_1, 
            V_ref=V_ref_1,
            τm0=τm0_1, # τm0 = P_ref*eff, assuming eff=1
            )
        gen2 = InvModel(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_2, 
            ω_ref=ω_ref_2, 
            v_ref=V_ref_2, 
            p_ref=p_ref_2, 
            q_ref=q_ref_2, 
            )
        gen3 = GenModel(
            ω0=ω0, Sb_sys=Sb_sys, 
            Sb_gen=Sb_gen_3, 
            V_ref=V_ref_3, 
            τm0=τm0_3, 
            )
        # Ground
        ground = GroundDQ()
    end
    @equations begin
        # NOTE: each "connect" adds algebraic equations defining the voltages as equal and the currents as equal/opposite
        # Bus 1
        connect(ground.g, gen1.n)  # >>> match based on high/low voltage - current sign convention is adjusted in eqs
        #connect(gen1.p, xfmr41.n)
        connect(gen1.p, xfmrS1.n)
        connect(xfmrS1.p, xfmr4S.n)
        connect(xfmrS1.p, xfmrSg_41.p)
        connect(xfmrSg_41.n, ground.g)
        # Bus 2
        connect(ground.g, gen2.n)
        #connect(gen2.p, xfmr27.p) ### IF JUST THE FILTER.
        connect(gen2.p, xfmr2S.p)
        connect(xfmr2S.n, xfmrS7.p)
        connect(xfmr2S.n, xfmrSg_27.p)
        connect(xfmrSg_27.n, ground.g)
        # Bus 3
        connect(ground.g, gen3.n)
        #connect(gen3.p, xfmr93.n)
        connect(gen3.p, xfmrS3.n)
        connect(xfmrS3.p, xfmr9S.n)
        connect(xfmrS3.p, xfmrSg_93.p)
        connect(xfmrSg_93.n, ground.g)
        # Bus 4
        connect(shunt4.n, ground.g)
        #connect(shunt4.p, xfmr41.p)
        connect(shunt4.p, xfmr4S.p)
        connect(shunt4.p, line64.n)
        connect(shunt4.p, line54.n)
        # Bus 7
        connect(shunt7.n, ground.g)
        #connect(shunt7.p, xfmrS7.n)
        connect(shunt7.p, xfmrS7.n)
        connect(shunt7.p, line75.p)
        connect(shunt7.p, line78.p)
        # Bus 9
        connect(shunt9.n, ground.g)
        #connect(shunt9.p, xfmr93.p)
        connect(shunt9.p, xfmr9S.p)
        connect(shunt9.p, line89.n)
        connect(shunt9.p, line96.p)
        # Bus 5
        connect(load5.n, ground.g)
        connect(shunt5.n, ground.g)
        connect(shunt5.p, load5.p)
        connect(shunt5.p, line54.p)
        connect(shunt5.p, line75.n)
        # Bus 6
        connect(load6.n, ground.g)
        connect(shunt6.n, ground.g)
        connect(shunt6.p, load6.p)
        connect(shunt6.p, line96.n)
        connect(shunt6.p, line64.p)
        # Bus 8
        connect(load8.n, ground.g)
        connect(shunt8.n, ground.g)
        connect(shunt8.p, load8.p)
        connect(shunt8.p, line78.n)
        connect(shunt8.p, line89.p)
    end
end


# -----------------------------------------------------------------------------------------
# Single dynamic pi-line to connect two 9bus models
# -----------------------------------------------------------------------------------------
# NOTE: THIS IS NOT A STANDALONE MODEL. 
# For example, to connect Bus From to Bus 5 in an instance of Model9Bus (sys1) and Bus To
# to Bus 5 in another instance of Model9Bus (sys2), you need these connections:
#   connections = [
#       connect(bridge.shuntF.p, sys1.shunt5.p)
#       connect(bridge.shuntT.p, sys2.shunt5.p)
#       connect(bridge.ground.g, sys1.ground.g)
#       connect(bridge.ground.g, sys2.ground.g)
#   ]
# TODO: THIS APPROACH DIDN'T WORK THE WAY I WANTED IT TO. MTK was not able to automatically
# combine the shunt capacitances between the two models (maybe because it doesn't know 
# that is ok in a circuit?) So that led to structural singularities that forced me to 
# find initial conditions for shunt current (instead of voltage), which I don't want to do.
@mtkmodel Bridge_PiLine begin
    @parameters begin
        Sb_sys = 100.0    # [MVA] system base power
        ω0 = 2*pi*60.0    # [rad/s] angular frequency of rotating network reference frame
    end 
    @components begin
        # NOTE: These values match the bridge lines used in https://doi.org/10.1016/j.epsr.2022.108562
        # NOTE: B values are the shunt capacitance contributed by this line only, so each
        # B value (node From and node To) will combine in parallel with the shunt 
        # capacitance at the node we connect them to (e.g. Node 5 in one of the 9bus models).
        lineFT = DynamicImpedanceDQ(ω0=ω0, R = 0.0085, X = 0.0576)
        shuntF = DynamicCapacitorDQ(ω0=ω0, B = 0.0745)
        shuntT = DynamicCapacitorDQ(ω0=ω0, B = 0.0745)
        ground = GroundDQ()
    end
    @equations begin
        # Bus "From"
        connect(shuntF.n, ground.g)
        connect(shuntF.p, lineFT.p)
        # Bus "To"
        connect(shuntT.n, ground.g)
        connect(shuntT.p, lineFT.n)        
    end
end


# -----------------------------------------------------------------------------------------
# Single dynamic impedance to connect two 9bus models
# -----------------------------------------------------------------------------------------
# NOTE: THIS IS NOT A STANDALONE MODEL. 
# For example, to connect Bus From to Bus 5 in an instance of Model9Bus (sys1) and Bus To
# to Bus 5 in another instance of Model9Bus (sys2), you need these connections:
#   connections = [
#       connect(bridge.lineFT.p, sys0.shunt5.p)
#       connect(bridge.lineFT.n, sys1.shunt5.p)
#   ]
# TODO: This is the approach I am taking for now. The shunt capacitances from the pi line
# definition still need to be accounted for, so I am adding them manually to the shunt 
# parameters in the adjacent subsystem models. This prevents the structural singularity. 
@mtkmodel Bridge_SeriesImpedance begin
    @parameters begin
        Sb_sys = 100.0    # [MVA] system base power
        ω0 = 2*pi*60.0    # [rad/s] angular frequency of rotating network reference frame
    end 
    @components begin
        # NOTE: These values match the bridge lines used in https://doi.org/10.1016/j.epsr.2022.108562
        lineFT = DynamicImpedanceDQ(ω0=ω0, R = 0.0085, X = 0.0576)
    end
end