#==============================================================================
# File: compile_shift_register.do
#
# Description:
#   Compiles all RTL and testbench files into the ModelSim work library.
#
# Usage:
#   do compile_shift_register.do
#
#==============================================================================


echo "--------------------------------------------"
echo "Compiling design"
echo "--------------------------------------------"


#------------------------------------------------------------------------------
# Create work library
#------------------------------------------------------------------------------

if {[file exists work]} {
    vdel -lib work -all
}
if {[file exists trap_filter]} {
    vdel -lib trap_filter -all
}

vlib work
vmap work work

vlib trap_filter
vmap trap_filter trap_filter


#------------------------------------------------------------------------------
# Compile RTL files
#------------------------------------------------------------------------------

echo "Compiling RTL..."

vcom -2008 -work trap_filter ../../src/pkg/trap_filter_pkg.vhd
vcom -2008 -work trap_filter ../../src/pkg/pulse_data_pkg.vhd
vcom -2008 -work trap_filter ../../src/rtl/pulse_feed.vhd
vcom -2008 -work trap_filter ../../src/rtl/shift_register.vhd


#------------------------------------------------------------------------------
# Compile Testbench files
#------------------------------------------------------------------------------

echo "Compiling Testbench..."

vcom -2008 -work trap_filter ../tb/tb_shift_register.vhd


echo "--------------------------------------------"
echo "Compilation finished"
echo "--------------------------------------------"