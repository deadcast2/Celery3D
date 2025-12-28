# Program KC705 with DDR3 Framebuffer Test Bitstream

puts "=============================================="
puts "Programming KC705 with DDR3 Framebuffer Test"
puts "=============================================="

set bitstream "./build_ddr3_fb/ddr3_fb_test.bit"

if {![file exists $bitstream]} {
    puts "ERROR: Bitstream not found at $bitstream"
    puts "Run 'make synth-ddr3-fb' first to build the bitstream."
    exit 1
}

# Open hardware manager
open_hw_manager

# Connect to server
connect_hw_server -allow_non_jtag

# Open target (KC705)
open_hw_target

# Get the FPGA device
set device [get_hw_devices xc7k325t_0]
current_hw_device $device

# Set the programming file
set_property PROGRAM.FILE $bitstream $device

# Program
puts "Programming..."
program_hw_devices $device

puts ""
puts "=============================================="
puts "Programming complete!"
puts "=============================================="
puts ""
puts "Expected behavior:"
puts "  - LED[0]: MIG MMCM locked"
puts "  - LED[1]: DDR3 calibration complete"
puts "  - LED[2]: Pattern write in progress (blinks)"
puts "  - LED[3]: Pattern write done (solid ON)"
puts "  - LED[4]: Video clock locked"
puts "  - LED[5]: HDMI init done"
puts "  - LED[6]: HDMI init error (should be OFF)"
puts "  - LED[7]: Heartbeat (slow blink)"
puts ""
puts "HDMI should show a gradient test pattern:"
puts "  - Red gradient horizontally (left to right)"
puts "  - Green gradient vertically (top to bottom)"
puts "  - Blue checkerboard pattern"
puts "=============================================="

close_hw_manager
