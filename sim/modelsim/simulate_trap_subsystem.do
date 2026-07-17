#==============================================================================
# File: simulate_trap_subsystem.do
#
# Description:
#   ModelSim simulation script for tb_trap_subsystem.vhd
#   - Opens the simulation
#   - Loads waveform configuration
#   - Runs simulation
#   - Leaves GUI open for inspection
#
# Usage:
#   vsim -do simulate_trap_subsystem.do
#==============================================================================

#--------------------------------------------------------------------------
# Launch the simulator
#--------------------------------------------------------------------------
vsim trap_filter.tb_trap_subsystem -t 1ns

#--------------------------------------------------------------------------
# Load waveform configuration
#--------------------------------------------------------------------------
do waves_trap_subsystem.do

#--------------------------------------------------------------------------
# Optional: add cursors or zoom
#--------------------------------------------------------------------------
# wave cursor active 1
# wave cursor add 50ns
