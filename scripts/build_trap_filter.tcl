#==============================================================================
# build_trap_filter.tcl
#
# Creates the Lattice Radiant project for the trapezoidal filter 
# design targeting the CertusPro-NX LFCPNX-100.
#
# Run with:
#   radiantc build_trap_filter.tcl         (command line, Linux or Windows)
#   source build_trap_filter.tcl           (radiant tcl console)
#
# Author: Aldo Lupio
# Date:   09/07/2026
#
# cd /Users/aldor/Desktop/irap/trap_filter/trap_filter/scripts
#==============================================================================

#------------------------------------------------------------------------------
# Project Configuration
#------------------------------------------------------------------------------

set PROJECT_NAME    "trap_filter"

set SCRIPT_PATH [info script]
if {$SCRIPT_PATH eq ""} {
    error "Cannot resolve script location. Run as: radiantc [file join scripts build_trap_filter.tcl]"
}

set SCRIPT_DIR  [file dirname [file normalize $SCRIPT_PATH]]
set PROJECT_DIR [file normalize "$SCRIPT_DIR/../build/radiant"]
set RTL_DIR     [file normalize "$SCRIPT_DIR/../src/rtl"]
set PKG_DIR     [file normalize "$SCRIPT_DIR/../src/pkg"]
set CONST_DIR   [file normalize "$SCRIPT_DIR/../constraints"]

#------------------------------------------------------------------------------
# FPGA Selection: CertusPro-NX LFCPNX-100
#------------------------------------------------------------------------------

#   LFCPNX-100-9LFG672C
set DEV_FAMILY      "LFCPNX"
set DEV_DEVICE      "LFCPNX-100"
set DEV_PART        "LFCPNX-100-9LFG672C"
set DEV_PERFORMANCE "9_High-Performance_1.0V"
set DEV_OPERATION   "Commercial"

#------------------------------------------------------------------------------
# Synthesis Tool: "lse" (Lattice Synthesis Engine) or "synplify"
#------------------------------------------------------------------------------

set SYNTHESIS_TOOL  "lse"

#------------------------------------------------------------------------------
# Create or recreate the project
#------------------------------------------------------------------------------

set PROJECT_FILE "${PROJECT_DIR}/${PROJECT_NAME}.rdf"

# If the project already exists, remove it
if {[file exists $PROJECT_FILE]} {
    puts "INFO: Existing project found at $PROJECT_FILE -- recreating."
    catch {prj_close}
    file delete -force $PROJECT_DIR
}

file mkdir $PROJECT_DIR
puts "INFO: Creating project '$PROJECT_NAME' for part $DEV_PART"

set OLD_PWD [pwd]
cd $PROJECT_DIR
puts "INFO: Creating project in [pwd]"

prj_create \
    -name        $PROJECT_NAME \
    -dev         $DEV_PART \
    -performance $DEV_PERFORMANCE \
    -synthesis   $SYNTHESIS_TOOL \
    -impl        "impl1" \
    -impl_dir    "impl1"

# VHDL 2008 and library definition (trap_filter)
prj_set_strategy_value -strategy Strategy1 lse_vhdl2008=True
prj_set_impl_opt -impl "impl1" {lib} {trap_filter}

#------------------------------------------------------------------------------
# NEXT STEPS
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Add RTL Source Files
#------------------------------------------------------------------------------

# Packages
prj_add_source [file join $PKG_DIR "trap_filter_pkg.vhd"]

# RTL
prj_add_source [file join $RTL_DIR "delay_unit_sr.vhd"]
prj_add_source [file join $RTL_DIR "delay_trap.vhd"]
prj_add_source [file join $RTL_DIR "mov_avg_filter.vhd"]
prj_add_source [file join $RTL_DIR "jordanov_filter.vhd"]
prj_add_source [file join $RTL_DIR "valid_tracker.vhd"]
prj_add_source [file join $RTL_DIR "baseline_restorer.vhd"]
prj_add_source [file join $RTL_DIR "trap_subsystem.vhd"]

#------------------------------------------------------------------------------
# Add RTL Top Wrapper
#------------------------------------------------------------------------------

prj_set_impl_opt -impl "impl1" "top" "trap_subsystem"

#------------------------------------------------------------------------------
# Add Constraints (Physical / Timing)
#------------------------------------------------------------------------------

prj_add_source [file join $CONST_DIR "trap_pulse_shaper.pdc"]
prj_add_source [file join $CONST_DIR "trap_pulse_shaper.ldc"]

#------------------------------------------------------------------------------
# Add IP Sources
#------------------------------------------------------------------------------

# prj_add_source [file join $SCRIPT_DIR ".." "ip" "fifo_delay" "fifo_delay.ipx"]

#------------------------------------------------------------------------------
# Add Simulation TB
#------------------------------------------------------------------------------

# prj_add_source -simulate_only [file join $SCRIPT_DIR ".." "sim" "tb_delay_unit.v"]

#------------------------------------------------------------------------------
# Save and report
#------------------------------------------------------------------------------

prj_save
cd $OLD_PWD
puts "INFO: Project created at $PROJECT_FILE"