# Celery3D

Voodoo1-inspired GPU implementation on Xilinx Kintex-7 (KC705 development board).

## Hardware

- **FPGA:** Xilinx Kintex-7 XC7K325T-2FFG900C
- **Board:** KC705 Evaluation Kit (Rev C)
- **Host:** Intel Z270 chipset, PCIe slot 01.1 (CPU-direct lanes)

## Subsystem Test Projects

| Subsystem | Status | Notes |
|-----------|--------|-------|
| PCIe x8 Gen2 | Verified | Link trains at 5GT/s, BAR0 read/write works |
| DDR3 | Pending | |
| HDMI | Pending | |

## Important Notes

### PCIe Debugging Lessons

1. **Cold boot required:** On some systems, PCIe devices need a full power cycle (not just rescan) to enumerate properly. Hot-plugging via `echo 1 > /sys/bus/pci/rescan` may show the device but memory transactions fail.

2. **Enable memory space after rescan:** After removing/rescanning a device, memory access gets disabled. Always run:
   ```bash
   sudo setpci -s <bus:dev.fn> COMMAND=0x06
   ```

3. **Linux STRICT_DEVMEM:** Modern kernels block `/dev/mem` access to MMIO regions. Use sysfs resource files instead:
   ```c
   int fd = open("/sys/bus/pci/devices/0000:XX:XX.X/resource0", O_RDWR | O_SYNC);
   void *map = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
   ```

4. **Class code matters:** Setting class code to `0x0700` (Serial controller) causes Linux `serial` driver to bind and interfere. Use `0x0300` (VGA compatible) or `0x1180` (Signal processing) for custom devices.

5. **KC705 EMCCLK workaround:** When using BPI flash config mode, either:
   - Add `(* DONT_TOUCH = "TRUE" *) input emcclk` port with pin R24/LVCMOS25
   - Or set `BITSTREAM.CONFIG.EXTMASTERCCLK_EN Disable` for JTAG-only testing

### LED Indicators (KC705 PCIe Example)

| LED | Signal | Expected State |
|-----|--------|----------------|
| LED0 | sys_rst_n | ON when out of reset |
| LED1 | !user_reset | ON when user logic running |
| LED2 | user_lnk_up | ON when PCIe link trained |
| LED3 | heartbeat | BLINKING when user_clk active |

## Building

Each subsystem test is a separate Vivado project under `Vivado/`. Open the `.xpr` file and regenerate IP if needed.

```bash
# Regenerate IP (if Vivado version differs)
vivado -mode batch -source regen_ip.tcl
```

## Testing PCIe

```bash
# Check device enumeration
lspci -d 10ee:

# Check link status
sudo lspci -vvv -s <bus:dev.fn> | grep LnkSta

# Enable memory access
sudo setpci -s <bus:dev.fn> COMMAND=0x06

# Test BAR0 read/write (compile pcie_test.c first)
sudo ./pcie_test
```
