#------------------------------------------------------------------------------
# build.tcl
# Vivado build script for Celery3D Phase 1
# Usage: vivado -mode batch -source scripts/build.tcl
#------------------------------------------------------------------------------

# Get project root directory (one level up from scripts/)
set script_dir [file dirname [info script]]
set project_root [file normalize "$script_dir/.."]

# Project settings
set project_name "celery3d"
set part "xc7k325tffg900-2"
set top_module "celery3d_top"

# Output directory
set output_dir "$project_root/output"
set project_dir "$output_dir/vivado_project"

# Create output directory
file mkdir $output_dir

#------------------------------------------------------------------------------
# Create project
#------------------------------------------------------------------------------
puts "Creating project..."
create_project $project_name $project_dir -part $part -force

# Set project properties
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

#------------------------------------------------------------------------------
# Add source files
#------------------------------------------------------------------------------
puts "Adding source files..."

# RTL sources
set rtl_files [list \
    "$project_root/rtl/clocking/clock_gen.sv" \
    "$project_root/rtl/i2c/i2c_master.sv" \
    "$project_root/rtl/init/adv7511_init.sv" \
    "$project_root/rtl/video/video_timing_gen.sv" \
    "$project_root/rtl/video/test_pattern_gen.sv" \
    "$project_root/rtl/video/rgb565_to_ycbcr.sv" \
    "$project_root/rtl/video/hdmi_output.sv" \
    "$project_root/rtl/top/celery3d_top.sv" \
]

foreach f $rtl_files {
    if {[file exists $f]} {
        add_files -fileset sources_1 $f
        puts "  Added: $f"
    } else {
        puts "  WARNING: File not found: $f"
    }
}

# Set all files as SystemVerilog
set_property file_type SystemVerilog [get_files *.sv]

# Constraints
set xdc_file "$project_root/constraints/kc705_hdmi.xdc"
if {[file exists $xdc_file]} {
    add_files -fileset constrs_1 $xdc_file
    puts "  Added constraints: $xdc_file"
} else {
    puts "  WARNING: Constraints file not found: $xdc_file"
}

#------------------------------------------------------------------------------
# Set top module
#------------------------------------------------------------------------------
set_property top $top_module [current_fileset]
update_compile_order -fileset sources_1

#------------------------------------------------------------------------------
# Synthesis
#------------------------------------------------------------------------------
puts "Running synthesis..."
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING on [get_runs synth_1]

launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Check synthesis status
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed!"
    exit 1
}

set synth_status [get_property STATUS [get_runs synth_1]]
puts "Synthesis status: $synth_status"

#------------------------------------------------------------------------------
# Implementation
#------------------------------------------------------------------------------
puts "Running implementation..."

# Set implementation strategies
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]

launch_runs impl_1 -jobs 4
wait_on_run impl_1

# Check implementation status
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed!"
    exit 1
}

set impl_status [get_property STATUS [get_runs impl_1]]
puts "Implementation status: $impl_status"

#------------------------------------------------------------------------------
# Generate bitstream
#------------------------------------------------------------------------------
puts "Generating bitstream..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

#------------------------------------------------------------------------------
# Generate reports
#------------------------------------------------------------------------------
puts "Generating reports..."
open_run impl_1

# Timing report
report_timing_summary -file "$output_dir/timing_summary.rpt" -max_paths 10

# Utilization report
report_utilization -file "$output_dir/utilization.rpt"

# Power report
report_power -file "$output_dir/power.rpt"

# IO report
report_io -file "$output_dir/io.rpt"

#------------------------------------------------------------------------------
# Copy bitstream to output directory
#------------------------------------------------------------------------------
set bitstream_src "$project_dir/${project_name}.runs/impl_1/${top_module}.bit"
set bitstream_dst "$output_dir/${project_name}.bit"

if {[file exists $bitstream_src]} {
    file copy -force $bitstream_src $bitstream_dst
    puts "Bitstream copied to: $bitstream_dst"
} else {
    puts "WARNING: Bitstream not found at: $bitstream_src"
}

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
puts ""
puts "=============================================="
puts "Build complete!"
puts "=============================================="
puts "Bitstream: $bitstream_dst"
puts "Reports:   $output_dir/*.rpt"
puts ""

# Print timing summary
set wns [get_property STATS.WNS [get_runs impl_1]]
set tns [get_property STATS.TNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
set ths [get_property STATS.THS [get_runs impl_1]]

puts "Timing Summary:"
puts "  WNS (Worst Negative Slack): $wns ns"
puts "  TNS (Total Negative Slack): $tns ns"
puts "  WHS (Worst Hold Slack):     $whs ns"
puts "  THS (Total Hold Slack):     $ths ns"

if {$wns < 0 || $whs < 0} {
    puts ""
    puts "WARNING: Timing not met!"
}

puts ""
exit 0
