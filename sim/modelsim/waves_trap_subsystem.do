#==============================================================================
# File: waves_trap_subsystem.do
#
# Description:
#   Waveform configuration for the trap_subsystem testbench in ModelSim.
#   Signals are grouped logically by function.
#
# Usage:
#   source waves_trap_subsystem.do
#==============================================================================

quietly WaveActivateNextPane {} 0

#===========================================================================
# Simulation
#===========================================================================
add wave -divider " CLK/RST_N "
add wave -color green -radix binary sim:/tb_trap_subsystem/tb_clk
add wave -color green -radix binary sim:/tb_trap_subsystem/tb_rst_n

#===========================================================================
# INPUTS
#===========================================================================
add wave -divider " INPUTS "
add wave -color green -radix binary sim:/tb_trap_subsystem/tb_ce
add wave -color white -format Analog-Step -radix unsigned sim:/tb_trap_subsystem/tb_data_i
add wave -color green -radix binary sim:/tb_trap_subsystem/tb_sync_pulse

#===========================================================================
# SHIFT REGISTER  (internal)
#===========================================================================
add wave -divider " SHIFT REG "
add wave -color green -radix unsigned sim:/tb_trap_subsystem/dut/u_valid_i/cnt_arm
add wave -color white -radix unsigned sim:/tb_trap_subsystem/dut/data_n
add wave -color green -radix unsigned sim:/tb_trap_subsystem/dut/u_valid_i/cnt_delay_mov
add wave -color green -radix unsigned sim:/tb_trap_subsystem/dut/data_mov_d
add wave -color green -radix binary sim:/tb_trap_subsystem/dut/delay_mov_ready
add wave -color green -radix unsigned sim:/tb_trap_subsystem/dut/u_valid_i/cnt_delay_jord
add wave -color white -radix unsigned sim:/tb_trap_subsystem/dut/data_jord_k
add wave -color white -radix unsigned sim:/tb_trap_subsystem/dut/data_jord_l
add wave -color white -radix unsigned sim:/tb_trap_subsystem/dut/data_jord_kl
add wave -color green -radix binary sim:/tb_trap_subsystem/dut/delay_jord_ready

#===========================================================================
# VALID TRACKER  (internal)
#===========================================================================
add wave -divider " VALID TRACKER "
add wave -color green -radix binary sim:/tb_trap_subsystem/dut/data_jord_valid
add wave -color green -radix binary sim:/tb_trap_subsystem/dut/data_mov_valid

#===========================================================================
# BASELINE RESTORER  (internal)
#===========================================================================
add wave -divider " BASELINE RESTORER "
add wave -color white -format Analog-Step -radix signed sim:/tb_trap_subsystem/dut/data_jord_filt
add wave -color green -radix signed sim:/tb_trap_subsystem/dut/jord_i/diff
add wave -color green -radix signed sim:/tb_trap_subsystem/dut/jord_i/acc1
add wave -color green -radix signed sim:/tb_trap_subsystem/dut/jord_i/Mdiff_scaled
add wave -color green -radix signed sim:/tb_trap_subsystem/dut/jord_i/acc2
add wave -color white -format Analog-Step -radix unsigned sim:/tb_trap_subsystem/dut/data_mov_filt
add wave -color green -radix binary sim:/tb_trap_subsystem/tb_baseline_trig
add wave -color green -radix unsigned sim:/tb_trap_subsystem/dut/baseline_i/baseline_held

#===========================================================================
# DUT OUTPUTS
#===========================================================================
add wave -divider " DUT OUTPUTS "
add wave -color white -format Analog-Step -radix signed sim:/tb_trap_subsystem/tb_data_filtered
add wave -color green -radix binary sim:/tb_trap_subsystem/tb_data_filtered_valid
add wave -color green -radix binary sim:/tb_trap_subsystem/tb_stat_error

#===========================================================================
# JORDANOV_FILTER VALIDATION  (output vs python reference)
#===========================================================================
add wave -divider " JORDANOV_FILTER VALIDATION "

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