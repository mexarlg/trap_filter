# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "G_ADC_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "G_BASE_MOV_DELAY_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "G_LOG_ADDR_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "G_NOISE_THRESHOLD" -parent ${Page_0}
  ipgui::add_param $IPINST -name "G_PEAK_MOV_DELAY_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "G_PILEUP_CNT_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "G_PILEUP_DECAY_VALUE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "G_SLOW_JORD_K_DELAY" -parent ${Page_0}
  ipgui::add_param $IPINST -name "G_SLOW_JORD_M_DELAY" -parent ${Page_0}
  ipgui::add_param $IPINST -name "G_SLOW_JORD_M_EXP_VALUE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "G_TIMESTAMP_DIV" -parent ${Page_0}
  ipgui::add_param $IPINST -name "G_T_RISE_MOV_DELAY_WIDTH" -parent ${Page_0}


}

proc update_PARAM_VALUE.G_ADC_WIDTH { PARAM_VALUE.G_ADC_WIDTH } {
	# Procedure called to update G_ADC_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.G_ADC_WIDTH { PARAM_VALUE.G_ADC_WIDTH } {
	# Procedure called to validate G_ADC_WIDTH
	return true
}

proc update_PARAM_VALUE.G_BASE_MOV_DELAY_WIDTH { PARAM_VALUE.G_BASE_MOV_DELAY_WIDTH } {
	# Procedure called to update G_BASE_MOV_DELAY_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.G_BASE_MOV_DELAY_WIDTH { PARAM_VALUE.G_BASE_MOV_DELAY_WIDTH } {
	# Procedure called to validate G_BASE_MOV_DELAY_WIDTH
	return true
}

proc update_PARAM_VALUE.G_LOG_ADDR_WIDTH { PARAM_VALUE.G_LOG_ADDR_WIDTH } {
	# Procedure called to update G_LOG_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.G_LOG_ADDR_WIDTH { PARAM_VALUE.G_LOG_ADDR_WIDTH } {
	# Procedure called to validate G_LOG_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.G_NOISE_THRESHOLD { PARAM_VALUE.G_NOISE_THRESHOLD } {
	# Procedure called to update G_NOISE_THRESHOLD when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.G_NOISE_THRESHOLD { PARAM_VALUE.G_NOISE_THRESHOLD } {
	# Procedure called to validate G_NOISE_THRESHOLD
	return true
}

proc update_PARAM_VALUE.G_PEAK_MOV_DELAY_WIDTH { PARAM_VALUE.G_PEAK_MOV_DELAY_WIDTH } {
	# Procedure called to update G_PEAK_MOV_DELAY_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.G_PEAK_MOV_DELAY_WIDTH { PARAM_VALUE.G_PEAK_MOV_DELAY_WIDTH } {
	# Procedure called to validate G_PEAK_MOV_DELAY_WIDTH
	return true
}

proc update_PARAM_VALUE.G_PILEUP_CNT_WIDTH { PARAM_VALUE.G_PILEUP_CNT_WIDTH } {
	# Procedure called to update G_PILEUP_CNT_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.G_PILEUP_CNT_WIDTH { PARAM_VALUE.G_PILEUP_CNT_WIDTH } {
	# Procedure called to validate G_PILEUP_CNT_WIDTH
	return true
}

proc update_PARAM_VALUE.G_PILEUP_DECAY_VALUE { PARAM_VALUE.G_PILEUP_DECAY_VALUE } {
	# Procedure called to update G_PILEUP_DECAY_VALUE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.G_PILEUP_DECAY_VALUE { PARAM_VALUE.G_PILEUP_DECAY_VALUE } {
	# Procedure called to validate G_PILEUP_DECAY_VALUE
	return true
}

proc update_PARAM_VALUE.G_SLOW_JORD_K_DELAY { PARAM_VALUE.G_SLOW_JORD_K_DELAY } {
	# Procedure called to update G_SLOW_JORD_K_DELAY when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.G_SLOW_JORD_K_DELAY { PARAM_VALUE.G_SLOW_JORD_K_DELAY } {
	# Procedure called to validate G_SLOW_JORD_K_DELAY
	return true
}

proc update_PARAM_VALUE.G_SLOW_JORD_M_DELAY { PARAM_VALUE.G_SLOW_JORD_M_DELAY } {
	# Procedure called to update G_SLOW_JORD_M_DELAY when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.G_SLOW_JORD_M_DELAY { PARAM_VALUE.G_SLOW_JORD_M_DELAY } {
	# Procedure called to validate G_SLOW_JORD_M_DELAY
	return true
}

proc update_PARAM_VALUE.G_SLOW_JORD_M_EXP_VALUE { PARAM_VALUE.G_SLOW_JORD_M_EXP_VALUE } {
	# Procedure called to update G_SLOW_JORD_M_EXP_VALUE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.G_SLOW_JORD_M_EXP_VALUE { PARAM_VALUE.G_SLOW_JORD_M_EXP_VALUE } {
	# Procedure called to validate G_SLOW_JORD_M_EXP_VALUE
	return true
}

proc update_PARAM_VALUE.G_TIMESTAMP_DIV { PARAM_VALUE.G_TIMESTAMP_DIV } {
	# Procedure called to update G_TIMESTAMP_DIV when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.G_TIMESTAMP_DIV { PARAM_VALUE.G_TIMESTAMP_DIV } {
	# Procedure called to validate G_TIMESTAMP_DIV
	return true
}

proc update_PARAM_VALUE.G_T_RISE_MOV_DELAY_WIDTH { PARAM_VALUE.G_T_RISE_MOV_DELAY_WIDTH } {
	# Procedure called to update G_T_RISE_MOV_DELAY_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.G_T_RISE_MOV_DELAY_WIDTH { PARAM_VALUE.G_T_RISE_MOV_DELAY_WIDTH } {
	# Procedure called to validate G_T_RISE_MOV_DELAY_WIDTH
	return true
}


proc update_MODELPARAM_VALUE.G_ADC_WIDTH { MODELPARAM_VALUE.G_ADC_WIDTH PARAM_VALUE.G_ADC_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.G_ADC_WIDTH}] ${MODELPARAM_VALUE.G_ADC_WIDTH}
}

proc update_MODELPARAM_VALUE.G_SLOW_JORD_K_DELAY { MODELPARAM_VALUE.G_SLOW_JORD_K_DELAY PARAM_VALUE.G_SLOW_JORD_K_DELAY } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.G_SLOW_JORD_K_DELAY}] ${MODELPARAM_VALUE.G_SLOW_JORD_K_DELAY}
}

proc update_MODELPARAM_VALUE.G_SLOW_JORD_M_DELAY { MODELPARAM_VALUE.G_SLOW_JORD_M_DELAY PARAM_VALUE.G_SLOW_JORD_M_DELAY } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.G_SLOW_JORD_M_DELAY}] ${MODELPARAM_VALUE.G_SLOW_JORD_M_DELAY}
}

proc update_MODELPARAM_VALUE.G_SLOW_JORD_M_EXP_VALUE { MODELPARAM_VALUE.G_SLOW_JORD_M_EXP_VALUE PARAM_VALUE.G_SLOW_JORD_M_EXP_VALUE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.G_SLOW_JORD_M_EXP_VALUE}] ${MODELPARAM_VALUE.G_SLOW_JORD_M_EXP_VALUE}
}

proc update_MODELPARAM_VALUE.G_BASE_MOV_DELAY_WIDTH { MODELPARAM_VALUE.G_BASE_MOV_DELAY_WIDTH PARAM_VALUE.G_BASE_MOV_DELAY_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.G_BASE_MOV_DELAY_WIDTH}] ${MODELPARAM_VALUE.G_BASE_MOV_DELAY_WIDTH}
}

proc update_MODELPARAM_VALUE.G_PEAK_MOV_DELAY_WIDTH { MODELPARAM_VALUE.G_PEAK_MOV_DELAY_WIDTH PARAM_VALUE.G_PEAK_MOV_DELAY_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.G_PEAK_MOV_DELAY_WIDTH}] ${MODELPARAM_VALUE.G_PEAK_MOV_DELAY_WIDTH}
}

proc update_MODELPARAM_VALUE.G_T_RISE_MOV_DELAY_WIDTH { MODELPARAM_VALUE.G_T_RISE_MOV_DELAY_WIDTH PARAM_VALUE.G_T_RISE_MOV_DELAY_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.G_T_RISE_MOV_DELAY_WIDTH}] ${MODELPARAM_VALUE.G_T_RISE_MOV_DELAY_WIDTH}
}

proc update_MODELPARAM_VALUE.G_NOISE_THRESHOLD { MODELPARAM_VALUE.G_NOISE_THRESHOLD PARAM_VALUE.G_NOISE_THRESHOLD } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.G_NOISE_THRESHOLD}] ${MODELPARAM_VALUE.G_NOISE_THRESHOLD}
}

proc update_MODELPARAM_VALUE.G_PILEUP_DECAY_VALUE { MODELPARAM_VALUE.G_PILEUP_DECAY_VALUE PARAM_VALUE.G_PILEUP_DECAY_VALUE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.G_PILEUP_DECAY_VALUE}] ${MODELPARAM_VALUE.G_PILEUP_DECAY_VALUE}
}

proc update_MODELPARAM_VALUE.G_LOG_ADDR_WIDTH { MODELPARAM_VALUE.G_LOG_ADDR_WIDTH PARAM_VALUE.G_LOG_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.G_LOG_ADDR_WIDTH}] ${MODELPARAM_VALUE.G_LOG_ADDR_WIDTH}
}

proc update_MODELPARAM_VALUE.G_PILEUP_CNT_WIDTH { MODELPARAM_VALUE.G_PILEUP_CNT_WIDTH PARAM_VALUE.G_PILEUP_CNT_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.G_PILEUP_CNT_WIDTH}] ${MODELPARAM_VALUE.G_PILEUP_CNT_WIDTH}
}

proc update_MODELPARAM_VALUE.G_TIMESTAMP_DIV { MODELPARAM_VALUE.G_TIMESTAMP_DIV PARAM_VALUE.G_TIMESTAMP_DIV } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.G_TIMESTAMP_DIV}] ${MODELPARAM_VALUE.G_TIMESTAMP_DIV}
}

