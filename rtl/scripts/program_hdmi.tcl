# Celery3D GPU - Program HDMI Bitstream to KC705
# Usage: vivado -mode batch -source scripts/program_hdmi.tcl

puts "=============================================="
puts "Programming KC705 with HDMI test bitstream"
puts "=============================================="

open_hw_manager
connect_hw_server
open_hw_target

# Select the first device (KC705 Kintex-7)
current_hw_device [lindex [get_hw_devices] 0]
puts "Device: [get_property NAME [current_hw_device]]"

# Program the bitstream
set_property PROGRAM.FILE {build_hdmi/hdmi_test.bit} [current_hw_device]
program_hw_devices [current_hw_device]

puts ""
puts "Programming complete!"
puts "=============================================="

close_hw_target
disconnect_hw_server
quit
