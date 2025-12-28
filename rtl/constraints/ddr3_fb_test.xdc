# DDR3 Framebuffer Test Constraints for KC705
# Combines DDR3 memory interface with HDMI video output
# DDR3 and main clock constraints are handled by MIG IP

# ==============================================================================
# System Reset - Active Low (directly from GPIO button SW4 South)
# ==============================================================================
set_property PACKAGE_PIN AB12 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS15 [get_ports sys_rst_n]
set_false_path -from [get_ports sys_rst_n]

# ==============================================================================
# GPIO LEDs (Active High)
# ==============================================================================
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

set_false_path -to [get_ports {gpio_led[*]}]

# ==============================================================================
# HDMI Output (ADV7511 HDMI Transmitter) - Bank 12/13 (HR, 2.5V)
# ==============================================================================
# HDMI Data Bus (16-bit YCbCr 4:2:2 to ADV7511 D[23:8])
set_property PACKAGE_PIN B23 [get_ports {hdmi_d[0]}]
set_property PACKAGE_PIN A23 [get_ports {hdmi_d[1]}]
set_property PACKAGE_PIN E23 [get_ports {hdmi_d[2]}]
set_property PACKAGE_PIN D23 [get_ports {hdmi_d[3]}]
set_property PACKAGE_PIN F25 [get_ports {hdmi_d[4]}]
set_property PACKAGE_PIN E25 [get_ports {hdmi_d[5]}]
set_property PACKAGE_PIN E24 [get_ports {hdmi_d[6]}]
set_property PACKAGE_PIN D24 [get_ports {hdmi_d[7]}]
set_property PACKAGE_PIN F26 [get_ports {hdmi_d[8]}]
set_property PACKAGE_PIN E26 [get_ports {hdmi_d[9]}]
set_property PACKAGE_PIN G23 [get_ports {hdmi_d[10]}]
set_property PACKAGE_PIN G24 [get_ports {hdmi_d[11]}]
set_property PACKAGE_PIN J19 [get_ports {hdmi_d[12]}]
set_property PACKAGE_PIN H19 [get_ports {hdmi_d[13]}]
set_property PACKAGE_PIN L17 [get_ports {hdmi_d[14]}]
set_property PACKAGE_PIN L18 [get_ports {hdmi_d[15]}]

set_property IOSTANDARD LVCMOS25 [get_ports {hdmi_d[*]}]

# HDMI Control Signals
set_property PACKAGE_PIN H17 [get_ports hdmi_de]
set_property PACKAGE_PIN K18 [get_ports hdmi_clk]
set_property PACKAGE_PIN H20 [get_ports hdmi_vsync]
set_property PACKAGE_PIN J18 [get_ports hdmi_hsync]

set_property IOSTANDARD LVCMOS25 [get_ports hdmi_de]
set_property IOSTANDARD LVCMOS25 [get_ports hdmi_clk]
set_property IOSTANDARD LVCMOS25 [get_ports hdmi_vsync]
set_property IOSTANDARD LVCMOS25 [get_ports hdmi_hsync]

# HDMI clock output drive strength
set_property SLEW FAST [get_ports hdmi_clk]
set_property DRIVE 8 [get_ports hdmi_clk]

# ==============================================================================
# I2C Bus (for ADV7511 Configuration via PCA9548 Mux)
# ==============================================================================
set_property PACKAGE_PIN K21 [get_ports i2c_scl]
set_property PACKAGE_PIN L21 [get_ports i2c_sda]

set_property IOSTANDARD LVCMOS25 [get_ports i2c_scl]
set_property IOSTANDARD LVCMOS25 [get_ports i2c_sda]

set_property PULLUP true [get_ports i2c_scl]
set_property PULLUP true [get_ports i2c_sda]

# I2C Mux Reset (IIC_MUX_RESET_B) - active low
set_property PACKAGE_PIN P23 [get_ports i2c_mux_reset_n]
set_property IOSTANDARD LVCMOS25 [get_ports i2c_mux_reset_n]

# I2C is slow - relax timing
set_false_path -to [get_ports i2c_scl]
set_false_path -to [get_ports i2c_sda]
set_false_path -from [get_ports i2c_scl]
set_false_path -from [get_ports i2c_sda]
set_false_path -to [get_ports i2c_mux_reset_n]

# ==============================================================================
# Clock Domain Crossings
# ==============================================================================
# The design has multiple clock domains:
# - ui_clk from MIG (~100 MHz) for DDR3 interface
# - clk_50mhz for I2C and system logic
# - clk_25mhz for video pixel clock

# False paths for async CDC signals (handled by sync registers in RTL)
# Frame/line start signals from video to DDR domain
set_false_path -from [get_clocks -of_objects [get_pins u_video_clk/mmcm_inst/CLKOUT0]] \
               -to [get_clocks -of_objects [get_pins u_mig/u_mig_7series_0_mig/u_ddr3_infrastructure/gen_mmcm.mmcm_i/CLKFBOUT]]

set_false_path -from [get_clocks -of_objects [get_pins u_mig/u_mig_7series_0_mig/u_ddr3_infrastructure/gen_mmcm.mmcm_i/CLKFBOUT]] \
               -to [get_clocks -of_objects [get_pins u_video_clk/mmcm_inst/CLKOUT0]]

# ==============================================================================
# BITSTREAM Configuration
# ==============================================================================
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 2.5 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
