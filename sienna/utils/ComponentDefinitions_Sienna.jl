
# This is just a cleaned-up subset of definitions from:
# https://github.com/NREL-Sienna/PowerSimulationsDynamics.jl/blob/main/test/data_tests/dynamic_test_data.jl

using PowerSystems

# -----------------------------------------------------------------------------------------
# Synchronous Generator
# -----------------------------------------------------------------------------------------

######## Machine #########
# Differential states (6)
#   ψq: q-axis stator flux,
#   ψd: d-axis stator flux,
#   eq_p: q-axis transient voltage,
#   ed_p: d-axis transient voltage
#   ψd_pp: subtransient flux linkage in the d-axis
#   ψq_pp: subtransient flux linkage in the q-axis 
machine_sauerpai() = SauerPaiMachine(;
    R = 0.002,      # [pu] check this
    Xd = 1.79,      # [pu]
    Xq = 1.71,      # [pu] 
    Xd_p = 0.169,   # [pu] 
    Xq_p = 0.228,   # [pu] 
    Xd_pp = 0.135,  # [pu] 
    Xq_pp = 0.2,    # [pu] 
    Xl = 0.13,      # [pu]  
    Td0_p = 4.3,    # [s] 
    Tq0_p = 0.85,   # [s] 
    Td0_pp = 0.032, # [s] 
    Tq0_pp = 0.05,  # [s] 
) # MVABase

######## Shaft #########
# Differential States (2)
#   δ: rotor angle,
#   ω: rotor speed
shaft_damping() = SingleMass(
    3.148,  # H
    2.0,    # D
)

########  AVR #########
# Differential States (4)
#   Vf: Voltage field,
#   Vr1: Amplifier State,
#   Vr2: Stabilizing Feedback State,
#   Vm: Measured voltage
avr_type1() = AVRTypeI(;
    Ka = 20.0,      # [-]
    Ke = 0.01,      # [-]
    Kf = 0.063,     # [s*pu/pu]
    Ta = 0.2,       # [s]
    Te = 0.314,     # [s]
    Tf = 0.35,      # [s]
    Tr = 0.001,     # [s]
    Va_lim = (min=-5.0, max=5.0), # [pu]
    Ae = 0.0039,    # [-] Se(vf) = Ae exp(Be|vf|)
    Be = 1.555,     # [-]
    V_ref = 1.0,    # [pu]
) # used in Sauer & Pai Chapter 7

# # Differential States (4)
# #   Vm: Measured voltage,
# #   Vrll: Lead/Lag State,
# #   Vr: Amplifier State,
# #   Vf: Voltage field
# avr_exst1() = PSY.EXST1(;
#     Tr = 0.01,      # [s]
#     Vi_lim = (-5.0, 5.0), # [pu]
#     Tc = 10.0,      # [s]
#     Tb = 20.0,      # [s]
#     Ka = 200.0,     # [-]
#     Ta = 0.1,       # [s]
#     Vr_lim = (0.0, 6.0), # [pu]
#     Kc = 0.0,       # [-]
#     Kf = 0.0,       # [-]
#     Tf = 0.1,       # [s]
# ) # used in Jose dynamics class

######## PSS #########
pss_none() = PSSFixed(0.0)  # voltage stabilization signal

######## TG #########
tg_none() = TGFixed(1.0)    # efficiency factor

# -----------------------------------------------------------------------------------------
# Inverter
# -----------------------------------------------------------------------------------------
# TODO: Adjust the filter values accordingly to make this an aggregrated IBR?

######## Converter ########
# Copy-paste of dynamic_test_data
converter_low_power() = AverageConverter(; rated_voltage = 690.0, rated_current = 2.75) # 1.9 kVA
converter_high_power() = AverageConverter(; rated_voltage = 138.0, rated_current = 100.0) # 13.8 kVA

###### DC Source ######
# Copy-paste of dynamic_test_data
dc_source_lv() = FixedDCSource(; voltage = 600.0) #Not in the original data, guessed.
dc_source_hv() = FixedDCSource(; voltage = 1500.0) #Not in the original data, guessed.

######## Filter ########
# Copy-paste of dynamic_test_data, also same as dynamics project spec
filter_lcl() = LCLFilter(; 
    lf = 0.08, # [Ω-pu]
    rf = 0.003, 
    cf = 0.074, 
    lg = 0.2, 
    rg = 0.01
    )

######## PLL ########
# Copy-paste of dynamic_test_data, also same as dynamics project spec
reduced_pll() = ReducedOrderPLL(;
    ω_lp = 1.32*2*pi*50,    #Cut-off frequency for LowPass filter of PLL filter.
    kp_pll = 2.0,           #PLL proportional gain
    ki_pll = 20.0,          #PLL integral gain
)
no_pll() = PSY.FixedFrequency()


######## Inner Control ########
# Copy-paste of dynamic_test_data, also same as dynamics project spec
inner_control() = VoltageModeControl(;
    kpv = 0.59,     #Voltage controller proportional gain
    kiv = 736.0,    #Voltage controller integral gain
    kffv = 0.0,     #Binary variable enabling the voltage feed-forward in output of current controllers
    rv = 0.0,       #Virtual resistance in pu
    lv = 0.2,       #Virtual inductance in pu
    kpc = 1.27,     #Current controller proportional gain
    kic = 14.3,     #Current controller integral gain
    kffi = 0.0,     #Binary variable enabling the current feed-forward in output of current controllers
    ωad = 50.0,     #Active damping low pass filter cut-off frequency
    kad = 0.2,
)

######## Outer Control ########
# Copy-paste of dynamic_test_data, only active droop is same as dynamics project spec
function outer_control_droop()
    # Taken directly from dynamic_test_data, also same as dynamics project spec
    function active_droop()
        return PSY.ActivePowerDroop(; Rp = 0.05, ωz = 2*pi*60.0) ## Changed this to 60.0
    end
    function reactive_droop()
        return PSY.ReactivePowerDroop(; kq = 0.2, ωf = 1000.0)
    end
    return OuterControl(active_droop(), reactive_droop())
end