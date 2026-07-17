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
add wave -color green -radix unsigned sim:/tb_jordanov_filter/sr_k/cnt_data_d
add wave -color green -radix unsigned sim:/tb_jordanov_filter/sr_l/cnt_data_d
add wave -color green -radix unsigned sim:/tb_jordanov_filter/sr_kl/cnt_data_d
add wave -color white -format Analog-Step -radix unsigned sim:/tb_jordanov_filter/tb_data_i
add wave -color green -radix binary sim:/tb_jordanov_filter/tb_sync_pulse

#===========================================================================
# SHIFT REG OUTPUTS
#===========================================================================
add wave -divider "SHIFT REG OUTPUTS"
add wave -color green  -radix unsigned sim:/tb_jordanov_filter/tb_data_n
add wave -color green  -radix unsigned sim:/tb_jordanov_filter/tb_data_k
add wave -color green  -radix unsigned sim:/tb_jordanov_filter/tb_data_l
add wave -color green  -radix unsigned sim:/tb_jordanov_filter/tb_data_kl

#===========================================================================
# SYNCHRONIZER OUTPUTS
#===========================================================================
add wave -divider "SYNCHRONIZER OUTPUTS"
add wave -color green  -radix binary sim:/tb_jordanov_filter/tb_delay_jord_ready
add wave -color green  -radix binary sim:/tb_jordanov_filter/tb_error_sync
add wave -color green -radix binary sim:/tb_jordanov_filter/tb_data_jord_valid

#===========================================================================
# jordanov_filter Internal
#===========================================================================
add wave -divider "JORDANOV_FILTER"
add wave -color green -radix signed sim:/tb_jordanov_filter/dut/diff
add wave -color green -radix signed sim:/tb_jordanov_filter/dut/acc1_q1
add wave -color green -radix signed sim:/tb_jordanov_filter/dut/Mdiff
add wave -color green -radix signed sim:/tb_jordanov_filter/dut/Mdiff_scaled
add wave -color green -radix signed sim:/tb_jordanov_filter/dut/acc2
add wave -color green -radix binary sim:/tb_jordanov_filter/dut/error_oflow
add wave -color white -format Analog-Step -radix signed sim:/tb_jordanov_filter/tb_data_filtered

#===========================================================================
# jordanov_filter EXPECTED
#===========================================================================
add wave -divider " JORDANOV_FILTER VALIDATION"


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