#==============================================================================
# File: waves_shift_register.do
#
# Description:
#   Waveform configuration for the shift_register testbench in ModelSim.
#   Signals are grouped logically by function.
#
# Usage:
#   source waves_shift_register.do
#==============================================================================

quietly WaveActivateNextPane {} 0

#===========================================================================
# Simulation
#===========================================================================
add wave -divider " CLK/RST_N "
add wave -color green  -radix binary sim:/tb_shift_register/tb_clk
add wave -color green  -radix binary sim:/tb_shift_register/tb_rst_n

#===========================================================================
# shift_register IN
#===========================================================================
add wave -divider " shift_register "
add wave -color green -radix unsigned sim:/tb_shift_register/tb_data_i
add wave -color green  -radix unsigned sim:/tb_shift_register/tb_data_d
add wave -color green  -radix unsigned sim:/tb_shift_register/tb_data_d2

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