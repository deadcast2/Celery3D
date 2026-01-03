#------------------------------------------------------------------------------
# open_hwmgr.tcl
# Open hardware manager for interactive programming/debugging
#------------------------------------------------------------------------------

set script_dir [file dirname [info script]]
set project_root [file normalize "$script_dir/.."]

# Open hardware manager
open_hw_manager

# Try to connect to hardware server
puts "Attempting to connect to hardware server..."
if {[catch {connect_hw_server -allow_non_jtag} err]} {
    puts "Note: Could not auto-connect to hardware server."
    puts "Use Flow -> Open Target -> Auto Connect in the GUI."
}

puts ""
puts "Hardware Manager is ready."
puts ""
puts "To program the FPGA:"
puts "  1. Right-click on the device"
puts "  2. Select 'Program Device'"
puts "  3. Browse to: $project_root/output/celery3d.bit"
puts ""
