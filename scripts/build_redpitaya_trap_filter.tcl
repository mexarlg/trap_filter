################################################################
# This is a generated script based on red pitaya block design
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]buil
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

################################################################
# Project and IP Repositories
################################################################

set PROJECT_NAME "redpitaya_trap_filter"
set PROJECT_DIR [file normalize "$script_folder/../build/redpitaya"]
set CONST_DIR    [file normalize "$script_folder/../constraints"]
set DEV_PART     "xc7z010clg400-1"
set BOARD_PART   "redpitaya.com:redpitaya-125-14:part0:1.0"

# Repositories holding the non Xilinx cores.
set REPO_DIRS [list \
   [file normalize "$script_folder/../ip"] \
]


################################################################
# Check if script is running in correct Vivado version.
################################################################
set scripts_vivado_version 2025.2
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
   puts ""
   if { [string compare $scripts_vivado_version $current_vivado_version] > 0 } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2042 -severity "WARNING" " This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. The script was created with a future version of Vivado; sourcing it may fail or produce unexpected results."}

   } else {
     catch {common::send_gid_msg -ssname BD::TCL -id 2041 -severity "WARNING" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. It is recommended to run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_bd_tcl to create an updated script."}

   }
}

################################################################
# START
################################################################

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   if { [file exists $PROJECT_DIR] } {
      puts "INFO: Existing project found at $PROJECT_DIR -- recreating."
      file delete -force $PROJECT_DIR
   }
   file mkdir $PROJECT_DIR
   create_project $PROJECT_NAME $PROJECT_DIR -part $DEV_PART -force
   set_property BOARD_PART      $BOARD_PART [current_project]
   set_property target_language VHDL        [current_project]
}

################################################################
# Register IP Repositories
################################################################

# Block Design Name
variable design_name
set design_name redpitaya_bd

set found_repos [list]
foreach repo $REPO_DIRS {
   if { [file exists $repo] } {
      lappend found_repos $repo
   } else {
      puts "WARNING: IP repository not found, skipping: $repo"
   }
}

if { [llength $found_repos] > 0 } {
   set repos [get_property ip_repo_paths [current_project]]
   foreach repo $found_repos {
      if { [lsearch -exact $repos $repo] < 0 } {
         lappend repos $repo
      }
   }
   set_property ip_repo_paths $repos [current_project]
   update_ip_catalog -rebuild
   puts "INFO: IP repositories registered: $found_repos"
}

# Creating design if needed
set errMsg ""
set nRet 0

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

if { ${design_name} eq "" } {
   #    1) Design_name not set

   set errMsg "Please set the variable <design_name> to a non-empty value."
   set nRet 1

} elseif { ${cur_design} ne "" && ${list_cells} eq "" } {
   #    2): Current design opened AND is empty AND names same.
   #    3): Current design opened AND is empty AND names diff; design_name NOT in project.
   #    4): Current design opened AND is empty AND names diff; design_name exists in project.

   if { $cur_design ne $design_name } {
      common::send_gid_msg -ssname BD::TCL -id 2001 -severity "INFO" "Changing value of <design_name> from <$design_name> to <$cur_design> since current design is empty."
      set design_name [get_property NAME $cur_design]
   }
   common::send_gid_msg -ssname BD::TCL -id 2002 -severity "INFO" "Constructing design in IPI design <$cur_design>..."

} elseif { ${cur_design} ne "" && $list_cells ne "" && $cur_design eq $design_name } {
   #    5) Current design opened AND has components AND same names.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 1
} elseif { [get_files -quiet ${design_name}.bd] ne "" } {
   #    6) Current opened design, has components, but diff names, design_name exists in project.
   #    7) No opened design, design_name exists in project.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 2

} else {
   #    8) No opened design, design_name not in project.
   #    9) Current opened design, has components, but diff names, design_name not in project.

   common::send_gid_msg -ssname BD::TCL -id 2003 -severity "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

   common::send_gid_msg -ssname BD::TCL -id 2004 -severity "INFO" "Making design <$design_name> as current_bd_design."
   current_bd_design $design_name

}

common::send_gid_msg -ssname BD::TCL -id 2005 -severity "INFO" "Currently the variable <design_name> is equal to \"$design_name\"."

if { $nRet != 0 } {
   catch {common::send_gid_msg -ssname BD::TCL -id 2006 -severity "ERROR" $errMsg}
   return $nRet
}

set bCheckIPsPassed 1

##################################################################
# CHECK IPs
##################################################################

set bCheckIPs 1
if { $bCheckIPs == 1 } {
   set list_check_ips "\ 
xilinx.com:ip:proc_sys_reset:5.0\
user:user:trap_filter:1.0\
xilinx.com:ip:ila:6.2\
xilinx.com:ip:xlslice:1.0\
DSPsandbox:FPGA-Notes-for-Scientists:adc:1.0\
DSPsandbox:FPGA-Notes-for-Scientists:clk:1.0\
xilinx.com:ip:vio:3.0\
"

   set list_ips_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2011 -severity "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2012 -severity "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

}

if { $bCheckIPsPassed != 1 } {
  common::send_gid_msg -ssname BD::TCL -id 2023 -severity "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 3
}

##################################################################
# DESIGN PROCs
##################################################################

# Procedure to create entire design
proc create_root_design { parentCell } {

  variable script_folder
  variable design_name

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create ports
  set adc_clk_n_i_0 [ create_bd_port -dir I adc_clk_n_i_0 ]
  set adc_clk_p_i_0 [ create_bd_port -dir I adc_clk_p_i_0 ]
  set adc_cdcs_o_0 [ create_bd_port -dir O adc_cdcs_o_0 ]
  set adc_data_1_i_0 [ create_bd_port -dir I -from 13 -to 0 adc_data_1_i_0 ]

  # Create instance: proc_sys_reset_0, and set properties
  set proc_sys_reset_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0 ]

  # Create instance: trap_filter_0, and set properties
  set trap_filter_0 [ create_bd_cell -type ip -vlnv user:user:trap_filter:1.0 trap_filter_0 ]
  set_property -dict [list \
    CONFIG.G_NOISE_THRESHOLD {50} \
    CONFIG.G_PILEUP_DECAY_VALUE {1000} \
  ] $trap_filter_0


  # Create instance: ila_0, and set properties
  set ila_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:ila:6.2 ila_0 ]
  set_property -dict [list \
    CONFIG.C_DATA_DEPTH {16384} \
    CONFIG.C_MONITOR_TYPE {Native} \
    CONFIG.C_NUM_OF_PROBES {11} \
    CONFIG.C_PROBE0_WIDTH {14} \
    CONFIG.C_PROBE1_WIDTH {15} \
    CONFIG.C_PROBE2_WIDTH {15} \
    CONFIG.C_PROBE3_WIDTH {12} \
    CONFIG.C_PROBE4_WIDTH {7} \
    CONFIG.C_PROBE5_WIDTH {3} \
    CONFIG.C_PROBE6_WIDTH {24} \
    CONFIG.C_PROBE9_WIDTH {10} \
  ] $ila_0


  # Create instance: xlslice_0, and set properties
  set xlslice_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 xlslice_0 ]
  set_property -dict [list \
    CONFIG.DIN_FROM {15} \
    CONFIG.DIN_TO {2} \
    CONFIG.DIN_WIDTH {16} \
  ] $xlslice_0

  # Create instance: adc_1, and set properties
  set adc_1 [ create_bd_cell -type ip -vlnv DSPsandbox:FPGA-Notes-for-Scientists:adc:1.0 adc_1 ]

  # Create instance: clk_0, and set properties
  set clk_0 [ create_bd_cell -type ip -vlnv DSPsandbox:FPGA-Notes-for-Scientists:clk:1.0 clk_0 ]

  # Create instance: vio_0, and set properties
  set vio_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:vio:3.0 vio_0 ]
  set_property -dict [list \
    CONFIG.C_NUM_PROBE_IN {0} \
    CONFIG.C_PROBE_OUT0_INIT_VAL {0x1} \
  ] $vio_0

  # Create port connections (CHANGE IF ANY IP PORT IS MODIFIED)
  connect_bd_net -net adc_1_adc_data_1_tdata  [get_bd_pins adc_1/adc_data_1_tdata] \
  [get_bd_pins xlslice_0/Din]
  connect_bd_net -net adc_clk_n_i_0_1  [get_bd_ports adc_clk_n_i_0] \
  [get_bd_pins clk_0/adc_clk_n_i]
  connect_bd_net -net adc_clk_p_i_0_1  [get_bd_ports adc_clk_p_i_0] \
  [get_bd_pins clk_0/adc_clk_p_i]
  connect_bd_net -net adc_data_1_i_0_1  [get_bd_ports adc_data_1_i_0] \
  [get_bd_pins adc_1/adc_data_1_i]
  connect_bd_net -net clk_0_adc_cdcs_o  [get_bd_pins clk_0/adc_cdcs_o] \
  [get_bd_ports adc_cdcs_o_0]
  connect_bd_net -net clk_0_clk_125  [get_bd_pins clk_0/clk_125] \
  [get_bd_pins adc_1/clk_125] \
  [get_bd_pins ila_0/clk] \
  [get_bd_pins proc_sys_reset_0/slowest_sync_clk] \
  [get_bd_pins trap_filter_0/CLK_I] \
  [get_bd_pins vio_0/clk]
  connect_bd_net -net clk_0_locked  [get_bd_pins clk_0/locked] \
  [get_bd_pins proc_sys_reset_0/dcm_locked]
  connect_bd_net -net proc_sys_reset_0_peripheral_aresetn  [get_bd_pins proc_sys_reset_0/peripheral_aresetn] \
  [get_bd_pins adc_1/resetn] \
  [get_bd_pins trap_filter_0/RST_N_I] \
  [get_bd_pins ila_0/probe8]
  connect_bd_net -net trap_filter_0_ERROR_OFLOW_O  [get_bd_pins trap_filter_0/ERROR_OFLOW_O] \
  [get_bd_pins ila_0/probe9]
  connect_bd_net -net trap_filter_0_LOG_FULL_O  [get_bd_pins trap_filter_0/LOG_FULL_O] \
  [get_bd_pins ila_0/probe7]
  connect_bd_net -net trap_filter_0_PILEUP_CNT_O  [get_bd_pins trap_filter_0/PILEUP_CNT_O] \
  [get_bd_pins ila_0/probe6]
  connect_bd_net -net trap_filter_0_PILEUP_EVENT_O  [get_bd_pins trap_filter_0/PILEUP_EVENT_O] \
  [get_bd_pins ila_0/probe10]
  connect_bd_net -net trap_filter_0_PULSE_AMPLITUDE_O  [get_bd_pins trap_filter_0/PULSE_AMPLITUDE_O] \
  [get_bd_pins ila_0/probe2]
  connect_bd_net -net trap_filter_0_PULSE_STATE_O  [get_bd_pins trap_filter_0/PULSE_STATE_O] \
  [get_bd_pins ila_0/probe5]
  connect_bd_net -net trap_filter_0_PULSE_TRAPEZOID_O  [get_bd_pins trap_filter_0/PULSE_TRAPEZOID_O] \
  [get_bd_pins ila_0/probe1]
  connect_bd_net -net trap_filter_0_PULSE_TRIGGERS_O  [get_bd_pins trap_filter_0/PULSE_TRIGGERS_O] \
  [get_bd_pins ila_0/probe4]
  connect_bd_net -net trap_filter_0_PULSE_T_RISE_O  [get_bd_pins trap_filter_0/PULSE_T_RISE_O] \
  [get_bd_pins ila_0/probe3]
  connect_bd_net -net vio_0_probe_out0  [get_bd_pins vio_0/probe_out0] \
  [get_bd_pins proc_sys_reset_0/ext_reset_in] \
  [get_bd_pins proc_sys_reset_0/aux_reset_in]
  connect_bd_net -net xlslice_0_Dout  [get_bd_pins xlslice_0/Dout] \
  [get_bd_pins trap_filter_0/DATA_I] \
  [get_bd_pins ila_0/probe0]

  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
}

create_root_design ""

##################################################################
# Top Wrapper
##################################################################

set bd_file [get_files ${design_name}.bd]
set wrapper [make_wrapper -files $bd_file -top -force]

add_files -norecurse -fileset sources_1 $wrapper
set_property top ${design_name}_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

set xdc_file [file join $CONST_DIR "trap_pulse_shaper_redpitaya.xdc"]
if { [file exists $xdc_file] } {
   add_files -fileset constrs_1 -norecurse $xdc_file
   puts "INFO: Constraints added from $xdc_file"
} else {
   puts "WARNING: Constraint file not found: $xdc_file"
}

puts "INFO: Project ready at ${PROJECT_DIR}/${PROJECT_NAME}.xpr"
puts "INFO: Top module set to ${design_name}_wrapper"
