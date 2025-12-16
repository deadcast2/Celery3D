# Celery3D GPU - Timing Constraints for KC705 Evaluation Board
# Target: Xilinx Kintex-7 XC7K325T-2FFG900C

# ==============================================================================
# Input Clock - 50 MHz single-ended oscillator
# ==============================================================================
# TODO: Update pin location from board schematic
# The 50 MHz oscillator is typically on a dedicated clock-capable pin
create_clock -period 20.000 -name clk_50mhz [get_ports clk_50mhz_in]

# ==============================================================================
# GPU Core Clock - Target 50 MHz (20ns period)
# ==============================================================================
# Matches original Voodoo 1 clock speed and board's 50 MHz oscillator
create_clock -period 20.000 -name clk_gpu [get_ports clk]

# Clock uncertainty for setup/hold analysis
set_clock_uncertainty -setup 0.500 [get_clocks clk_gpu]
set_clock_uncertainty -hold 0.100 [get_clocks clk_gpu]

# ==============================================================================
# Timing Exceptions
# ==============================================================================
# Reset is async, treat as false path for timing
set_false_path -from [get_ports rst_n]

# ==============================================================================
# Input/Output Delays (placeholder values)
# ==============================================================================
# These will be refined based on actual board routing and connected peripherals

# Vertex input interface - assume synchronous to clk_gpu
set_input_delay -clock clk_gpu -max 2.0 [get_ports {v0_* v1_* v2_*}]
set_input_delay -clock clk_gpu -min 0.5 [get_ports {v0_* v1_* v2_*}]
set_input_delay -clock clk_gpu -max 2.0 [get_ports tri_valid]
set_input_delay -clock clk_gpu -min 0.5 [get_ports tri_valid]

# Fragment output interface
set_output_delay -clock clk_gpu -max 2.0 [get_ports {frag_out_*}]
set_output_delay -clock clk_gpu -min 0.5 [get_ports {frag_out_*}]
set_output_delay -clock clk_gpu -max 2.0 [get_ports frag_valid]
set_output_delay -clock clk_gpu -min 0.5 [get_ports frag_valid]

# Ready/busy signals
set_output_delay -clock clk_gpu -max 2.0 [get_ports tri_ready]
set_output_delay -clock clk_gpu -min 0.5 [get_ports tri_ready]
set_output_delay -clock clk_gpu -max 2.0 [get_ports busy]
set_output_delay -clock clk_gpu -min 0.5 [get_ports busy]

set_input_delay -clock clk_gpu -max 2.0 [get_ports frag_ready]
set_input_delay -clock clk_gpu -min 0.5 [get_ports frag_ready]

# ==============================================================================
# Physical Constraints (Placeholder - update from board schematic)
# ==============================================================================
# Pin assignments will be added once schematic is available
# For now, run synthesis-only to check timing on internal paths

# Example pin format (commented out until we have actual pinout):
# set_property PACKAGE_PIN <pin> [get_ports clk_50mhz_in]
# set_property IOSTANDARD LVCMOS33 [get_ports clk_50mhz_in]

# ==============================================================================
# Synthesis Directives
# ==============================================================================
# Allow Vivado to optimize DSP inference for fixed-point multiplications
set_property DSP_STYLE block [get_cells -hierarchical -filter {PRIMITIVE_TYPE =~ DSP.*}] -quiet

# Target device
# set_property PART xc7k325t-2ffg676i [current_project]
