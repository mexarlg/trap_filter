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
add wave -color white -format Analog-Step -radix unsigned sim:/tb_pulse_detection/tb_data_i

#===========================================================================
# pulse_detection IN
#===========================================================================
add wave -divider " pulse_detection"
add wave -color white -format Analog-Step -radix signed sim:/tb_pulse_detection/dut/data_jord_filt
add wave -color white -format Analog-Step -radix signed sim:/tb_pulse_detection/dut/cfd_i/cfd_signal
add wave -color green -radix signed sim:/tb_pulse_detection/dut/cfd_i/data_slope
add wave -color green -radix binary sim:/tb_pulse_detection/dut/cfd_i/slope_pos_flag
add wave -color green -radix binary sim:/tb_pulse_detection/dut/cfd_i/zero_cross_flag
add wave -color green -radix binary sim:/tb_pulse_detection/dut/cfd_i/above_th_flag
add wave -color green -radix binary sim:/tb_pulse_detection/dut/cfd_i/pulse_incoming
add wave -color green -radix unsigned sim:/tb_pulse_detection/dut/cfd_i/pulse_timeout_cnt
add wave -color white -radix binary sim:/tb_pulse_detection/tb_pulse_trig
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