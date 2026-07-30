#==============================================================================
# File: simulate_trig_subsystemº.do
#
# Description:
#   ModelSim simulation script for tb_pulse_detection.
#   - Opens the simulation
#   - Loads waveform configuration
#   - Runs simulation
#   - Leaves GUI open for inspection
#
# Usage:
#   vsim -do simulate_trig_subsystemº.do
#==============================================================================

#--------------------------------------------------------------------------
# Launch the simulator
#--------------------------------------------------------------------------
vsim trap_filter.tb_trig_subsystem -t 1ns

#--------------------------------------------------------------------------
# Load waveform configuration
#--------------------------------------------------------------------------
do waves_trig_subsystem.do

#--------------------------------------------------------------------------
# Optional: add cursors or zoom
#--------------------------------------------------------------------------
# wave cursor active 1
# wave cursor add 50ns
