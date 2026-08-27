#==============================================================================
# File: waves_jordanov_filter.do
#
# Description:
#   Waveform configuration for the jordanov_filter testbench in ModelSim.
#   Signals are grouped logically by function.
#
# Usage:
#   source waves_jordanov_filter.do
#==============================================================================

quietly WaveActivateNextPane {} 0

#===========================================================================
# Simulation
#===========================================================================
add wave -divider " CLK/RST_N "
add wave -color green  -radix binary sim:/tb_jordanov_filter/tb_clk
add wave -color green  -radix binary sim:/tb_jordanov_filter/tb_rst_n

#===========================================================================
# SHIFT_REGISTER
#===========================================================================
add wave -divider " SHIFT REG INPUTS"
add wave -color green  -radix binary sim:/tb_jordanov_filter/tb_ce
add wave -color white -format Analog-Step -radix unsigned sim:/tb_jordanov_filter/tb_data_i

#===========================================================================
# SHIFT REG OUTPUTS
#===========================================================================
add wave -divider "TRAP_DELAY OUTPUTS"
add wave -color green  -radix unsigned sim:/tb_jordanov_filter/tb_data_n
add wave -color green  -radix unsigned sim:/tb_jordanov_filter/tb_data_k
add wave -color green  -radix unsigned sim:/tb_jordanov_filter/tb_data_l
add wave -color green  -radix unsigned sim:/tb_jordanov_filter/tb_data_kl
add wave -color green  -radix signed sim:/tb_jordanov_filter/tb_data_d

#===========================================================================
# jordanov_filter Internal
#===========================================================================
add wave -divider "JORDANOV_FILTER"
add wave -color green -radix signed sim:/tb_jordanov_filter/dut/diff
add wave -color green -radix signed sim:/tb_jordanov_filter/dut/acc1
add wave -color green -radix signed sim:/tb_jordanov_filter/dut/Mdiff
add wave -color green -radix signed sim:/tb_jordanov_filter/dut/Mdiff_q0
add wave -color green -radix signed sim:/tb_jordanov_filter/dut/acc2
add wave -color green -radix signed sim:/tb_jordanov_filter/dut/acc2_shift
add wave -color green -radix signed sim:/tb_jordanov_filter/dut/norm_prod
add wave -color green -radix signed sim:/tb_jordanov_filter/dut/norm_prod_round
add wave -color white -format Analog-Step -radix signed sim:/tb_jordanov_filter/tb_data_filtered
add wave -color green -radix binary sim:/tb_jordanov_filter/dut/error_oflow


#==============================================================================
# GENERAL WAVEFORM VIEWER SETTINGS
#==============================================================================
configure wave -namecolwidth 260
configure wave -valuecolwidth 80
configure wave -signalnamewidth 1
configure wave -timelineunits ns
WaveRestoreZoom {0 ns} {10000 ns}

#==============================================================================
# END OF FILE
#==============================================================================