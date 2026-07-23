#==============================================================================
# File: waves_pulse_feed.do
#
# Description:
#   Waveform configuration for the pulse_feed testbench in ModelSim.
#   Signals are grouped logically by function.
#
# Usage:
#   source waves_pulse_feed.do
#==============================================================================

quietly WaveActivateNextPane {} 0

#===========================================================================
# Simulation
#===========================================================================
add wave -divider " CLK/RST_N "
add wave -color green  -radix binary sim:/tb_pulse_feed/tb_clk
add wave -color green  -radix binary sim:/tb_pulse_feed/tb_rst_n

#===========================================================================
# PULSE_FEED IN
#===========================================================================
add wave -divider " PULSE_FEED"
add wave -color green  -radix binary sim:/tb_pulse_feed/tb_ce
add wave -color white -format Analog-Step -radix unsigned sim:/tb_pulse_feed/tb_data
add wave -color green -radix binary sim:/tb_pulse_feed/tb_data_valid

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