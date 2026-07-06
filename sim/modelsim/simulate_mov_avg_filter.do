#==============================================================================
# File: simulate_mov_avg_filter.do
#
# Description:
#   ModelSim simulation script for tb_mov_avg_filter.
#   - Opens the simulation
#   - Loads waveform configuration
#   - Runs simulation
#   - Leaves GUI open for inspection
#
# Usage:
#   vsim -do simulate_mov_avg_filter.do
#==============================================================================

#--------------------------------------------------------------------------
# Launch the simulator
#--------------------------------------------------------------------------
vsim trap_filter.tb_mov_avg_filter -t 1ns

#--------------------------------------------------------------------------
# Load waveform configuration
#--------------------------------------------------------------------------
do waves_mov_avg_filter.do

#--------------------------------------------------------------------------
# Optional: add cursors or zoom
#--------------------------------------------------------------------------
# wave cursor active 1
# wave cursor add 50ns
