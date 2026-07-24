#==============================================================================
# File: waves_mov_avg_filter.do
#
# Description:
#   Waveform configuration for the mov_avg_filter testbench in ModelSim.
#   Signals are grouped logically by function.
#
# Usage:
#   source waves_mov_avg_filter.do
#==============================================================================

quietly WaveActivateNextPane {} 0

#===========================================================================
# Simulation
#===========================================================================
add wave -divider " CLK/RST_N "
add wave -color green  -radix binary sim:/tb_mov_avg_filter/tb_clk
add wave -color green  -radix binary sim:/tb_mov_avg_filter/tb_rst_n

#===========================================================================
# SHIFT_REGISTER IN
#===========================================================================
add wave -divider " SHIFT REG INPUTS"
add wave -color green  -radix binary sim:/tb_mov_avg_filter/tb_ce
add wave -color white -format Analog-Step -radix signed sim:/tb_mov_avg_filter/tb_data_i
add wave -color green -radix unsigned sim:/tb_mov_avg_filter/sr/cnt_data_d
add wave -color green -radix binary sim:/tb_mov_avg_filter/tb_sync_pulse

#===========================================================================
# Mov_avg_filter IN
#===========================================================================
add wave -divider " MOV_AVG_FILTER INPUTS"
add wave -color green  -radix signed sim:/tb_mov_avg_filter/tb_data_n
add wave -color green  -radix signed sim:/tb_mov_avg_filter/tb_data_d
add wave -color green  -radix binary sim:/tb_mov_avg_filter/tb_data_d_valid

#===========================================================================
# Mov_avg_filter Internal
#===========================================================================
add wave -divider " MOV_AVG_FILTER"
add wave -color green  -radix signed sim:/tb_mov_avg_filter/dut/acc_reg
add wave -color green  -radix binary sim:/tb_mov_avg_filter/tb_error_oflow
add wave -color white -format Analog-Step -radix signed sim:/tb_mov_avg_filter/tb_data_filtered

#===========================================================================
# Mov_avg_filter EXPECTED
#===========================================================================
add wave -divider " MOV_AVG_FILTER VALIDATION"
add wave -color white -radix signed sim:/tb_mov_avg_filter/p_diff/v_diff


#==============================================================================
# GENERAL WAVEFORM VIEWER SETTINGS
#==============================================================================
configure wave -namecolwidth 260
configure wave -valuecolwidth 80
configure wave -signalnamewidth 1
configure wave -timelineunits ns
WaveRestoreZoom {0 ns} {1000 ns}

#==============================================================================
# END OF FILE
#==============================================================================