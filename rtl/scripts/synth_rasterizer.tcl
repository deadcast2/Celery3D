# Celery3D GPU - Vivado Synthesis Script (Non-Project Mode)
# Target: Xilinx Kintex-7 XC7K325T-2FFG676I
# Usage: vivado -mode batch -source scripts/synth_rasterizer.tcl

puts "=============================================="
puts "Celery3D GPU - Rasterizer Synthesis"
puts "=============================================="

# Set part and output directory
set part xc7k325tffg676-2
set output_dir ./build
set top_module rasterizer_top

# Create output directory
file mkdir $output_dir

# Read RTL sources
puts "Reading RTL sources..."
read_verilog -sv {
    core/celery_pkg.sv
    core/edge_eval.sv
    core/triangle_setup.sv
    core/rasterizer.sv
    core/rasterizer_top.sv
}

# Read constraints
puts "Reading constraints..."
read_xdc constraints/celery_k7.xdc

# Run synthesis
puts "Running synthesis..."
synth_design -top $top_module -part $part -flatten_hierarchy rebuilt

# Write checkpoint after synthesis
write_checkpoint -force $output_dir/post_synth.dcp

# Generate synthesis reports
puts "Generating synthesis reports..."
report_timing_summary -file $output_dir/post_synth_timing_summary.rpt
report_timing -sort_by group -max_paths 10 -path_type summary -file $output_dir/post_synth_timing.rpt
report_utilization -file $output_dir/post_synth_utilization.rpt
report_drc -file $output_dir/post_synth_drc.rpt

# Print quick summary
puts ""
puts "=============================================="
puts "Synthesis Complete - Quick Summary"
puts "=============================================="
report_utilization -hierarchical -hierarchical_depth 2

puts ""
puts "Timing Summary:"
report_timing_summary -no_detailed_paths

puts ""
puts "Reports written to: $output_dir/"
puts "  - post_synth_timing_summary.rpt"
puts "  - post_synth_timing.rpt"
puts "  - post_synth_utilization.rpt"
puts "  - post_synth_drc.rpt"

# Note: Place & route is skipped for submodule synthesis
# The rasterizer_top has struct interfaces that exceed available I/Os
# In the full GPU design, these connect internally to other modules
#
# To run full implementation, create a top-level wrapper with:
# - Actual pin mappings for clk, rst_n
# - Internal connections to command processor, framebuffer, etc.

# Final timing summary (post-synthesis estimates)
puts ""
puts "=============================================="
puts "Synthesis Complete - Timing Estimates"
puts "=============================================="
puts "(Note: Post-synthesis timing - actual timing may vary after place & route)"
report_timing_summary

puts ""
puts "All reports written to: $output_dir/"
puts "=============================================="
