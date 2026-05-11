# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "CLK_FRE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "DIFFICULTY" -parent ${Page_0}
  ipgui::add_param $IPINST -name "UART_FRE" -parent ${Page_0}


}

proc update_PARAM_VALUE.CLK_FRE { PARAM_VALUE.CLK_FRE } {
	# Procedure called to update CLK_FRE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CLK_FRE { PARAM_VALUE.CLK_FRE } {
	# Procedure called to validate CLK_FRE
	return true
}

proc update_PARAM_VALUE.DIFFICULTY { PARAM_VALUE.DIFFICULTY } {
	# Procedure called to update DIFFICULTY when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.DIFFICULTY { PARAM_VALUE.DIFFICULTY } {
	# Procedure called to validate DIFFICULTY
	return true
}

proc update_PARAM_VALUE.UART_FRE { PARAM_VALUE.UART_FRE } {
	# Procedure called to update UART_FRE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.UART_FRE { PARAM_VALUE.UART_FRE } {
	# Procedure called to validate UART_FRE
	return true
}


proc update_MODELPARAM_VALUE.CLK_FRE { MODELPARAM_VALUE.CLK_FRE PARAM_VALUE.CLK_FRE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CLK_FRE}] ${MODELPARAM_VALUE.CLK_FRE}
}

proc update_MODELPARAM_VALUE.UART_FRE { MODELPARAM_VALUE.UART_FRE PARAM_VALUE.UART_FRE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.UART_FRE}] ${MODELPARAM_VALUE.UART_FRE}
}

proc update_MODELPARAM_VALUE.DIFFICULTY { MODELPARAM_VALUE.DIFFICULTY PARAM_VALUE.DIFFICULTY } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.DIFFICULTY}] ${MODELPARAM_VALUE.DIFFICULTY}
}

