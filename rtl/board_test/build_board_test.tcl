# KC705 Board Test - Vivado Build Script
# Synthesizes, implements, and generates bitstream for LED test

# Configuration
set project_name "kc705_board_test"
set part "xc7k325tffg900-2"
set top_module "kc705_board_test"

# Get script directory
set script_dir [file dirname [info script]]
set build_dir "${script_dir}/build"

# Create build directory
file mkdir $build_dir

# Create in-memory project
create_project -in_memory -part $part

# Add source files
read_verilog -sv "${script_dir}/kc705_board_test.sv"
read_xdc "${script_dir}/kc705_board_test.xdc"

# Run synthesis
puts "=========================================="
puts "Running Synthesis..."
puts "=========================================="
synth_design -top $top_module -part $part

# Generate post-synthesis reports
report_utilization -file "${build_dir}/post_synth_utilization.rpt"
report_timing_summary -file "${build_dir}/post_synth_timing.rpt"

# Optimize design
puts "=========================================="
puts "Running Optimization..."
puts "=========================================="
opt_design

# Place design
puts "=========================================="
puts "Running Placement..."
puts "=========================================="
place_design

# Route design
puts "=========================================="
puts "Running Routing..."
puts "=========================================="
route_design

# Generate post-implementation reports
report_utilization -file "${build_dir}/post_route_utilization.rpt"
report_timing_summary -file "${build_dir}/post_route_timing.rpt"
report_drc -file "${build_dir}/post_route_drc.rpt"

# Write checkpoint
write_checkpoint -force "${build_dir}/${project_name}.dcp"

# Generate bitstream
puts "=========================================="
puts "Generating Bitstream..."
puts "=========================================="
write_bitstream -force "${build_dir}/${project_name}.bit"

puts "=========================================="
puts "Build Complete!"
puts "Bitstream: ${build_dir}/${project_name}.bit"
puts "=========================================="

# Print summary
puts "\nResource Utilization Summary:"
report_utilization -hierarchical -hierarchical_depth 1

puts "\nTiming Summary:"
report_timing_summary -max_paths 5
