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
add wave -color green  -radix binary sim:/tb_mov_avg_filter/tb_ce

#===========================================================================
# Mov_avg_filter IN
#===========================================================================
add wave -divider " MOV_AVG_FILTER IN"
add wave -color white -format Analog-Step -radix signed sim:/tb_mov_avg_filter/tb_data_n
add wave -color white -radix signed sim:/tb_mov_avg_filter/tb_data_n
add wave -color green -radix binary sim:/tb_mov_avg_filter/tb_sync_pulse
add wave -color green  -radix signed sim:/tb_mov_avg_filter/tb_data_d
add wave -color green  -radix binary sim:/tb_mov_avg_filter/tb_delay_ready
add wave -color green  -radix binary sim:/tb_mov_avg_filter/tb_sample_trig

#===========================================================================
# Mov_avg_filter Internal
#===========================================================================
add wave -divider " MOV_AVG_FILTER INTERNAL"
add wave -color green  -radix signed sim:/tb_mov_avg_filter/dut/acc_reg

#===========================================================================
# Mov_avg_filter OUT
#===========================================================================
add wave -divider " MOV_AVG_FILTER OUT"
add wave -color white -format Analog-Step -radix signed sim:/tb_mov_avg_filter/tb_filt_data
add wave -color white -radix signed sim:/tb_mov_avg_filter/tb_filt_data
add wave -color green  -radix binary sim:/tb_mov_avg_filter/tb_filt_data_ready
add wave -color green  -radix signed sim:/tb_mov_avg_filter/tb_captured_data
add wave -color green  -radix binary sim:/tb_mov_avg_filter/tb_captured_data_valid

#===========================================================================
# Mov_avg_filter EXPECTED
#===========================================================================
add wave -divider " MOV_AVG_FILTER EXPECTED"
# python data is delayed 2 cycles to compare it with the filter (2 cycles latency)
add wave -color white -format Analog-Step -radix signed sim:/tb_mov_avg_filter/tb_data_ref_q1
add wave -color white -radix signed sim:/tb_mov_avg_filter/tb_data_ref_q1
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