# Celery3D GPU - HDMI Video Output Synthesis Script (Non-Project Mode)
# Target: Xilinx Kintex-7 XC7K325T-2FFG900C (KC705 Evaluation Board)
# Usage: vivado -mode batch -source scripts/synth_hdmi.tcl

puts "=============================================="
puts "Celery3D GPU - HDMI Video Output Synthesis"
puts "=============================================="

# Set part and output directory
set part xc7k325tffg900-2
set output_dir ./build_hdmi
set top_module hdmi_synth_top

# Create output directory
file mkdir $output_dir

# Read RTL sources
puts "Reading RTL sources..."
read_verilog -sv {
    core/celery_pkg.sv
    video/video_pkg.sv
    video/clk_gen_kc705.sv
    video/video_timing_gen.sv
    video/test_pattern_gen.sv
    video/rgb_to_ycbcr.sv
    video/i2c_master.sv
    video/adv7511_init.sv
    video/hdmi_top.sv
    video/hdmi_synth_top.sv
}

# Read constraints (HDMI-specific)
puts "Reading constraints..."
read_xdc constraints/hdmi_k7.xdc

# Set synthesis defines
set_property verilog_define SYNTHESIS [current_fileset]

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
report_clock_networks -file $output_dir/post_synth_clocks.rpt

# Print quick summary
puts ""
puts "=============================================="
puts "Synthesis Complete - Quick Summary"
puts "=============================================="
report_utilization -hierarchical -hierarchical_depth 2

puts ""
puts "Clock Summary:"
report_clocks

puts ""
puts "Timing Summary (post-synthesis):"
report_timing_summary -no_detailed_paths

# ===============================================================================
# Place and Route
# ===============================================================================
puts ""
puts "=============================================="
puts "Running Place & Route..."
puts "=============================================="

# Optimize design
opt_design

# Place design
place_design

# Write checkpoint after placement
write_checkpoint -force $output_dir/post_place.dcp

# Route design
route_design

# Write checkpoint after routing
write_checkpoint -force $output_dir/post_route.dcp

# Generate post-route reports
puts "Generating post-route reports..."
report_timing_summary -file $output_dir/post_route_timing_summary.rpt
report_timing -sort_by group -max_paths 10 -path_type summary -file $output_dir/post_route_timing.rpt
report_utilization -file $output_dir/post_route_utilization.rpt
report_drc -file $output_dir/post_route_drc.rpt
report_power -file $output_dir/post_route_power.rpt

# ===============================================================================
# Generate Bitstream
# ===============================================================================
puts ""
puts "=============================================="
puts "Generating Bitstream..."
puts "=============================================="

write_bitstream -force $output_dir/hdmi_test.bit

# ===============================================================================
# Final Summary
# ===============================================================================
puts ""
puts "=============================================="
puts "Build Complete - Final Summary"
puts "=============================================="

report_utilization

puts ""
puts "Final Timing Summary:"
report_timing_summary

puts ""
puts "=============================================="
puts "Output Files:"
puts "=============================================="
puts "  Bitstream:    $output_dir/hdmi_test.bit"
puts "  Checkpoints:  $output_dir/post_synth.dcp"
puts "                $output_dir/post_place.dcp"
puts "                $output_dir/post_route.dcp"
puts ""
puts "Reports written to: $output_dir/"
puts "  - post_synth_timing_summary.rpt"
puts "  - post_synth_utilization.rpt"
puts "  - post_route_timing_summary.rpt"
puts "  - post_route_utilization.rpt"
puts "  - post_route_power.rpt"
puts "=============================================="
