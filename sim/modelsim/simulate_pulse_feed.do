#==============================================================================
# File: simulate_pulse_feed.do
#
# Description:
#   ModelSim simulation script for tb_pulse_feed.
#   - Opens the simulation
#   - Loads waveform configuration
#   - Runs simulation
#   - Leaves GUI open for inspection
#
# Usage:
#   vsim -do simulate_pulse_feed.do
#==============================================================================

#--------------------------------------------------------------------------
# Launch the simulator
#--------------------------------------------------------------------------
vsim trap_filter.tb_pulse_feed -t 1ns

#--------------------------------------------------------------------------
# Load waveform configuration
#--------------------------------------------------------------------------
do waves_pulse_feed.do

#--------------------------------------------------------------------------
# Optional: add cursors or zoom
#--------------------------------------------------------------------------
# wave cursor active 1
# wave cursor add 50ns
