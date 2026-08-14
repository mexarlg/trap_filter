#==============================================================================
# File: compile_pulse_shaper_top.do
#
# Description:
#   Compiles all RTL and testbench files into the ModelSim work library.
#
# Usage:
#   do compile_pulse_shaper_top.do
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
vcom -2008 -work trap_filter ../../src/pkg/pulse_mult_data_pkg.vhd
vcom -2008 -work trap_filter ../../src/rtl/pulse_feed.vhd
vcom -2008 -work trap_filter ../../src/rtl/valid_subsystem.vhd
vcom -2008 -work trap_filter ../../src/rtl/shift_register.vhd
vcom -2008 -work trap_filter ../../src/rtl/delay_module.vhd
vcom -2008 -work trap_filter ../../src/rtl/jordanov_filter.vhd
vcom -2008 -work trap_filter ../../src/rtl/mov_avg_filter.vhd
vcom -2008 -work trap_filter ../../src/rtl/baseline_restorer.vhd
vcom -2008 -work trap_filter ../../src/rtl/trap_subsystem.vhd
vcom -2008 -work trap_filter ../../src/rtl/cfd.vhd
vcom -2008 -work trap_filter ../../src/rtl/pulse_detection.vhd
vcom -2008 -work trap_filter ../../src/rtl/trig_gen.vhd
vcom -2008 -work trap_filter ../../src/rtl/pileup_detection.vhd
vcom -2008 -work trap_filter ../../src/rtl/trig_subsystem.vhd
vcom -2008 -work trap_filter ../../src/rtl/pulse_capture.vhd
vcom -2008 -work trap_filter ../../src/rtl/risetime_capture.vhd
vcom -2008 -work trap_filter ../../src/rtl/peak_subsystem.vhd
vcom -2008 -work trap_filter ../../src/rtl/pulse_logger.vhd
vcom -2008 -work trap_filter ../../src/rtl/bram_dp.vhd
vcom -2008 -work trap_filter ../../src/rtl/logger_subsystem.vhd
vcom -2008 -work trap_filter ../../src/integration/pulse_shaper_top.vhd


#------------------------------------------------------------------------------
# Compile Testbench files
#------------------------------------------------------------------------------

echo "Compiling Testbench..."

vcom -2008 -work trap_filter ../tb/tb_pulse_shaper_top.vhd


echo "--------------------------------------------"
echo "Compilation finished"
echo "--------------------------------------------"