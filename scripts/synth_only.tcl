#------------------------------------------------------------------------------
# synth_only.tcl
# Run synthesis only (no implementation)
#------------------------------------------------------------------------------

set script_dir [file dirname [info script]]
set project_root [file normalize "$script_dir/.."]

set project_name "celery3d"
set part "xc7k325tffg900-2"
set top_module "celery3d_top"
set output_dir "$project_root/output"
set project_dir "$output_dir/vivado_project"

file mkdir $output_dir

# Create project
create_project $project_name $project_dir -part $part -force

# Add sources
set rtl_files [glob -nocomplain "$project_root/rtl/*/*.sv"]
foreach f $rtl_files {
    add_files -fileset sources_1 $f
}
set_property file_type SystemVerilog [get_files *.sv]

# Add constraints
add_files -fileset constrs_1 "$project_root/constraints/kc705_hdmi.xdc"

# Set top
set_property top $top_module [current_fileset]
update_compile_order -fileset sources_1

# Run synthesis
puts "Running synthesis..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Report
open_run synth_1
report_utilization -file "$output_dir/synth_utilization.rpt"
report_timing_summary -file "$output_dir/synth_timing.rpt"

puts ""
puts "Synthesis complete!"
puts "Reports saved to: $output_dir/"

exit 0
