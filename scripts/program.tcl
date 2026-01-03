#------------------------------------------------------------------------------
# program.tcl
# Vivado programming script for Celery3D
# Usage: vivado -mode batch -source scripts/program.tcl
#------------------------------------------------------------------------------

# Get project root directory
set script_dir [file dirname [info script]]
set project_root [file normalize "$script_dir/.."]

# Bitstream location
set bitstream "$project_root/output/celery3d.bit"

# Check if bitstream exists
if {![file exists $bitstream]} {
    puts "ERROR: Bitstream not found: $bitstream"
    puts "Run 'make build' first to generate the bitstream."
    exit 1
}

puts "Programming KC705 with: $bitstream"

#------------------------------------------------------------------------------
# Open hardware manager
#------------------------------------------------------------------------------
open_hw_manager

#------------------------------------------------------------------------------
# Connect to hardware server
#------------------------------------------------------------------------------
puts "Connecting to hardware server..."
connect_hw_server -allow_non_jtag

# Get available targets
set targets [get_hw_targets]
if {[llength $targets] == 0} {
    puts "ERROR: No hardware targets found!"
    puts "Make sure the KC705 is connected and powered on."
    close_hw_manager
    exit 1
}

puts "Found targets: $targets"

# Open first target (usually the KC705)
open_hw_target [lindex $targets 0]

#------------------------------------------------------------------------------
# Get the FPGA device
#------------------------------------------------------------------------------
set devices [get_hw_devices]
if {[llength $devices] == 0} {
    puts "ERROR: No FPGA devices found!"
    close_hw_target
    close_hw_manager
    exit 1
}

puts "Found devices: $devices"

# Find the Kintex-7 device
set fpga ""
foreach dev $devices {
    set part [get_property PART $dev]
    if {[string match "xc7k*" $part]} {
        set fpga $dev
        break
    }
}

if {$fpga == ""} {
    puts "ERROR: Kintex-7 FPGA not found!"
    puts "Available devices: $devices"
    close_hw_target
    close_hw_manager
    exit 1
}

puts "Using FPGA: $fpga"
current_hw_device $fpga

#------------------------------------------------------------------------------
# Program the FPGA
#------------------------------------------------------------------------------
puts "Programming FPGA..."

# Set the bitstream file
set_property PROGRAM.FILE $bitstream $fpga

# Program the device
program_hw_devices $fpga

puts ""
puts "=============================================="
puts "Programming complete!"
puts "=============================================="
puts ""
puts "Check the KC705 LEDs:"
puts "  LED[0] = MMCM locked (should be ON)"
puts "  LED[1] = ADV7511 init done (should be ON after ~200ms)"
puts "  LED[2] = ADV7511 init error (should be OFF)"
puts "  LED[3] = VSYNC (should blink at 60Hz)"
puts ""
puts "Connect an HDMI monitor to see the test pattern."
puts "Use DIP switches to change patterns (0-7)."
puts ""

#------------------------------------------------------------------------------
# Cleanup
#------------------------------------------------------------------------------
close_hw_target
close_hw_manager

exit 0
