#------------------------------------------------------------------------------
# kc705_hdmi.xdc
# Pin constraints for Celery3D Phase 1 on KC705
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# System Clock (200 MHz LVDS)
#------------------------------------------------------------------------------
set_property PACKAGE_PIN AD12 [get_ports sys_clk_p]
set_property PACKAGE_PIN AD11 [get_ports sys_clk_n]
set_property IOSTANDARD LVDS [get_ports sys_clk_p]
set_property IOSTANDARD LVDS [get_ports sys_clk_n]

create_clock -period 5.000 -name sys_clk [get_ports sys_clk_p]

#------------------------------------------------------------------------------
# CPU Reset Button (active-HIGH)
#------------------------------------------------------------------------------
set_property PACKAGE_PIN AB7 [get_ports cpu_reset]
set_property IOSTANDARD LVCMOS15 [get_ports cpu_reset]

#------------------------------------------------------------------------------
# I2C Interface
#------------------------------------------------------------------------------
set_property PACKAGE_PIN L21 [get_ports iic_sda]
set_property PACKAGE_PIN K21 [get_ports iic_scl]
set_property IOSTANDARD LVCMOS25 [get_ports iic_sda]
set_property IOSTANDARD LVCMOS25 [get_ports iic_scl]
set_property PULLUP true [get_ports iic_sda]
set_property PULLUP true [get_ports iic_scl]

# I2C Mux Reset (active-low)
set_property PACKAGE_PIN P23 [get_ports iic_mux_reset_n]
set_property IOSTANDARD LVCMOS25 [get_ports iic_mux_reset_n]

#------------------------------------------------------------------------------
# HDMI Video Output
#------------------------------------------------------------------------------
# Pixel Clock
set_property PACKAGE_PIN K18 [get_ports hdmi_clk]
set_property IOSTANDARD LVCMOS25 [get_ports hdmi_clk]

# Sync Signals
set_property PACKAGE_PIN J18 [get_ports hdmi_hsync]
set_property PACKAGE_PIN H20 [get_ports hdmi_vsync]
set_property PACKAGE_PIN H17 [get_ports hdmi_de]
set_property IOSTANDARD LVCMOS25 [get_ports hdmi_hsync]
set_property IOSTANDARD LVCMOS25 [get_ports hdmi_vsync]
set_property IOSTANDARD LVCMOS25 [get_ports hdmi_de]

# HDMI Data Bus [15:0]
set_property PACKAGE_PIN B23 [get_ports {hdmi_data[0]}]
set_property PACKAGE_PIN A23 [get_ports {hdmi_data[1]}]
set_property PACKAGE_PIN E23 [get_ports {hdmi_data[2]}]
set_property PACKAGE_PIN D23 [get_ports {hdmi_data[3]}]
set_property PACKAGE_PIN F25 [get_ports {hdmi_data[4]}]
set_property PACKAGE_PIN E25 [get_ports {hdmi_data[5]}]
set_property PACKAGE_PIN E24 [get_ports {hdmi_data[6]}]
set_property PACKAGE_PIN D24 [get_ports {hdmi_data[7]}]
set_property PACKAGE_PIN F26 [get_ports {hdmi_data[8]}]
set_property PACKAGE_PIN E26 [get_ports {hdmi_data[9]}]
set_property PACKAGE_PIN G23 [get_ports {hdmi_data[10]}]
set_property PACKAGE_PIN G24 [get_ports {hdmi_data[11]}]
set_property PACKAGE_PIN J19 [get_ports {hdmi_data[12]}]
set_property PACKAGE_PIN H19 [get_ports {hdmi_data[13]}]
set_property PACKAGE_PIN L17 [get_ports {hdmi_data[14]}]
set_property PACKAGE_PIN L18 [get_ports {hdmi_data[15]}]

set_property IOSTANDARD LVCMOS25 [get_ports {hdmi_data[*]}]

# HDMI Interrupt (directly active high for ADV7511input, directly active high for ADV7511not used in Phase 1)
set_property PACKAGE_PIN AH24 [get_ports hdmi_int]
set_property IOSTANDARD LVCMOS25 [get_ports hdmi_int]

#------------------------------------------------------------------------------
# GPIO LEDs
#------------------------------------------------------------------------------
set_property PACKAGE_PIN AB8  [get_ports {led[0]}]
set_property PACKAGE_PIN AA8  [get_ports {led[1]}]
set_property PACKAGE_PIN AC9  [get_ports {led[2]}]
set_property PACKAGE_PIN AB9  [get_ports {led[3]}]
set_property PACKAGE_PIN AE26 [get_ports {led[4]}]
set_property PACKAGE_PIN G19  [get_ports {led[5]}]
set_property PACKAGE_PIN E18  [get_ports {led[6]}]
set_property PACKAGE_PIN F16  [get_ports {led[7]}]

set_property IOSTANDARD LVCMOS15 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS15 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS15 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS15 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS25 [get_ports {led[4]}]
set_property IOSTANDARD LVCMOS25 [get_ports {led[5]}]
set_property IOSTANDARD LVCMOS25 [get_ports {led[6]}]
set_property IOSTANDARD LVCMOS25 [get_ports {led[7]}]

#------------------------------------------------------------------------------
# GPIO DIP Switches
#------------------------------------------------------------------------------
set_property PACKAGE_PIN Y29  [get_ports {gpio_sw[0]}]
set_property PACKAGE_PIN W29  [get_ports {gpio_sw[1]}]
set_property PACKAGE_PIN AA28 [get_ports {gpio_sw[2]}]
set_property PACKAGE_PIN Y28  [get_ports {gpio_sw[3]}]

set_property IOSTANDARD LVCMOS25 [get_ports {gpio_sw[*]}]

#------------------------------------------------------------------------------
# Clock Constraints
#------------------------------------------------------------------------------
# Generated clocks are automatically created by Vivado from MMCM

# False paths for CDC between clock domains
set_false_path -from [get_clocks -of_objects [get_pins u_clock_gen/mmcm_inst/CLKOUT0]] \
               -to [get_clocks -of_objects [get_pins u_clock_gen/mmcm_inst/CLKOUT1]]
set_false_path -from [get_clocks -of_objects [get_pins u_clock_gen/mmcm_inst/CLKOUT1]] \
               -to [get_clocks -of_objects [get_pins u_clock_gen/mmcm_inst/CLKOUT0]]

# Async reset is asynchronous
set_false_path -from [get_ports cpu_reset]

#------------------------------------------------------------------------------
# I2C Timing (100 kHz - relaxed timing)
#------------------------------------------------------------------------------
set_max_delay -from [get_ports iic_sda] 100.0
set_max_delay -from [get_ports iic_scl] 100.0
set_max_delay -to [get_ports iic_sda] 100.0
set_max_delay -to [get_ports iic_scl] 100.0

#------------------------------------------------------------------------------
# HDMI Output Timing
# ADV7511 samples on rising edge of hdmi_clk
# Data should be stable before clock edge
#------------------------------------------------------------------------------
set_output_delay -clock [get_clocks -of_objects [get_pins u_clock_gen/mmcm_inst/CLKOUT1]] \
                 -max 2.0 [get_ports {hdmi_data[*] hdmi_de hdmi_hsync hdmi_vsync}]
set_output_delay -clock [get_clocks -of_objects [get_pins u_clock_gen/mmcm_inst/CLKOUT1]] \
                 -min -1.0 [get_ports {hdmi_data[*] hdmi_de hdmi_hsync hdmi_vsync}]

#------------------------------------------------------------------------------
# Bitstream Configuration
#------------------------------------------------------------------------------
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
