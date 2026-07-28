#==============================================================================
# File: waves_pulse_detection.do
#
# Description:
#   Waveform configuration for the pulse_detection testbench in ModelSim.
#   Signals are grouped logically by function.
#
# Usage:
#   source waves_pulse_detection.do
#==============================================================================

quietly WaveActivateNextPane {} 0

#===========================================================================
# Simulation
#===========================================================================
add wave -divider " CLK/RST_N "
add wave -color green  -radix binary sim:/tb_pulse_detection/tb_clk
add wave -color green  -radix binary sim:/tb_pulse_detection/tb_rst_n
add wave -color green  -radix binary sim:/tb_pulse_detection/tb_ce

#===========================================================================
# pulse_detection IN
#===========================================================================
add wave -divider " pulse_detection"
add wave -color white -format Analog-Step -radix unsigned sim:/tb_pulse_detection/tb_data_i
add wave -color green -radix binary sim:/tb_pulse_detection/tb_pulse_detected
add wave -color green -radix binary sim:/tb_pulse_detection/dut/pulse_above_th
add wave -color green -radix binary sim:/tb_pulse_detection/dut/pulse_below_th
add wave -color green -radix binary sim:/tb_pulse_detection/dut/pulse_armed
add wave -color green -radix binary sim:/tb_pulse_detection/dut/pulse_armed_q0
add wave -color white -format Analog-Step -radix signed sim:/tb_pulse_detection/dut/data_jord_filt
add wave -color green -radix binary sim:/tb_pulse_detection/tb_error_oflow

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