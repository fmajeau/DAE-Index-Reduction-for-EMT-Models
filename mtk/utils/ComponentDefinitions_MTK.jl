module ComponentDefinitions_MTK
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D

# -----------------------------------------------------------------------------------------
# New connector type: PinDQ
# -----------------------------------------------------------------------------------------
# When two components are "connect()"-ed via one of these connectors, these vars are equated
# Thus, one connection with this connector adds 5 equations
@connector PinDQ begin
    vd(t)                  # [pu] q-axis voltage at node
    vq(t)                  # [pu] q-axis voltage at node
    ωs(t)                  # [pu] reference frequency
    id(t), [connect=Flow]  # [pu] d-axis current out of node
    iq(t), [connect=Flow]  # [pu] q-axis current out of node
end


# -----------------------------------------------------------------------------------------
# New component type: GroundDQ
# -----------------------------------------------------------------------------------------
# This defines the reference point for all voltages in order to ensure a unique solution.
# 4 state variables:
#   4 from 1 PinDQ: vd, v1, id, iq
# 2 algebraic equations
@mtkmodel GroundDQ begin
    @components begin
        g = PinDQ()
    end
    @equations begin
        g.vd ~ 0
        g.vq ~ 0
    end
end


# -----------------------------------------------------------------------------------------
# New component type: OnePortDQ
# -----------------------------------------------------------------------------------------
# 12 state variables: 
#   8 from 2 Pins:  p.vd, p.vq, p.id, n.iq, n.vd, n.vq, n.id, n.iq
#   4 from @variables: vd, dq, id, iq
# 6 algebraic equations
@mtkmodel OnePortDQ begin
    @components begin
        p = PinDQ()
        n = PinDQ()
    end
    @variables begin
        vd(t)  # d-axis voltage across the component
        vq(t)  # q-axis voltage across the component
        id(t)  # d-axis current through the component
        iq(t)  # q-axis current through the component
        ωs(t)  # reference frequency
    end
    @equations begin
        vd ~ p.vd - n.vd    # voltage across component (positive current is p->n, so voltage must be [p-n])
        vq ~ p.vq - n.vq    # ^
        0 ~ p.id + n.id     # current flowing into component also flows out
        0 ~ p.iq + n.iq     # ^
        id ~ p.id           # define the sign convention (current thru component is current into pos node)
        iq ~ p.iq           # ^
        ωs ~ p.ωs           # arbitrarily set the component reference frequency using the positive pin
        0 ~ p.ωs - n.ωs     # the entire component has the same reference angular velocity 
    end
end


# -----------------------------------------------------------------------------------------
# Extension of OnePortDQ: DynamicImpedanceDQ
# -----------------------------------------------------------------------------------------
# *** USE THIS FOR LINES AND INDEX-1 TRANSFORMERS!
# 12 state variables (inherited from OnePortDQ)
# 8 equations
#   6 algebraic equations (inherited from OnePortDQ)
#   2 differential equations (custom to this component)
@mtkmodel DynamicImpedanceDQ begin
    @extend OnePortDQ()
    @parameters begin
        ω0
        R = 1.0
        X = 1.0
    end
    @equations begin
        # In Sienna, dynamic lines do not have freq dependent impedances.
        D(id) ~ (ω0/X) * (vd - (R*id) + (X*iq))
        D(iq) ~ (ω0/X) * (vq - (R*iq) - (X*id))
    end
end

# -----------------------------------------------------------------------------------------
# Extension of OnePortDQ: DynamicTransformerSeries
# -----------------------------------------------------------------------------------------
# *** USE THIS FOR LINES AND INDEX-1 TRANSFORMERS!
# 12 state variables (inherited from OnePortDQ)
# 8 equations
#   6 algebraic equations (inherited from OnePortDQ)
#   2 differential equations (custom to this component)
# NOTE: in order to match Sienna, I am modeling these in the generator base (like I did in Sienna).
# This is true for the LCL filter and SG+T transformer Sienna implementations. Thus I have to
# define iD,iQ here. The connections in MTK are made with id,iq, which are in the network RF.
@mtkmodel DynamicTransformerSeries_ωL begin
    @extend OnePortDQ()
    @parameters begin
        ω0              # [rad/s] GLOBAL
        Sb_sys          # [MVA] GLOBAL
        Sb_gen          # [MVA]
        R = 1.0         # in Sb_gen
        L = 1.0         # in Sb_gen
    end
    @variables begin
        iD(t)
        iQ(t)
    end
    @equations begin
        iD ~ (Sb_sys/Sb_gen)*id 
        iQ ~ (Sb_sys/Sb_gen)*iq
        D(iD) ~ (ω0/L) * (vd - (R*iD) + (ωs*L*iQ))
        D(iQ) ~ (ω0/L) * (vq - (R*iQ) - (ωs*L*iD))
    end
end

# Used this for all inductors in sg+T models, and for the shunt and high side inductor 
# in the inverter model. Sienna models the second L of LCL with the time dependent
# inductance so I did too. 
# TODO: It is admittedly weird to mix and match so maybe chance that at some point. 
@mtkmodel DynamicTransformerSeries_X begin
    @extend OnePortDQ()
    @parameters begin
        ω0              # [rad/s] GLOBAL
        Sb_sys          # [MVA] GLOBAL
        Sb_gen          # [MVA]
        R = 1.0         # in Sb_gen
        X = 1.0         # in Sb_gen
    end
    @variables begin
        iD(t) # in Sb_gen (while id is in Sb_sys)
        iQ(t) # in Sb_gen (while iq is in Sb_sys)
    end
    @equations begin
        iD ~ (Sb_sys/Sb_gen)*id # pos to neg in gen base network RF
        iQ ~ (Sb_sys/Sb_gen)*iq
        D(iD) ~ (ω0/X) * (vd - (R*iD) + (X*iQ))
        D(iQ) ~ (ω0/X) * (vq - (R*iQ) - (X*iD))
    end
end


# -----------------------------------------------------------------------------------------
# Extension of OnePortDQ: StaticImpedanceDQ
# -----------------------------------------------------------------------------------------
# *** USE THIS FOR ALGEBRAIC TRANSFORMERS
# 12 state variables (inherited from OnePortDQ)
# 8 equations
#   6 algebraic equations (inherited from OnePortDQ)
#   2 algebraic equations (custom to this component)
@mtkmodel StaticImpedanceDQ begin
    @extend OnePortDQ()
    @parameters begin
        R = 1.0
        X = 1.0
    end
    @equations begin
        0 ~ vd - (R*id) + (X*iq)
        0 ~ vq - (R*iq) - (X*id)
    end
end

# -----------------------------------------------------------------------------------------
# Extension of OnePortDQ: LoadConstantPower
# -----------------------------------------------------------------------------------------
# *** USE THIS FOR CONSTANT IMPEDANCE LOADS
# 12 state variables (inherited from OnePortDQ)
# 8 equations
#   6 algebraic equations (inherited from OnePortDQ)
#   2 algebraic equations (custom to this component)
@mtkmodel LoadConstantPower begin #StaticImpedanceDQPower
    @extend OnePortDQ()
    @parameters begin
        P = 1.0
        Q = 1.0
    end
    @equations begin
        # NOTE: If we manually solve for id and iq, as in Sienna (see link), then this  
        #   model becomes index-0 because there are not algebraic loops. I.e., it can 
        #   become an ODEProblem with a nonsingular mass matrix without index reduction.
        #   https://github.com/NREL-Sienna/PowerSimulationsDynamics.jl/blob/main/src/models/load_models.jl#L67-L68
        id ~ (1/((vd^2) + (vq^2)))*(P*vd + Q*vq)
        iq ~ (1/((vd^2) + (vq^2)))*(P*vq - Q*vd)
        # NOTE: If we use id and iq in their coupled form, then this model becomes index-1
        #    because there are algebraic loops. In other words, it can only become an 
        #    ODEProblem with a singluar mass matrix without index reduction.
        #0 ~ vd*id + vq*iq - P 
        #0 ~ vq*id - vd*iq - Q
    end
end

# -----------------------------------------------------------------------------------------
# Extension of OnePortDQ: LoadConstantImpedance
# -----------------------------------------------------------------------------------------
# *** USE THIS FOR CONSTANT IMPEDANCE LOADS
# 12 state variables (inherited from OnePortDQ)
# 8 equations
#   6 algebraic equations (inherited from OnePortDQ)
#   2 algebraic equations (custom to this component)
@mtkmodel LoadConstantImpedance begin
    @extend OnePortDQ()
    @parameters begin
        P = 1.0   # active power from PF solution (note - power will change during simulation)
        Q = 1.0   # reactive " "
        vd0 = 1.0 # terminal voltage from PF solution
        vq0 = 0.0 # " "
    end
    @equations begin
        # NOTE: If we manually solve for id and iq, as in Sienna (see link), then this  
        #   model becomes index-0 because there are not algebraic loops. I.e., it can 
        #   become an ODEProblem with a nonsingular mass matrix without index reduction.
        #   https://github.com/NREL-Sienna/PowerSimulationsDynamics.jl/blob/main/src/models/load_models.jl#L67-L68
        id ~ (1/((vd0^2) + (vq0^2)))*(P*vd + Q*vq)
        iq ~ (1/((vd0^2) + (vq0^2)))*(P*vq - Q*vd)
        # NOTE: If we use id and iq in their coupled form, then this model becomes index-1
        #    because there are algebraic loops. In other words, it can only become an 
        #    ODEProblem with a singluar mass matrix without index reduction.
    end
end


# -----------------------------------------------------------------------------------------
# Extension of OnePortDQ: DynamicCapacitorDQ
# -----------------------------------------------------------------------------------------
# TODO: to decide whether to add parallel resistor, look at PSCAD code for reference.
# *** USE THIS FOR BUSES W/ SHUNT CAPS!
# 12 state variables (inherited from OnePortDQ)
# 8 equations
#   6 algebraic equations (inherited from OnePortDQ)
#   2 differential equations (custom to this component)
@mtkmodel DynamicCapacitorDQ begin
    @extend OnePortDQ()
    @parameters begin
        ω0
        B = 1.0 # total per bus, i.e. if Line12 and Line23 lines connect at Bus2, B = (B12/2) + (B23/2)
    end
    @equations begin
        D(vd) ~ (ω0/B) * (id + (B*vq))
        D(vq) ~ (ω0/B) * (iq - (B*vd))
    end
end


# -----------------------------------------------------------------------------------------
# New component type: GenModel
# -----------------------------------------------------------------------------------------
# 23 state variables: 
#   4 from 1 Pins:  p.vd, p.vq, p.id, p.iq
#   19 from @variables
# 21 equations:
#   12 differential equations
#   9 algebraic equations
# (Remember that when it is connected, it adds four more equations to the overall system)
@mtkmodel GenModel begin
    @extend OnePortDQ()
    # NOTE: vd,vq,id,iq from OnePortDQ is the terminal voltage and current in the network ref frame
    # NOTE: Vd,Vq,Id,Iq added in this model is the terminal voltage and current in the gen ref frame
    # NOTE: ωs is from OnePortDQ
    @variables begin
        # Stator (diff)
        ψq(t)
        ψd(t)
        # Machine (diff)
        eq_p(t)
        ed_p(t)
        ψd_pp(t)
        ψq_pp(t)
        # Shaft (diff)
        δ(t) 
        ω(t)
        # AVR (diff)
        Vf(t)
        Vr1(t)
        Vr2(t)
        Vm(t)
        # Terminal (alg) - in generator DQ ref frame 
        Id(t)
        Iq(t)
        Vd(t)
        Vq(t)
        vh(t) # magnitude (same in any ref frame)
        # Torque (alg)
        τe(t)
        τm(t)
    end
    @parameters begin
        # All parameters are from Sienna testing environment:
        # PowerSimulationsDynamics.jl/test/data_tests/dynamic_test_data.jl
        # ------------------------------------------------------------------------- General
        ω0              # [rad/s] GLOBAL
        Sb_sys          # [MVA] GLOBAL
        Sb_gen = 100.0  # [MVA]
        # --------------------------------------------------------------------------- Shaft
        # Source: dynamic_test_data.jl > shaft_damping()
        H = 3.148       # [s] units are technically MWs/MVA
        Dd = 2.0        # [pu] can't be D, it is a reserved name for derivatives in MTK
        τm0             # [pu] *FORCE USER TO DEFINE - MUST BE CONSISTENT WITH POWERFLOW
        # ------------------------------------------------------------------------- Machine
        # Source: dynamic_test_data.jl > machine_sauerpai()
        R = 0.002       # [pu]
        Xd = 1.79       # [pu]
        Xq = 1.71       # [pu] 
        Xd_p = 0.169    # [pu] 
        Xq_p = 0.228    # [pu] 
        Xd_pp = 0.135   # [pu] 
        Xq_pp = 0.2     # [pu] 
        Xl = 0.13       # [pu]  
        Td0_p = 4.3     # [s] 
        Tq0_p = 0.85    # [s] 
        Td0_pp = 0.032  # [s] 
        Tq0_pp = 0.05   # [s] 
        # (15.14) Intermediate machine constants for convenience
        γd1 = (Xd_pp - Xl) / (Xd_p - Xl)
        γq1 = (Xq_pp - Xl) / (Xq_p - Xl)
        γd2 = (1.0 - γd1) / (Xd_p - Xl)
        γq2 = (1.0 - γq1) / (Xq_p - Xl)
        # ----------------------------------------------------------------------------- AVR
        # Source: dynamic_test_data.jl > avr_type1()
        Ka = 20.0       # [-]
        Ke = 0.01       # [-]
        Kf = 0.063      # [s*pu/pu]
        Ta = 0.2        # [s]
        Te = 0.314      # [s]
        Tf = 0.35       # [s]
        Tr = 0.001      # [s]
        #Va_lim = (min=-5.0, max=5.0) # [pu] not used in milano equations
        Ae = 0.0039     # [-] Se(Vf) = Ae exp(Be|Vf|)
        Be = 1.555      # [-]
        V_ref           # [pu] *FORCE USER TO DEFINE - MUST BE CONSISTENT WITH POWERFLOW
    end
    @equations begin
        # NOTE: The order of D() equations here sets the final order of the states/initial conditions
        # ------ DQ VOLTAGES - get terminal voltage in generator RF (not from milano, bec he uses vh θh)
        Vd ~ (sin(δ)*vd) - (cos(δ)*vq) # vd, vq are in the network reference frame
        Vq ~ (cos(δ)*vd) + (sin(δ)*vq) 
        vh ~ sqrt(vd^2 + vq^2)  # NOTE: could sub into AVR eqs, doesn't need to be it's own eq
        # ------ STATOR (2) - Milano (15.9) 
        D(ψq) ~ ω0 * ((R*Iq) - (ω*ψd) + Vq)
        D(ψd) ~ ω0 * ((R*Id) + (ω*ψq) + Vd)
        # ------ MACHINE (6) - Milano (15.13) and (15.15)
        D(eq_p) ~ (1/Td0_p) * (-eq_p - (Xd-Xd_p)*(Id - (γd2*ψd_pp) - ((1-γd1)*Id) + (γd2*eq_p)) + Vf)
        D(ed_p) ~ (1/Tq0_p) * (-ed_p + (Xq-Xq_p)*(Iq - (γq2*ψq_pp) - ((1-γq1)*Iq) - (γq2*ed_p))) 
        ### ^^^ NOTE: Milano and Sienna have a typo: (γd2*ed_p). It should be (γq2*ed_p), like above
        D(ψd_pp) ~ (1/Td0_pp) * (-ψd_pp + eq_p - ((Xd_p - Xl)*Id))
        D(ψq_pp) ~ (1/Tq0_pp) * (-ψq_pp - ed_p - ((Xq_p - Xl)*Iq))
        0 ~ ψd + (Xd_pp*Id) - (γd1*eq_p) - ((1-γd1)*ψd_pp)  # Id
        0 ~ ψq + (Xq_pp*Iq) + (γq1*ed_p) - ((1-γq1)*ψq_pp)  # Iq
        #Id ~ (1.0 / Xd_pp) * (γd1 * eq_p - ψd + (1 - γd1) * ψd_pp)   #15.15 explicit form
        #Iq ~ (1.0 / Xq_pp) * (-γq1 * ed_p - ψq + (1 - γq1) * ψq_pp)  #15.15 explicit form
        # ------ SHAFT (2) - Milano (15.5)
        # NOTE: ωs is the reference frequency shared by the whole system. We use the multi-machine 
        #  implementation where ωs(t) is set by GenModelRef (of which there is only one per model) 
        #  i.e. ωs(t) = ω(t) of GenModelRef
        D(δ) ~ ω0 * (ω - ωs)  # [rad/s] = [rad/s * (pu-rad/s - pu-rad/s)]
        D(ω) ~ (1 / (2 * H)) * (τm - τe - Dd * (ω - 1.0)/ω)  # use 1.0 for damping diff (not ωs) to match Sienna
        # NOTE: this includes the speed correction to match Sienna, ie [Dd*(ω-1.0)/ω] (not [Dd*(ω-1.0)])
        # ------ AVR (4) 
        D(Vf) ~ -(1/Te) * (Vf*(Ke + Ae*exp(Be*abs(Vf))) - Vr1)
        D(Vr1) ~ (1/Ta) * (Ka*(V_ref - Vm - Vr2 - (Kf/Tf)*Vf) - Vr1)
        D(Vr2) ~ -(1/Tf) * ((Kf/Tf)*Vf + Vr2)
        D(Vm) ~ (1/Tr) * (vh - Vm)
        # ------ Electric torque - Milano (15.6)
        0 ~ (ψd*Iq) - (ψq*Id) - τe
        # ------ Mechanical torque - trivial
        0 ~ τm0 - τm
        # ------ DQ currents - get currents in network RF (id,iq) from currents in generator RF (Id,Iq)
        # NOTE: since this is current, we must adjust between the gen and system bases
        # NOTE: Gen equations define positive Id and Iq as injections into the grid, but the OnePortDQ 
        #  definitions define positive id and iq as flow from positive to negative voltage, which would be 
        #  a withdrawal from the grid (gen bus --> ground). Negative signs on LHS account for this. 
        # (See PowerSimulationsDynamics.jl/blob/main/src/models/generator_models/machine_models.jl#L212)
        -id ~ (Sb_gen/Sb_sys)*((sin(δ)*Id) + (cos(δ)*Iq)) # id, iq are in the network reference frame
        -iq ~ (Sb_gen/Sb_sys)*((-cos(δ)*Id) + (sin(δ)*Iq))
    end
end

# -----------------------------------------------------------------------------------------
# New component type: GenModelRef
# -----------------------------------------------------------------------------------------
# Almost identical to GenModel 
@mtkmodel GenModelRef begin
    @extend OnePortDQ()
    # NOTE: vd,vq,id,iq from OnePortDQ is the terminal voltage and current in the network ref frame
    # NOTE: Vd,Vq,Id,Iq added in this model is the terminal voltage and current in the gen ref frame
    # NOTE: ωs is from OnePortDQ
    @variables begin
        # Stator (diff)
        ψq(t)
        ψd(t)
        # Machine (diff)
        eq_p(t)
        ed_p(t)
        ψd_pp(t)
        ψq_pp(t)
        # Shaft (diff)
        #δ(t) # NOTE: δ is a parameter, not a variable, for the reference gen 
        ω(t)
        # AVR (diff)
        Vf(t)
        Vr1(t)
        Vr2(t)
        Vm(t)
        # Terminal (alg) - in generator DQ ref frame 
        Id(t)
        Iq(t)
        Vd(t)
        Vq(t)
        vh(t) # magnitude (same in any ref frame)
        # Torque (alg)
        τe(t)
        τm(t)
    end
    @parameters begin
        # All parameters are from Sienna testing environment:
        # PowerSimulationsDynamics.jl/test/data_tests/dynamic_test_data.jl
        # ------------------------------------------------------------------------- General
        ω0              # [rad/s] GLOBAL
        Sb_sys          # [MVA] GLOBAL
        Sb_gen = 100.0  # [MVA]
        δ               # [rad] *FORCE USER TO DEFINE - MUST BE CONSISTENT WITH POWERFLOW
        # --------------------------------------------------------------------------- Shaft
        # Source: dynamic_test_data.jl > shaft_damping()
        H = 3.148       # [s] units are technically MWs/MVA
        Dd = 2.0        # [pu] can't be D, it is a reserved name for derivatives in MTK
        τm0             # [pu] *FORCE USER TO DEFINE - MUST BE CONSISTENT WITH POWERFLOW
        # ------------------------------------------------------------------------- Machine
        # Source: dynamic_test_data.jl > machine_sauerpai()
        R = 0.002       # [pu]
        Xd = 1.79       # [pu]
        Xq = 1.71       # [pu] 
        Xd_p = 0.169    # [pu] 
        Xq_p = 0.228    # [pu] 
        Xd_pp = 0.135   # [pu] 
        Xq_pp = 0.2     # [pu] 
        Xl = 0.13       # [pu]  
        Td0_p = 4.3     # [s] 
        Tq0_p = 0.85    # [s] 
        Td0_pp = 0.032  # [s] 
        Tq0_pp = 0.05   # [s] 
        # (15.14) Intermediate machine constants for convenience
        γd1 = (Xd_pp - Xl) / (Xd_p - Xl)
        γq1 = (Xq_pp - Xl) / (Xq_p - Xl)
        γd2 = (1 - γd1) / (Xd_p - Xl)
        γq2 = (1 - γq1) / (Xq_p - Xl)
        # ----------------------------------------------------------------------------- AVR
        # Source: dynamic_test_data.jl > avr_type1()
        Ka = 20.0       # [-]
        Ke = 0.01       # [-]
        Kf = 0.063      # [s*pu/pu]
        Ta = 0.2        # [s]
        Te = 0.314      # [s]
        Tf = 0.35       # [s]
        Tr = 0.001      # [s]
        #Va_lim = (min=-5.0, max=5.0) # [pu] not used in milano equations
        Ae = 0.0039     # [-] Se(Vf) = Ae exp(Be|Vf|)
        Be = 1.555      # [-]
        V_ref           # [pu] *FORCE USER TO DEFINE - MUST BE CONSISTENT WITH POWERFLOW
    end
    @equations begin
        # NOTE: The order of D() equations here sets the final order of the states/initial conditions
        # ------ DQ VOLTAGES - get terminal voltage in generator RF (not from milano, bec he uses vh θh)
        Vd ~ (sin(δ)*vd) - (cos(δ)*vq) # vd, vq are in the network reference frame
        Vq ~ (cos(δ)*vd) + (sin(δ)*vq) 
        vh ~ sqrt(vd^2 + vq^2)  # NOTE: could sub into AVR eqs, doesn't need to be it's own eq
        # ------ STATOR (2) - Milano (15.9) 
        D(ψq) ~ ω0 * ((R*Iq) - (ω*ψd) + Vq)
        D(ψd) ~ ω0 * ((R*Id) + (ω*ψq) + Vd)
        # ------ MACHINE (6) - Milano (15.13) and (15.15)
        D(eq_p) ~ (1/Td0_p) * (-eq_p - (Xd-Xd_p)*(Id - (γd2*ψd_pp) - ((1-γd1)*Id) + (γd2*eq_p)) + Vf)
        D(ed_p) ~ (1/Tq0_p) * (-ed_p + (Xq-Xq_p)*(Iq - (γq2*ψq_pp) - ((1-γq1)*Iq) - (γq2*ed_p))) 
        ### ^^^ NOTE: Milano and Sienna have a typo: (γd2*ed_p). It should be (γq2*ed_p), like above
        D(ψd_pp) ~ (1/Td0_pp) * (-ψd_pp + eq_p - ((Xd_p - Xl)*Id))
        D(ψq_pp) ~ (1/Tq0_pp) * (-ψq_pp - ed_p - ((Xq_p - Xl)*Iq))
        0 ~ ψd + (Xd_pp*Id) - (γd1*eq_p) - ((1-γd1)*ψd_pp)  # Id
        0 ~ ψq + (Xq_pp*Iq) + (γq1*ed_p) - ((1-γq1)*ψq_pp)  # Iq
        #Id ~ (1.0 / Xd_pp) * (γd1 * eq_p - ψd + (1 - γd1) * ψd_pp)   #15.15 explicit form
        #Iq ~ (1.0 / Xq_pp) * (-γq1 * ed_p - ψq + (1 - γq1) * ψq_pp)  #15.15 explicit form
        # ------ SHAFT (2) - Milano (15.5)
        # NOTE: ωs is the reference frequency shared by the whole system. We use the multi-machine 
        #  implementation where ωs(t) is set by GenModelRef (of which there is only one per model) 
        #  i.e. ωs(t) = ω(t) of GenModelRef
        #D(δ) ~ ω0 * (ω - ωs)  # [δ = rad] NOT NEEDED FOR GenModelRef SINCE δ is a parameter!
        D(ω) ~ (1 / (2 * H)) * (τm - τe - Dd * (ω - 1.0)/ω)
        # NOTE: this includes the speed correction to match Sienna, ie [Dd*(ω-1.0)/ω] (not [Dd*(ω-1.0)])
        0 ~ ωs - ω  # set this generator frequency as the reference frequency
        # ------ AVR (4) 
        D(Vf) ~ -(1/Te) * (Vf*(Ke + Ae*exp(Be*abs(Vf))) - Vr1)
        D(Vr1) ~ (1/Ta) * (Ka*(V_ref - Vm - Vr2 - (Kf/Tf)*Vf) - Vr1)
        D(Vr2) ~ -(1/Tf) * ((Kf/Tf)*Vf + Vr2)
        D(Vm) ~ (1/Tr) * (vh - Vm)
        # ------ Electric torque - Milano (15.6)
        0 ~ (ψd*Iq) - (ψq*Id) - τe
        # ------ Mechanical torque - trivial
        0 ~ τm0 - τm
        # ------ DQ currents - get currents in network RF (id,iq) from currents in generator RF (Id,Iq)
        # NOTE: since this is current, we must adjust between the gen and system bases
        # NOTE: Gen equations define positive Id and Iq as injections into the grid, but the OnePortDQ 
        #  definitions define positive id and iq as flow from positive to negative voltage, which would be 
        #  a withdrawal from the grid (gen bus --> ground). Negative signs on LHS account for this. 
        # (See PowerSimulationsDynamics.jl/blob/main/src/models/generator_models/machine_models.jl#L212)
        -id ~ (Sb_gen/Sb_sys)*((sin(δ)*Id) + (cos(δ)*Iq)) # id, iq are in the network reference frame
        -iq ~ (Sb_gen/Sb_sys)*((-cos(δ)*Id) + (sin(δ)*Iq))
    end
end

# -----------------------------------------------------------------------------------------
# New component type: InvModel
# -----------------------------------------------------------------------------------------
# 23 state variables: 
#   4 from 1 Pins:  p.vd, p.vq, p.id, p.iq
#   19 from @variables
# 21 equations:
#   12 differential equations
#   9 algebraic equations
# (Remember that when it is connected, it adds four more equations to the overall system)
@mtkmodel InvModel begin
    @extend OnePortDQ()
    # NOTE: vd,vq,id,iq from OnePortDQ is the terminal voltage and current in the network ref frame (and system base)
    # NOTE: vD,vQ,iD,iQ added in this model is the terminal voltage and current in the gen ref frame (and gen base)
    # NOTE: I think I also need notation for network ref frame (and gen base) - for the filter. 
    # NOTE: ωs is from OnePortDQ (it is the system reference frequency)
    @variables begin
        # Converter (in generator RF)
        vcvD(t) # alg
        vcvQ(t) # alg
        # LCLFilter (in network RF but gen base)
        icvd(t) # current thru converter-side L
        icvq(t)
        vcvd(t) # alg
        vcvq(t) # alg
        id_g(t) # alg
        iq_g(t) # alg
        # OuterControl
        θoc(t)
        pm(t)
        qm(t)
        pe(t)       # alg
        qe(t)       # alg
        ωoc(t)      # alg
        voc_ref(t)  # alg
        # VoltageModeControl (in generator RF)
        ξD(t)
        ξQ(t)
        γD(t)
        γQ(t)
        ϕD(t)
        ϕQ(t)
        vviD_ref(t) # alg
        vviQ_ref(t) # alg
        icvD_ref(t) # alg
        icvQ_ref(t) # alg 
        vD_refsig(t) # alg 
        vQ_refsig(t) # alg
        # LCLFilter (in generator ref frame.. related via θoc)
        icvD(t) # alg
        icvQ(t) # alg
        vD(t) # alg
        vQ(t) # alg
        iD(t) # alg
        iQ(t) # alg
    end
    @parameters begin
        # All parameters are from Sienna testing environment:
        # PowerSimulationsDynamics.jl/test/data_tests/dynamic_test_data.jl
        # ------------------------------------------------------------------------- General
        ω0              # [rad/s] GLOBAL I think same as Ωb ???
        Sb_sys          # [MVA] GLOBAL
        Sb_gen = 100.0  # [MVA]
        #Ωb = 2*pi*60.0  # Sienna's Ωb is our ω0
        # ------------------------------------------------------------------- Outer Control
        # ActivePowerDroop
        Rp = 0.05
        ωz = 2*pi*60.0  # Changed this to 60.0
        ω_ref  # *FORCE USER TO DEFINE - MUST BE CONSISTENT WITH POWERFLOW 
        p_ref  # *FORCE USER TO DEFINE - MUST BE CONSISTENT WITH POWERFLOW 
        # ReactivePowerDroop
        kq = 0.2
        ωf = 1000.0
        v_ref  # *FORCE USER TO DEFINE - MUST BE CONSISTENT WITH POWERFLOW 
        q_ref  # *FORCE USER TO DEFINE - MUST BE CONSISTENT WITH POWERFLOW 
        # ------------------------------------------------------------------- Inner Control
        kpv = 0.59     #Voltage controller proportional gain
        kiv = 736.0    #Voltage controller integral gain
        kffv = 0.0     #Binary variable enabling the voltage feed-forward in output of current controllers
        rv = 0.0       #Virtual resistance in pu
        lv = 0.2       #Virtual inductance in pu
        kpc = 1.27     #Current controller proportional gain
        kic = 14.3     #Current controller integral gain
        kffi = 0.0     #Binary variable enabling the current feed-forward in output of current controllers
        ωad = 50.0     #Active damping low pass filter cut-off frequency
        kad = 0.2
        # -------------------------------------------------------------------------- Filter
        lf = 0.08
        rf = 0.003
        cf = 0.074
        lg = 0.2
        rg = 0.01
    end
    @equations begin
        # NOTE: The order of D() equations here sets the final order of the states/initial conditions
        # ------ Gen to Network RF/BASE transformations
        # dq = network RF, DQ = generator RF
        vcvd ~ cos(θoc)*vcvD - sin(θoc)*vcvQ  # dq (lcl filter), DQ (converter / voltage mode control)
        vcvq ~ sin(θoc)*vcvD + cos(θoc)*vcvQ
        # (iD,iQ) = genRF/genBASE     << used in VoltageModeControl
        # (id_g,iq_g) = netRF/genBASE << used in OutControl and LCLFilter
        # (id,iq) = netRF/netBASE     << used for connecting to network (i.e. how the OnePortDQ vars are defined)
        # NOTE: Filter equations define positive id and iq as injections into the grid, but the OnePortDQ 
        #  definitions define positive id and iq as flow from positive to negative voltage, which would be 
        #  a withdrawal from the grid (gen bus --> ground). Negative signs on LHS account for this. 
        -id ~ (Sb_gen/Sb_sys)*id_g            # convert from genBASE to netBASE 
        -iq ~ (Sb_gen/Sb_sys)*iq_g            # convert from genBASE to netBASE
        # ------- TRYING TO REVERSE THESE OVERDETERMINED EQUATIONS  ("###" above)
        icvD ~ cos(θoc)*icvd + sin(θoc)*icvq  # dq (lcl filter), DQ (voltage mode control)
        icvQ ~ -sin(θoc)*icvd + cos(θoc)*icvq
        vD ~ cos(θoc)*vd + sin(θoc)*vq
        vQ ~ -sin(θoc)*vd + cos(θoc)*vq
        iD ~ cos(θoc)*id_g + sin(θoc)*iq_g    # convert from genRF to netRF
        iQ ~ -sin(θoc)*id_g + cos(θoc)*iq_g   # convert from genRF to netRF
        # ------ Fixed Frequency (no PLL)
        #  i.e. controller sees ωs
        # ------ OuterControl
        # NOTE: ωs is the reference frequency shared by the whole system. We use the multi-machine 
        #  implementation where ωs(t) is set by GenModelRef (of which there is only one per model) 
        #  i.e. ωs(t) = ω(t) of GenModelRef
        D(θoc) ~ ω0*(ωoc - ωs)  # NOTE: in Sienna doc, ωs is ωsys; in Sienna code  ωs is ω_sys
        D(pm) ~ ωz*(pe - pm)
        D(qm) ~ ωf*(qe - qm)
        pe ~ vd*id_g + vq*iq_g  # measured at filter capacitor
        qe ~ vq*id_g - vd*iq_g  # measured at filter capacitor
        ωoc ~ ω_ref + Rp*(p_ref - pm)
        voc_ref ~ v_ref + kq*(q_ref - qm)
        # ------ VoltageModeControl
        D(ξD) ~ vviD_ref - vD
        D(ξQ) ~ vviQ_ref - vQ 
        D(γD) ~ icvD_ref - icvD 
        D(γQ) ~ icvQ_ref - icvQ 
        D(ϕD) ~ ωad * (vD - ϕD) # ϕ
        D(ϕQ) ~ ωad * (vQ - ϕQ)
        vviD_ref ~ voc_ref - (rv*iD) + (ωoc*lv*iQ)
        vviQ_ref ~ - (rv*iQ) - (ωoc*lv*iD)
        icvD_ref ~ kpv*(vviD_ref - vD) + (kiv*ξD) - (cf*ωoc*vQ) + (kffi*iD)
        icvQ_ref ~ kpv*(vviQ_ref - vQ) + (kiv*ξQ) + (cf*ωoc*vD) + (kffi*iQ)
        vD_refsig ~ kpc*(icvD_ref - icvD) + (kic*γD) - (lf*ωoc*icvQ) + (kffv*vD) - kad*(vD - ϕD) 
        vQ_refsig ~ kpc*(icvQ_ref - icvQ) + (kic*γQ) + (lf*ωoc*icvD) + (kffv*vQ) - kad*(vQ - ϕQ) 
        # ------ Converter
        vcvD ~ vD_refsig 
        vcvQ ~ vQ_refsig 
        # ------ LCL Filter 
        D(icvd) ~ (ω0/lf) * (vcvd - vd - (rf*icvd) + (ωs*lf*icvq))   # NOTE: in Sienna doc, ωs is ωgrid; in Sienna code  ωs is ω_sys
        D(icvq) ~ (ω0/lf) * (vcvq - vq - (rf*icvq) - (ωs*lf*icvd))   # "" ""
        D(vd) ~ (ω0/cf) * (icvd - id_g + (ωs*cf*vq))                 # "" ""
        D(vq) ~ (ω0/cf) * (icvq - iq_g - (ωs*cf*vd))                 # "" ""
        # NOTE: the equations below are part of the transformer subsystem.
        #  If i want to keep this as a single unit, then vd1 has to become vd and vd has to 
        #  become some intermediate bec right now I'm treating vd/vq as the network interface,
        #  since those are the names of the OnePortDQ states.. 
        ###D(id) ~ (ω0/lg) * (vd - vd1 - (rg*id) + (ωs*lg*iq))       # NOTE: in Sienna doc, ωs is ωgrid; in Sienna code  ωs is ω_sys
        ###D(iq) ~ (ω0/lg) * (vq - vq1 - (rg*iq) - (ωs*lg*id))       # "" ""        
    end
end
 
end