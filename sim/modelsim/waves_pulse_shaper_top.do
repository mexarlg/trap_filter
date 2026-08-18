#==============================================================================
# File: waves_pulse_shaper_top.do
#
# Description:
#   Waveform configuration for the trap_subsystem testbench in ModelSim.
#   Signals are grouped logically by function.
#
# Usage:
#   source waves_pulse_shaper_top.do
#==============================================================================

quietly WaveActivateNextPane {} 0

#===========================================================================
# Simulation
#===========================================================================
add wave -divider " CLK/RST_N "
add wave -color green -radix binary sim:/tb_pulse_shaper_top/tb_clk
add wave -color green -radix binary sim:/tb_pulse_shaper_top/tb_rst_n

#===========================================================================
# INPUTS
#===========================================================================
add wave -divider " INPUTS "
add wave -color green -radix binary sim:/tb_pulse_shaper_top/tb_ce
add wave -color white -format Analog-Step -radix unsigned sim:/tb_pulse_shaper_top/tb_data_i

#===========================================================================
# TRIG_SS
#===========================================================================
add wave -divider " TRIG_SS "
add wave -color green -radix signed sim:/tb_pulse_shaper_top/dut/trig_ss_i/pulse_detect_i/data_jord_filt
add wave -color green -radix signed sim:/tb_pulse_shaper_top/dut/trig_ss_i/pulse_detect_i/cfd_i/cfd_signal
add wave -color green -radix signed sim:/tb_pulse_shaper_top/dut/trig_ss_i/pulse_detect_i/cfd_i/above_th_flag
add wave -color green -radix signed sim:/tb_pulse_shaper_top/dut/trig_ss_i/pulse_detect_i/cfd_i/slope_pos_flag
add wave -color green -radix signed sim:/tb_pulse_shaper_top/dut/trig_ss_i/pulse_detect_i/cfd_i/pulse_incoming
add wave -color green -radix binary sim:/tb_pulse_shaper_top/dut/pulse_triggers
add wave -color green -radix binary sim:/tb_pulse_shaper_top/dut/pulse_clean
add wave -color green -radix binary sim:/tb_pulse_shaper_top/tb_pileup_event
add wave -color green -radix unsigned sim:/tb_pulse_shaper_top/tb_pileup_cnt

#===========================================================================
# TRAP_SS
#===========================================================================
add wave -divider " TRAP_SS "
add wave -color green -radix signed sim:/tb_pulse_shaper_top/dut/trap_ss_i/jord_i/acc2
add wave -color green -radix signed sim:/tb_pulse_shaper_top/dut/trap_ss_i/data_jord_filt
add wave -color green -radix signed sim:/tb_pulse_shaper_top/dut/capture_ss_i/data_mov_filt
add wave -color white -format Analog-Step -radix signed sim:/tb_pulse_shaper_top/tb_pulse_trapezoid

#===========================================================================
# PEAK_SS
#===========================================================================
add wave -divider " PEAK_SS "
add wave -color green -radix signed sim:/tb_pulse_shaper_top/tb_pulse_amplitude
add wave -color green -radix unsigned sim:/tb_pulse_shaper_top/dut/capture_ss_i/data_i_t_rise
add wave -color green -radix unsigned sim:/tb_pulse_shaper_top/dut/capture_ss_i/rise_capture_i/amplitude
add wave -color green -radix unsigned sim:/tb_pulse_shaper_top/dut/capture_ss_i/rise_capture_i/amplitude_th_90
add wave -color green -radix unsigned sim:/tb_pulse_shaper_top/dut/capture_ss_i/rise_capture_i/amplitude_th_10
add wave -color green -radix binary sim:/tb_pulse_shaper_top/dut/capture_ss_i/rise_capture_i/is_below_90
add wave -color green -radix binary sim:/tb_pulse_shaper_top/dut/capture_ss_i/rise_capture_i/is_above_10
add wave -color green -radix unsigned sim:/tb_pulse_shaper_top/dut/capture_ss_i/rise_capture_i/state
add wave -color green -radix unsigned sim:/tb_pulse_shaper_top/tb_pulse_t_rise

#===========================================================================
# VALID_SS
#===========================================================================
add wave -divider " VALID_SS "
add wave -color green -radix binary sim:/tb_pulse_shaper_top/dut/valid_ss_i/delays_ready
add wave -color white -radix binary sim:/tb_pulse_shaper_top/tb_pulse_valid
add wave -color green -radix binary sim:/tb_pulse_shaper_top/tb_error_oflow

#===========================================================================
# LOGGER_SS
#===========================================================================
add wave -divider " LOGGER_SS "
add wave -color green -radix hex sim:/tb_pulse_shaper_top/tb_log_pulse_data
add wave -color green -radix hex sim:/tb_pulse_shaper_top/tb_log_timestamp_data
add wave -color green -radix unsigned sim:/tb_pulse_shaper_top/tb_timestamp_cnt

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