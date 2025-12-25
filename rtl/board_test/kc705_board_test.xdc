# KC705 Board Test - Constraints
# Target: Xilinx Kintex-7 XC7K325T-2FFG900C

# ==============================================================================
# 200 MHz Differential System Clock
# ==============================================================================
set_property PACKAGE_PIN AD12 [get_ports sysclk_p]
set_property PACKAGE_PIN AD11 [get_ports sysclk_n]
set_property IOSTANDARD LVDS [get_ports sysclk_p]
set_property IOSTANDARD LVDS [get_ports sysclk_n]

create_clock -period 5.000 -name sysclk [get_ports sysclk_p]

# ==============================================================================
# GPIO LEDs (Active-High from FPGA)
# Note: LEDs 0-3 are in Bank 33 (LVCMOS15)
#       LEDs 4-7 are in different banks (LVCMOS25)
# ==============================================================================

# LED 0 - DS27
set_property PACKAGE_PIN AB8 [get_ports {gpio_led[0]}]
set_property IOSTANDARD LVCMOS15 [get_ports {gpio_led[0]}]

# LED 1 - DS26
set_property PACKAGE_PIN AA8 [get_ports {gpio_led[1]}]
set_property IOSTANDARD LVCMOS15 [get_ports {gpio_led[1]}]

# LED 2 - DS25
set_property PACKAGE_PIN AC9 [get_ports {gpio_led[2]}]
set_property IOSTANDARD LVCMOS15 [get_ports {gpio_led[2]}]

# LED 3 - DS3
set_property PACKAGE_PIN AB9 [get_ports {gpio_led[3]}]
set_property IOSTANDARD LVCMOS15 [get_ports {gpio_led[3]}]

# LED 4 - DS10
set_property PACKAGE_PIN AE26 [get_ports {gpio_led[4]}]
set_property IOSTANDARD LVCMOS25 [get_ports {gpio_led[4]}]

# LED 5 - DS1
set_property PACKAGE_PIN G19 [get_ports {gpio_led[5]}]
set_property IOSTANDARD LVCMOS25 [get_ports {gpio_led[5]}]

# LED 6 - DS4
set_property PACKAGE_PIN E18 [get_ports {gpio_led[6]}]
set_property IOSTANDARD LVCMOS25 [get_ports {gpio_led[6]}]

# LED 7 - DS2
set_property PACKAGE_PIN F16 [get_ports {gpio_led[7]}]
set_property IOSTANDARD LVCMOS25 [get_ports {gpio_led[7]}]

# ==============================================================================
# Configuration
# ==============================================================================
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 2.5 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
