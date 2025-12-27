# DDR3 Test Constraints for KC705
# This file adds constraints for GPIO LEDs and system reset
# DDR3 and clock constraints are handled by MIG IP (mig_7series_0.xdc)

# ==============================================================================
# System Reset - Active Low (directly from GPIO button SW4 South)
# ==============================================================================
# AB12 is GPIO_SW_S (South button) - directly active-low when pressed
# Design inverts this internally for MIG which expects active-high
set_property PACKAGE_PIN AB12 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS15 [get_ports sys_rst_n]
set_false_path -from [get_ports sys_rst_n]

# ==============================================================================
# GPIO LEDs (Active High)
# ==============================================================================
# From KC705 UG810 Table 1-15: GPIO LED Connections
# LED[0] through LED[7] directly connected to FPGA
set_property PACKAGE_PIN AB8  [get_ports {gpio_led[0]}]
set_property PACKAGE_PIN AA8  [get_ports {gpio_led[1]}]
set_property PACKAGE_PIN AC9  [get_ports {gpio_led[2]}]
set_property PACKAGE_PIN AB9  [get_ports {gpio_led[3]}]
set_property PACKAGE_PIN AE26 [get_ports {gpio_led[4]}]
set_property PACKAGE_PIN G19  [get_ports {gpio_led[5]}]
set_property PACKAGE_PIN E18  [get_ports {gpio_led[6]}]
set_property PACKAGE_PIN F16  [get_ports {gpio_led[7]}]

set_property IOSTANDARD LVCMOS15 [get_ports {gpio_led[0]}]
set_property IOSTANDARD LVCMOS15 [get_ports {gpio_led[1]}]
set_property IOSTANDARD LVCMOS15 [get_ports {gpio_led[2]}]
set_property IOSTANDARD LVCMOS15 [get_ports {gpio_led[3]}]
set_property IOSTANDARD LVCMOS25 [get_ports {gpio_led[4]}]
set_property IOSTANDARD LVCMOS25 [get_ports {gpio_led[5]}]
set_property IOSTANDARD LVCMOS25 [get_ports {gpio_led[6]}]
set_property IOSTANDARD LVCMOS25 [get_ports {gpio_led[7]}]

# LEDs are slow - no timing needed
set_false_path -to [get_ports {gpio_led[*]}]

# ==============================================================================
# BITSTREAM Configuration
# ==============================================================================
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 2.5 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
