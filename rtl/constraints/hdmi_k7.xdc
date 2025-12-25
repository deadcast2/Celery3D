# Celery3D GPU - HDMI Video Output Constraints for KC705
# Target: Xilinx Kintex-7 XC7K325T-2FFG900C (KC705 Evaluation Board)
# Top module: hdmi_synth_top

# ==============================================================================
# 200 MHz Differential System Clock (Bank 33 - HP, LVDS)
# ==============================================================================
# KC705 onboard 200 MHz oscillator
set_property PACKAGE_PIN AD12 [get_ports sys_clk_p]
set_property PACKAGE_PIN AD11 [get_ports sys_clk_n]
set_property IOSTANDARD LVDS [get_ports sys_clk_p]
set_property IOSTANDARD LVDS [get_ports sys_clk_n]

create_clock -period 5.000 -name sys_clk [get_ports sys_clk_p]

# ==============================================================================
# Reset - Using internal reset from MMCM lock (no external reset needed)
# ==============================================================================
# (Matches working board test approach - no external reset dependency)

# ==============================================================================
# HDMI Output (ADV7511 HDMI Transmitter) - Bank 12/13 (HR, 2.5V)
# ==============================================================================
# From KC705 UG810 Table 1-21: FPGA to HDMI Codec Connections
# All HDMI signals are in HR banks supporting LVCMOS25

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
# KC705 uses a PCA9548 I2C mux at address 0x74
# ADV7511 is on mux channel 5, I2C address 0x39 (0b0111001)
# Pin assignments per official KC705 XDC:
#   IIC_SCL_MAIN = K21
#   IIC_SDA_MAIN = L21
set_property PACKAGE_PIN K21 [get_ports i2c_scl]
set_property PACKAGE_PIN L21 [get_ports i2c_sda]

set_property IOSTANDARD LVCMOS25 [get_ports i2c_scl]
set_property IOSTANDARD LVCMOS25 [get_ports i2c_sda]

set_property PULLUP true [get_ports i2c_scl]
set_property PULLUP true [get_ports i2c_sda]

# I2C Mux Reset (IIC_MUX_RESET_B) - active low
# Must be driven HIGH to enable the I2C mux!
set_property PACKAGE_PIN P23 [get_ports i2c_mux_reset_n]
set_property IOSTANDARD LVCMOS25 [get_ports i2c_mux_reset_n]

# I2C is slow (100 kHz) - relax timing
set_false_path -to [get_ports i2c_scl]
set_false_path -to [get_ports i2c_sda]
set_false_path -from [get_ports i2c_scl]
set_false_path -from [get_ports i2c_sda]
set_false_path -to [get_ports i2c_mux_reset_n]

# ==============================================================================
# Control Inputs - GPIO DIP Switches (directly on board)
# ==============================================================================
# GPIO_DIP_SW0-SW3 on Bank 33 (HP, 1.5V)
set_property PACKAGE_PIN Y29 [get_ports {pattern_sel[0]}]
set_property PACKAGE_PIN W29 [get_ports {pattern_sel[1]}]
set_property PACKAGE_PIN AA28 [get_ports use_framebuffer]

set_property IOSTANDARD LVCMOS25 [get_ports {pattern_sel[*]}]
set_property IOSTANDARD LVCMOS25 [get_ports use_framebuffer]

# Relax timing on control inputs
set_false_path -from [get_ports {pattern_sel[*]}]
set_false_path -from [get_ports use_framebuffer]

# ==============================================================================
# Status LEDs - GPIO_LED (Active-High from FPGA)
# LEDs 0-3 are in Bank 33 (LVCMOS15), LEDs 4-7 are in different banks (LVCMOS25)
# ==============================================================================
# LED 0 (DS27) - HDMI init done
set_property PACKAGE_PIN AB8 [get_ports hdmi_init_done]
set_property IOSTANDARD LVCMOS15 [get_ports hdmi_init_done]

# LED 1 (DS26) - HDMI init error
set_property PACKAGE_PIN AA8 [get_ports hdmi_init_error]
set_property IOSTANDARD LVCMOS15 [get_ports hdmi_init_error]

# LED 2 (DS25) - Pixel clock locked
set_property PACKAGE_PIN AC9 [get_ports pixel_clk_locked]
set_property IOSTANDARD LVCMOS15 [get_ports pixel_clk_locked]

# LED 3 (DS3) - Heartbeat (blinks ~1Hz)
set_property PACKAGE_PIN AB9 [get_ports heartbeat]
set_property IOSTANDARD LVCMOS15 [get_ports heartbeat]

# LED 4 (DS10) - Alive (always on when running)
set_property PACKAGE_PIN AE26 [get_ports alive]
set_property IOSTANDARD LVCMOS25 [get_ports alive]

# ==============================================================================
# Bitstream Configuration (match KC705 board test settings)
# ==============================================================================
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 2.5 [current_design]
