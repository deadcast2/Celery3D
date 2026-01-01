# Celery3D GPU - Full GPU with DDR3 Framebuffer Build Script
# Target: Xilinx Kintex-7 XC7K325T-2FFG900C (KC705 Evaluation Board)
# Usage: vivado -mode batch -source scripts/synth_gpu_ddr3.tcl
#
# This builds the full GPU design:
# - UART command interface for triangle submission
# - Full rasterizer pipeline
# - DDR3 framebuffer via pixel_write_master
# - HDMI output via ADV7511

puts "=============================================="
puts "Celery3D - Full GPU + DDR3 Build"
puts "=============================================="

# Configuration
set part xc7k325tffg900-2
set output_dir ./build_gpu_ddr3
set top_module gpu_ddr3_top
set project_name gpu_ddr3

# Path to the MIG IP project
set mig_project_dir ./vivado/ddr3

# Create output directory
file mkdir $output_dir

# ===============================================================================
# Create Project
# ===============================================================================
puts "Creating Vivado project..."
create_project -force $project_name $output_dir -part $part

# Set project properties
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

# ===============================================================================
# Add MIG IP
# ===============================================================================
puts "Adding MIG IP..."

# Set the IP repository to include the generated MIG IP
set_property ip_repo_paths [list $mig_project_dir/ddr3.srcs/sources_1/ip] [current_project]
update_ip_catalog

# Add the MIG IP XCI file
set mig_xci "$mig_project_dir/ddr3.srcs/sources_1/ip/mig_7series_0/mig_7series_0.xci"
if {[file exists $mig_xci]} {
    add_files -norecurse $mig_xci
    # Generate output products if needed
    set mig_ip [get_ips mig_7series_0]
    if {$mig_ip ne ""} {
        generate_target all $mig_ip
    }
} else {
    puts "ERROR: MIG IP not found at $mig_xci"
    puts "Please generate the MIG IP first in Vivado"
    exit 1
}

# ===============================================================================
# Add RTL Sources
# ===============================================================================
puts "Adding RTL sources..."
add_files -norecurse {
    core/celery_pkg.sv
    core/edge_eval.sv
    core/triangle_setup.sv
    core/rasterizer.sv
    core/perspective_correct.sv
    core/texture_unit.sv
    core/depth_buffer.sv
    core/alpha_blend.sv
    core/framebuffer.sv
    core/rasterizer_top.sv
    uart/uart_rx.sv
    uart/cmd_parser.sv
    video/video_pkg.sv
    video/video_clk_from_mig.sv
    video/video_timing_gen.sv
    video/rgb_to_ycbcr.sv
    video/i2c_master.sv
    video/adv7511_init.sv
    video/ddr3_fb_line_buffer.sv
    video/pixel_fifo.sv
    video/pixel_write_master.sv
    video/gpu_ddr3_top.sv
}

# Set top module
set_property top $top_module [current_fileset]

# Set synthesis define
set_property verilog_define SYNTHESIS [current_fileset]

# ===============================================================================
# Add Constraints
# ===============================================================================
puts "Adding constraints..."

# Use the DDR3 FB test constraints as a base (same pinouts)
add_files -fileset constrs_1 -norecurse constraints/gpu_ddr3.xdc

# ===============================================================================
# Run Synthesis
# ===============================================================================
puts ""
puts "=============================================="
puts "Running Synthesis..."
puts "=============================================="

# Reset run if exists
reset_run synth_1 -quiet

# Launch synthesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Check if synthesis succeeded
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed!"
    exit 1
}

# Open synthesized design for reports
open_run synth_1

# Generate synthesis reports
puts "Generating synthesis reports..."
report_timing_summary -file $output_dir/post_synth_timing_summary.rpt
report_utilization -file $output_dir/post_synth_utilization.rpt
report_utilization -hierarchical -file $output_dir/post_synth_utilization_hier.rpt
report_drc -file $output_dir/post_synth_drc.rpt

puts ""
puts "Synthesis Utilization Summary:"
report_utilization

puts ""
puts "Synthesis Timing Summary:"
report_timing_summary -no_detailed_paths

# ===============================================================================
# Run Implementation
# ===============================================================================
puts ""
puts "=============================================="
puts "Running Implementation..."
puts "=============================================="

# Reset and launch implementation
reset_run impl_1 -quiet
launch_runs impl_1 -jobs 4
wait_on_run impl_1

# Check if implementation succeeded
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed!"
    exit 1
}

# Open implemented design for reports
open_run impl_1

# Generate implementation reports
puts "Generating implementation reports..."
report_timing_summary -file $output_dir/post_route_timing_summary.rpt
report_timing -sort_by group -max_paths 20 -path_type summary -file $output_dir/post_route_timing.rpt
report_utilization -file $output_dir/post_route_utilization.rpt
report_drc -file $output_dir/post_route_drc.rpt
report_power -file $output_dir/post_route_power.rpt
report_io -file $output_dir/post_route_io.rpt

puts ""
puts "Implementation Timing Summary:"
report_timing_summary

# ===============================================================================
# Generate Bitstream
# ===============================================================================
puts ""
puts "=============================================="
puts "Generating Bitstream..."
puts "=============================================="

# Launch bitstream generation
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# Copy bitstream to output directory
set bitstream_src "$output_dir/$project_name.runs/impl_1/${top_module}.bit"
set bitstream_dst "$output_dir/gpu_ddr3.bit"
if {[file exists $bitstream_src]} {
    file copy -force $bitstream_src $bitstream_dst
    puts "Bitstream copied to: $bitstream_dst"
} else {
    puts "WARNING: Bitstream not found at expected location"
    puts "Looking for bitstream..."
    set bitfiles [glob -nocomplain $output_dir/$project_name.runs/impl_1/*.bit]
    if {[llength $bitfiles] > 0} {
        file copy -force [lindex $bitfiles 0] $bitstream_dst
        puts "Bitstream copied to: $bitstream_dst"
    }
}

# ===============================================================================
# Final Summary
# ===============================================================================
puts ""
puts "=============================================="
puts "Build Complete!"
puts "=============================================="

report_utilization

puts ""
puts "Final Timing:"
set wns [get_property STATS.WNS [get_runs impl_1]]
set tns [get_property STATS.TNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
puts "  WNS (Worst Negative Slack): $wns ns"
puts "  TNS (Total Negative Slack): $tns ns"
puts "  WHS (Worst Hold Slack):     $whs ns"

if {$wns >= 0 && $whs >= 0} {
    puts ""
    puts "  TIMING MET!"
} else {
    puts ""
    puts "  WARNING: Timing not met!"
}

puts ""
puts "=============================================="
puts "Output Files:"
puts "=============================================="
puts "  Bitstream: $output_dir/gpu_ddr3.bit"
puts "  Project:   $output_dir/$project_name.xpr"
puts ""
puts "Reports in: $output_dir/"
puts "  - post_synth_timing_summary.rpt"
puts "  - post_synth_utilization.rpt"
puts "  - post_route_timing_summary.rpt"
puts "  - post_route_utilization.rpt"
puts "  - post_route_power.rpt"
puts "=============================================="
puts ""
puts "To program: make program-gpu-ddr3"
puts "=============================================="

close_project
