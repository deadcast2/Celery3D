# KC705 Board Programming Script
# Programs the FPGA with the LED test bitstream

set script_dir [file dirname [info script]]
set bitstream "${script_dir}/build/kc705_board_test.bit"

# Open hardware manager
open_hw_manager

# Connect to hardware server
connect_hw_server -allow_non_jtag

# Open target (auto-detect)
open_hw_target

# Get the first device (KC705)
set device [lindex [get_hw_devices] 0]
current_hw_device $device

# Set the bitstream file
set_property PROGRAM.FILE $bitstream $device

# Program the device
puts "Programming device with: $bitstream"
program_hw_devices $device

puts "Programming complete!"

# Close connection
close_hw_target
disconnect_hw_server
close_hw_manager
