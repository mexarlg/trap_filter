#==============================================================================
# generate_pulse_shaper_ip.tcl
#
# Packages the trapezoidal filter design as a reusable Vivado IP core.
# Sources are referenced in place, not copied.
#
# Run with:
#   vivado -mode batch -source scripts/generate_pulse_shaper_ip.tcl
#   source scripts/generate_pulse_shaper_ip.tcl        (vivado tcl console)
#
# Output:
#   ../ip/trap_filter/component.xml
#
# If build/vivado/trap_filter.xpr exists, or a project is already open, the
# repository is registered and the catalog refreshed so the core is immediately
# available under IP Catalog > User Repository.
#
#==============================================================================

#------------------------------------------------------------------------------
# IP Identification
#------------------------------------------------------------------------------

set IP_VENDOR       "user"
set IP_LIBRARY      "user"
set IP_NAME         "trap_filter"
set IP_VERSION      "1.0"
set IP_DISPLAY_NAME "Trapezoidal Pulse Shaper"
set IP_DESCRIPTION  "Trapezoidal shaping filter with triggering, pulse capture and event logging into a dual port BRAM"
set IP_TAXONOMY     "/UserIP"

set TOP_MODULE      "pulse_shaper_top"
set VHDL_LIBRARY    "trap_filter"

set SUPPORTED_FAMILIES [list \
    zynq       Production \
    artix7     Production \
]

#------------------------------------------------------------------------------
# Paths
#------------------------------------------------------------------------------

set SCRIPT_PATH [info script]
if {$SCRIPT_PATH eq ""} {
    error "Cannot resolve script location. Run as: vivado -mode batch -source scripts/generate_pulse_shaper_ip.tcl"
}

set SCRIPT_DIR [file dirname [file normalize $SCRIPT_PATH]]
set RTL_DIR    [file normalize "$SCRIPT_DIR/../src/rtl"]
set INTEG_DIR  [file normalize "$SCRIPT_DIR/../src/integration"]
set PKG_DIR    [file normalize "$SCRIPT_DIR/../src/pkg"]

set IP_REPO_DIR  [file normalize "$SCRIPT_DIR/../ip"]
set IP_DIR       [file normalize "$IP_REPO_DIR/$IP_NAME"]
set TMP_PROJ     [file normalize "$SCRIPT_DIR/../build/gen_ip_temp"]
set MAIN_PROJECT [file normalize "$SCRIPT_DIR/../build/vivado/trap_filter.xpr"]

set DEV_PART "xc7z020clg484-1"

#------------------------------------------------------------------------------
# Source Files
#------------------------------------------------------------------------------

set PKG_FILES [list \
    [file join $PKG_DIR "trap_filter_pkg.vhd"] \
]

set RTL_FILES [list \
    [file join $RTL_DIR "shift_register.vhd"] \
    [file join $RTL_DIR "delay_module.vhd"] \
    [file join $RTL_DIR "mov_avg_filter.vhd"] \
    [file join $RTL_DIR "jordanov_filter.vhd"] \
    [file join $RTL_DIR "baseline_restorer.vhd"] \
    [file join $RTL_DIR "trap_subsystem.vhd"] \
    [file join $RTL_DIR "cfd.vhd"] \
    [file join $RTL_DIR "pulse_detection.vhd"] \
    [file join $RTL_DIR "trig_gen.vhd"] \
    [file join $RTL_DIR "pileup_detection.vhd"] \
    [file join $RTL_DIR "trig_subsystem.vhd"] \
    [file join $RTL_DIR "pulse_capture.vhd"] \
    [file join $RTL_DIR "risetime_capture.vhd"] \
    [file join $RTL_DIR "capture_subsystem.vhd"] \
    [file join $RTL_DIR "bram_dp.vhd"] \
    [file join $RTL_DIR "pulse_logger.vhd"] \
    [file join $RTL_DIR "logger_subsystem.vhd"] \
    [file join $RTL_DIR "valid_subsystem.vhd"] \
    [file join $INTEG_DIR "pulse_shaper_top.vhd"] \
]

set ALL_VHDL [concat $PKG_FILES $RTL_FILES]

foreach f $ALL_VHDL {
    if {![file exists $f]} {
        error "Source file not found: $f"
    }
}

#------------------------------------------------------------------------------
# Generic definitions
#------------------------------------------------------------------------------

set PARAM_DEFS [list \
    {G_ADC_WIDTH              {Input Data}          {ADC width [bits]}                  12  15} \
    {G_SLOW_JORD_K_DELAY      {Trapezoidal Filter}  {Rise time k [samples]}             16  256} \
    {G_SLOW_JORD_M_DELAY      {Trapezoidal Filter}  {Flat top m [samples]}              16  256} \
    {G_SLOW_JORD_M_EXP_VALUE  {Trapezoidal Filter}  {Decay coefficient [12.4 fixed]}    0   65535} \
    {G_BASE_MOV_DELAY_WIDTH   {Moving Average}      {Baseline window [log2 samples]}    3   5} \
    {G_PEAK_MOV_DELAY_WIDTH   {Moving Average}      {Peak window [log2 samples]}        3   5} \
    {G_T_RISE_MOV_DELAY_WIDTH {Moving Average}      {Rise time window [log2 samples]}   3   5} \
    {G_NOISE_THRESHOLD        {Physical}            {Noise threshold [LSB]}             10  4096} \
    {G_PILEUP_DECAY_VALUE     {Physical}            {Pileup decay guard [samples]}      255 65535} \
    {G_LOG_ADDR_WIDTH         {Logger}              {Log depth [log2 events]}           10  16} \
    {G_PILEUP_CNT_WIDTH       {Logger}              {Pileup counter width [bits]}       12  24} \
    {G_TIMESTAMP_DIV          {Logger}              {Timestamp prescale [bits shifted]} 0   6} \
]

#------------------------------------------------------------------------------
# Remember an already open project so it can be restored at the end
#------------------------------------------------------------------------------

set INITIAL_PROJECT ""
set open_proj [current_project -quiet]

if {$open_proj ne ""} {
    set INITIAL_PROJECT [file normalize \
        [file join [get_property directory $open_proj] "[get_property name $open_proj].xpr"]]
    puts "INFO: Closing currently open project, it will be reopened afterwards"
    close_project
}

#------------------------------------------------------------------------------
# Prepare output directories
#------------------------------------------------------------------------------

if {[file exists $IP_REPO_DIR]} {
    puts "INFO: IP repository already present at $IP_REPO_DIR"
} else {
    puts "INFO: Creating IP repository at $IP_REPO_DIR"
    file mkdir $IP_REPO_DIR
}

if {[file exists $IP_DIR]} {
    puts "INFO: Removing previous IP output at $IP_DIR"
    file delete -force $IP_DIR
}

if {[file exists $TMP_PROJ]} {
    file delete -force $TMP_PROJ
}

file mkdir $IP_DIR
file mkdir $TMP_PROJ

#------------------------------------------------------------------------------
# Create the staging project
#------------------------------------------------------------------------------

puts "INFO: Creating staging project for part $DEV_PART"

create_project ${IP_NAME}_package $TMP_PROJ -part $DEV_PART -force
set_property target_language VHDL [current_project]

add_files -norecurse -fileset sources_1 $ALL_VHDL

set_property library   $VHDL_LIBRARY [get_files $ALL_VHDL]
set_property file_type {VHDL 2008}   [get_files $ALL_VHDL]

update_compile_order -fileset sources_1

set_property top     $TOP_MODULE   [get_filesets sources_1]
set_property top_lib $VHDL_LIBRARY [get_filesets sources_1]

update_compile_order -fileset sources_1

if {[get_property top [get_filesets sources_1]] ne $TOP_MODULE} {
    error "Top module could not be resolved to $TOP_MODULE"
}

#------------------------------------------------------------------------------
# Package the project, referencing sources in place
#------------------------------------------------------------------------------

puts "INFO: Packaging into $IP_DIR"

ipx::package_project \
    -root_dir    $IP_DIR \
    -vendor      $IP_VENDOR \
    -library     $IP_LIBRARY \
    -taxonomy    $IP_TAXONOMY \
    -set_current true \
    -force

set core [ipx::current_core]

set_property vendor              $IP_VENDOR          $core
set_property library             $IP_LIBRARY         $core
set_property name                $IP_NAME            $core
set_property version             $IP_VERSION         $core
set_property display_name        $IP_DISPLAY_NAME    $core
set_property description         $IP_DESCRIPTION     $core
set_property vendor_display_name $IP_VENDOR          $core
set_property taxonomy            $IP_TAXONOMY        $core
set_property supported_families  $SUPPORTED_FAMILIES $core
set_property core_revision       1                   $core

ipx::merge_project_changes files $core

#------------------------------------------------------------------------------
# Clock and Reset interfaces
#------------------------------------------------------------------------------

proc infer_signal_if {core port abstraction} {
    if {[llength [ipx::get_ports $port -of_objects $core]] == 0} {
        puts "WARNING: port $port not found, skipping interface inference"
        return ""
    }
    if {[llength [ipx::get_bus_interfaces $port -of_objects $core]] == 0} {
        ipx::infer_bus_interface $port $abstraction $core
    }
    return [ipx::get_bus_interfaces $port -of_objects $core]
}

proc set_bus_param {bus_if name value} {
    if {$bus_if eq ""} {
        return
    }
    if {[llength [ipx::get_bus_parameters $name -of_objects $bus_if]] == 0} {
        ipx::add_bus_parameter $name $bus_if
    }
    set_property value $value [ipx::get_bus_parameters $name -of_objects $bus_if]
}

set clk_if [infer_signal_if $core CLK_I   xilinx.com:signal:clock_rtl:1.0]
set rst_if [infer_signal_if $core RST_N_I xilinx.com:signal:reset_rtl:1.0]

set_bus_param $rst_if POLARITY         ACTIVE_LOW
set_bus_param $clk_if ASSOCIATED_RESET RST_N_I

#------------------------------------------------------------------------------
# Customisation GUI
#------------------------------------------------------------------------------

foreach pdef $PARAM_DEFS {
    lassign $pdef pname pgroup pdisplay pmin pmax
    if {[catch {set uparam [ipx::get_user_parameters $pname -of_objects $core]}]} { continue }
    if {$uparam eq ""} { continue }
    set_property value_validation_type          range_long $uparam
    set_property value_validation_range_minimum $pmin      $uparam
    set_property value_validation_range_maximum $pmax      $uparam
}

ipx::create_xgui_files $core
ipx::update_dependency $core

#------------------------------------------------------------------------------
# Finalise
#------------------------------------------------------------------------------

ipx::update_checksums $core
ipx::check_integrity  $core
ipx::save_core        $core

close_project

file delete -force $TMP_PROJ

puts "INFO: IP packaged at ${IP_DIR}/component.xml"

#------------------------------------------------------------------------------
# Register the repository in the catalog
#------------------------------------------------------------------------------

set TARGET_PROJECT ""

if {$INITIAL_PROJECT ne "" && [file exists $INITIAL_PROJECT]} {
    set TARGET_PROJECT $INITIAL_PROJECT
} elseif {[file exists $MAIN_PROJECT]} {
    set TARGET_PROJECT $MAIN_PROJECT
}

if {$TARGET_PROJECT eq ""} {
    puts "INFO: No project found, nothing to register"
    puts "INFO: Add the repository manually with:"
    puts "INFO:   set_property ip_repo_paths $IP_REPO_DIR \[current_project\]"
    puts "INFO:   update_ip_catalog -rebuild"
} else {
    puts "INFO: Registering repository in [file tail $TARGET_PROJECT]"
    open_project $TARGET_PROJECT

    set repos [get_property ip_repo_paths [current_project]]
    if {[lsearch -exact $repos $IP_REPO_DIR] < 0} {
        lappend repos $IP_REPO_DIR
        set_property ip_repo_paths $repos [current_project]
    }

    update_ip_catalog -rebuild

    if {$INITIAL_PROJECT eq ""} {
        close_project
    }
}

puts "INFO: Core available as ${IP_VENDOR}:${IP_LIBRARY}:${IP_NAME}:${IP_VERSION}"