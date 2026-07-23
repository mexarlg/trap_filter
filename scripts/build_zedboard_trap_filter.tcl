#==============================================================================
# build_trap_filter_vivado.tcl
#
# Creates the Vivado project for the trapezoidal filter design targeting
# the Avnet/Digilent ZedBoard (XC7Z020-1CLG484C).
#
# Run with:
#   vivado -mode batch -source build_trap_filter_vivado.tcl
#   source build_trap_filter_vivado.tcl        (vivado tcl console)
#
# Author: Aldo Lupio
# Date:   23/07/2026
#==============================================================================

#------------------------------------------------------------------------------
# Project Configuration
#------------------------------------------------------------------------------

set PROJECT_NAME    "trap_filter"
set TOP_MODULE      "trap_pulse_shaper_top"
set VHDL_LIBRARY    "trap_filter"

set SCRIPT_PATH [info script]
if {$SCRIPT_PATH eq ""} {
    error "Cannot resolve script location. Run as: vivado -mode batch -source scripts/build_trap_filter_vivado.tcl"
}

set SCRIPT_DIR  [file dirname [file normalize $SCRIPT_PATH]]
set PROJECT_DIR [file normalize "$SCRIPT_DIR/../build/vivado"]
set RTL_DIR     [file normalize "$SCRIPT_DIR/../src/rtl"]
set PKG_DIR     [file normalize "$SCRIPT_DIR/../src/pkg"]
set CONST_DIR   [file normalize "$SCRIPT_DIR/../constraints"]

#------------------------------------------------------------------------------
# FPGA Selection: ZedBoard Zynq-7000
#------------------------------------------------------------------------------

#   XC7Z020-1CLG484C
set DEV_PART        "xc7z020clg484-1"
set BOARD_PART      "avnet.com:zedboard:part0:1.4"

#------------------------------------------------------------------------------
# Debug core configuration
#------------------------------------------------------------------------------

set ILA_DEPTH       2048
set USE_BOARD_PART  0   ;# set to 1 if Avnet board files are installed

#------------------------------------------------------------------------------
# Create or recreate the project
#------------------------------------------------------------------------------

set PROJECT_FILE "${PROJECT_DIR}/${PROJECT_NAME}.xpr"

if {[file exists $PROJECT_DIR]} {
    puts "INFO: Existing project found at $PROJECT_DIR -- recreating."
    catch {close_project}
    file delete -force $PROJECT_DIR
}

file mkdir $PROJECT_DIR
puts "INFO: Creating project '$PROJECT_NAME' for part $DEV_PART"

create_project $PROJECT_NAME $PROJECT_DIR -part $DEV_PART -force

if {$USE_BOARD_PART} {
    if {[llength [get_board_parts -quiet $BOARD_PART]]} {
        set_property board_part $BOARD_PART [current_project]
    } else {
        puts "WARNING: Board part $BOARD_PART not found -- continuing with part only."
    }
}

set_property target_language VHDL [current_project]

#------------------------------------------------------------------------------
# Add RTL Source Files
#------------------------------------------------------------------------------

# Packages (order matters for VHDL analysis)
set PKG_FILES [list \
    [file join $PKG_DIR "trap_filter_pkg.vhd"] \
    [file join $PKG_DIR "pulse_data_pkg.vhd"] \
]

# RTL
set RTL_FILES [list \
    [file join $RTL_DIR "pulse_feed.vhd"] \
    [file join $RTL_DIR "delay_unit_sr.vhd"] \
    [file join $RTL_DIR "delay_trap.vhd"] \
    [file join $RTL_DIR "mov_avg_filter.vhd"] \
    [file join $RTL_DIR "jordanov_filter.vhd"] \
    [file join $RTL_DIR "valid_tracker.vhd"] \
    [file join $RTL_DIR "baseline_restorer.vhd"] \
    [file join $RTL_DIR "trap_subsystem.vhd"] \
    [file join $RTL_DIR "trap_pulse_shaper_top.vhd"] \
]

set ALL_VHDL [concat $PKG_FILES $RTL_FILES]

foreach f $ALL_VHDL {
    if {![file exists $f]} {
        error "Source file not found: $f"
    }
}

add_files -norecurse -fileset sources_1 $ALL_VHDL

# Assign the custom VHDL library and VHDL-2008 to every source
set_property library   $VHDL_LIBRARY [get_files $ALL_VHDL]
set_property file_type {VHDL 2008}   [get_files $ALL_VHDL]

# Enforce compile order explicitly (packages first)
set_property source_mgmt_mode DisplayOnly [current_project]
update_compile_order -fileset sources_1
reorder_files -fileset sources_1 -front $ALL_VHDL

#------------------------------------------------------------------------------
# Add RTL Top Wrapper
#------------------------------------------------------------------------------

set_property top $TOP_MODULE [get_filesets sources_1]
set_property top_lib $VHDL_LIBRARY [get_filesets sources_1]

#------------------------------------------------------------------------------
# Add Constraints (Physical / Timing)
#------------------------------------------------------------------------------

set XDC_FILE [file join $CONST_DIR "trap_pulse_shaper_zedboard.xdc"]

if {![file exists $XDC_FILE]} {
    error "Constraint file not found: $XDC_FILE"
}

add_files -fileset constrs_1 -norecurse $XDC_FILE


#------------------------------------------------------------------------------
# VIO
#------------------------------------------------------------------------------

create_ip -name vio -vendor xilinx.com -library ip -module_name vio_trap

set_property -dict [list \
    CONFIG.C_NUM_PROBE_OUT        {1} \
    CONFIG.C_NUM_PROBE_IN         {0} \
    CONFIG.C_PROBE_OUT0_WIDTH     {1} \
    CONFIG.C_PROBE_OUT0_INIT_VAL  {0x0} \
] [get_ips vio_trap]

generate_target all [get_ips vio_trap]

update_compile_order -fileset sources_1

#------------------------------------------------------------------------------
# Add Simulation TB
#------------------------------------------------------------------------------

# set SIM_FILES [list [file join $SCRIPT_DIR ".." "sim" "tb_delay_unit.vhd"]]
# add_files -fileset sim_1 -norecurse $SIM_FILES
# set_property library $VHDL_LIBRARY [get_files $SIM_FILES]
# set_property file_type {VHDL 2008} [get_files $SIM_FILES]

#------------------------------------------------------------------------------
# Synthesis / Implementation strategy
#------------------------------------------------------------------------------

set_property strategy "Vivado Synthesis Defaults" [get_runs synth_1]
set_property strategy "Vivado Implementation Defaults" [get_runs impl_1]

# Keep hierarchy readable for debug probing
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]

# Required so debug cores are inserted correctly
set_property STEPS.SYNTH_DESIGN.ARGS.KEEP_EQUIVALENT_REGISTERS true [get_runs synth_1]

#------------------------------------------------------------------------------
# Save and report
#------------------------------------------------------------------------------

update_compile_order -fileset sources_1

puts "INFO: Project created at $PROJECT_FILE"
puts "INFO: Top module set to $TOP_MODULE (library $VHDL_LIBRARY)"