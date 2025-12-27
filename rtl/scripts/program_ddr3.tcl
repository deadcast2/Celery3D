# Celery3D - Program DDR3 Test Bitstream to KC705
# Usage: vivado -mode batch -source scripts/program_ddr3.tcl

puts "=============================================="
puts "Programming KC705 with DDR3 test bitstream"
puts "=============================================="

set bitstream_file "build_ddr3/ddr3_test.bit"

if {![file exists $bitstream_file]} {
    puts "ERROR: Bitstream not found: $bitstream_file"
    puts "Run 'make synth-ddr3' first to build the bitstream."
    exit 1
}

open_hw_manager
connect_hw_server

# Find and open hardware target
set targets [get_hw_targets]
if {[llength $targets] == 0} {
    puts "ERROR: No hardware targets found!"
    puts "Check that KC705 is connected via JTAG."
    disconnect_hw_server
    close_hw_manager
    exit 1
}

open_hw_target [lindex $targets 0]

# Get the device
set devices [get_hw_devices]
if {[llength $devices] == 0} {
    puts "ERROR: No devices found on target!"
    close_hw_target
    disconnect_hw_server
    close_hw_manager
    exit 1
}

current_hw_device [lindex $devices 0]
puts "Device: [get_property NAME [current_hw_device]]"

# Program the bitstream
puts ""
puts "Programming device with: $bitstream_file"
set_property PROGRAM.FILE $bitstream_file [current_hw_device]
program_hw_devices [current_hw_device]

puts ""
puts "=============================================="
puts "Programming complete!"
puts "=============================================="
puts ""
puts "LED indicators:"
puts "  LED[0] = MMCM locked"
puts "  LED[1] = DDR3 calibration complete"
puts "  LED[2] = Heartbeat (blinks during test)"
puts "  LED[3] = Test in progress"
puts "  LED[4-5] = Progress counter"
puts "  LED[6] = PASS (solid = success)"
puts "  LED[7] = FAIL (solid = error)"
puts ""
puts "Expected sequence:"
puts "  1. LED[0] lights immediately (MMCM lock)"
puts "  2. LED[1] lights after ~1-2s (calibration)"
puts "  3. LEDs[2-5] animate during test"
puts "  4. LED[6] stays on if all tests pass"
puts "=============================================="

close_hw_target
disconnect_hw_server
close_hw_manager
