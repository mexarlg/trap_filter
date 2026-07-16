#==============================================================================
# File: waves_delay_unit_sr.do
#
# Description:
#   Waveform configuration for the delay_unit_sr testbench in ModelSim.
#   Signals are grouped logically by function.
#
# Usage:
#   source waves_delay_unit_sr.do
#==============================================================================

quietly WaveActivateNextPane {} 0

#===========================================================================
# Simulation
#===========================================================================
add wave -divider " CLK/RST_N "
add wave -color green  -radix binary sim:/tb_delay_unit_sr/tb_clk
add wave -color green  -radix binary sim:/tb_delay_unit_sr/tb_rst_n

#===========================================================================
# delay_unit_sr IN
#===========================================================================
add wave -divider " DELAY_UNIT_SR INPUTS"
add wave -color green  -radix binary sim:/tb_delay_unit_sr/tb_ce
add wave -color white -format Analog-Step -radix signed sim:/tb_delay_unit_sr/tb_data_i
add wave -color green -radix binary sim:/tb_delay_unit_sr/tb_sync_pulse

#===========================================================================
# delay_unit_sr Internal
#===========================================================================
add wave -divider " DELAY_UNIT_SR INTERNAL"
add wave -color green  -radix unsigned sim:/tb_delay_unit_sr/dut/C_CNT_D_MAX
add wave -color green  -radix signed sim:/tb_delay_unit_sr/dut/data_n
add wave -color white  -radix unsigned sim:/tb_delay_unit_sr/dut/cnt_data_d

#===========================================================================
# Mov_avg_filter OUT
#===========================================================================
add wave -divider " DELAY_UNIT_SR OUTPUTS"
add wave -color white  -radix signed sim:/tb_delay_unit_sr/tb_data_n
add wave -color green  -radix signed sim:/tb_delay_unit_sr/tb_data_d
add wave -color green  -radix binary sim:/tb_delay_unit_sr/tb_data_d_valid

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