# Program GPU + DDR3 bitstream to KC705
# Usage: vivado -mode batch -source scripts/program_gpu_ddr3.tcl

puts "Programming KC705 with GPU + DDR3 bitstream..."

# Open hardware manager
open_hw_manager

# Connect to hardware server
connect_hw_server -allow_non_jtag

# Open target
open_hw_target

# Get the device
set device [lindex [get_hw_devices] 0]
current_hw_device $device

# Set the bitstream
set_property PROGRAM.FILE {build_gpu_ddr3/gpu_ddr3.bit} $device

# Program the device
program_hw_devices $device

puts "Programming complete!"

# Close
close_hw_target
disconnect_hw_server
close_hw_manager
