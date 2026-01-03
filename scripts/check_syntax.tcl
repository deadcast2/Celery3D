#------------------------------------------------------------------------------
# check_syntax.tcl
# Quick RTL syntax check without full synthesis
#------------------------------------------------------------------------------

set script_dir [file dirname [info script]]
set project_root [file normalize "$script_dir/.."]

set part "xc7k325tffg900-2"
set top_module "celery3d_top"

# Create in-memory project
create_project -in_memory -part $part

# Add sources
set rtl_files [glob -nocomplain "$project_root/rtl/*/*.sv"]
foreach f $rtl_files {
    puts "Checking: $f"
    read_verilog -sv $f
}

# Add constraints
read_xdc "$project_root/constraints/kc705_hdmi.xdc"

# Set top module
set_property top $top_module [current_fileset]

# Run elaboration (catches most syntax/connection errors)
puts ""
puts "Running elaboration..."
synth_design -top $top_module -part $part -rtl

puts ""
puts "=============================================="
puts "Syntax check passed!"
puts "=============================================="

exit 0
