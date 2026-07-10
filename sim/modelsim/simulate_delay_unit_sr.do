#==============================================================================
# File: simulate_delay_unit_sr.do
#
# Description:
#   ModelSim simulation script for tb_delay_unit_sr.
#   - Opens the simulation
#   - Loads waveform configuration
#   - Runs simulation
#   - Leaves GUI open for inspection
#
# Usage:
#   vsim -do simulate_delay_unit_sr.do
#==============================================================================

#--------------------------------------------------------------------------
# Launch the simulator
#--------------------------------------------------------------------------
vsim trap_filter.tb_delay_unit_sr -t 1ns

#--------------------------------------------------------------------------
# Load waveform configuration
#--------------------------------------------------------------------------
do waves_delay_unit_sr.do

#--------------------------------------------------------------------------
# Optional: add cursors or zoom
#--------------------------------------------------------------------------
# wave cursor active 1
# wave cursor add 50ns
