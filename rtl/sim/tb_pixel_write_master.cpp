// Celery3D GPU - Verilator Testbench for Pixel Write Master
// Tests AXI4 write transactions for single-pixel framebuffer writes

#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vpixel_write_master.h"
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cassert>
#include <vector>

// Framebuffer parameters (must match DUT)
#define FB_WIDTH      640
#define FB_HEIGHT     480
#define FB_BASE_ADDR  0x00000000

// Simulation parameters
#define MAX_SIM_TIME  100000
#define TRACE_DEPTH   99

// Test result tracking
struct WriteTransaction {
    uint32_t addr;
    uint32_t strobe;
    uint16_t color;
    int pixel_x;
    int pixel_y;
};

std::vector<WriteTransaction> captured_writes;

// Clock the DUT
void tick(Vpixel_write_master* dut, VerilatedVcdC* trace, uint64_t& sim_time) {
    dut->clk = 0;
    dut->eval();
    if (trace) trace->dump(sim_time++);

    dut->clk = 1;
    dut->eval();
    if (trace) trace->dump(sim_time++);
}

// Write a pixel and capture the AXI transaction
bool write_pixel(Vpixel_write_master* dut, VerilatedVcdC* trace, uint64_t& sim_time,
                 int x, int y, uint16_t color, int max_cycles = 100) {

    // Present pixel data
    dut->pixel_x = x;
    dut->pixel_y = y;
    dut->pixel_color = color;
    dut->pixel_valid = 1;

    // Wait for ready
    int cycles = 0;
    while (!dut->pixel_ready && cycles < max_cycles) {
        tick(dut, trace, sim_time);
        cycles++;
    }

    if (cycles >= max_cycles) {
        printf("ERROR: Timeout waiting for pixel_ready\n");
        return false;
    }

    // Handshake complete, deassert valid
    tick(dut, trace, sim_time);
    dut->pixel_valid = 0;

    // Now wait for AXI write address phase
    WriteTransaction txn;
    txn.pixel_x = x;
    txn.pixel_y = y;
    txn.color = color;

    // Wait for awvalid
    cycles = 0;
    while (!dut->m_axi_awvalid && cycles < max_cycles) {
        tick(dut, trace, sim_time);
        cycles++;
    }

    if (cycles >= max_cycles) {
        printf("ERROR: Timeout waiting for awvalid\n");
        return false;
    }

    // Capture address
    txn.addr = dut->m_axi_awaddr;

    // Accept address
    dut->m_axi_awready = 1;
    tick(dut, trace, sim_time);
    dut->m_axi_awready = 0;

    // Wait for wvalid
    cycles = 0;
    while (!dut->m_axi_wvalid && cycles < max_cycles) {
        tick(dut, trace, sim_time);
        cycles++;
    }

    if (cycles >= max_cycles) {
        printf("ERROR: Timeout waiting for wvalid\n");
        return false;
    }

    // Capture strobe
    txn.strobe = dut->m_axi_wstrb;

    // Accept data
    dut->m_axi_wready = 1;
    tick(dut, trace, sim_time);
    dut->m_axi_wready = 0;

    // Wait for bready (DUT waiting for response)
    cycles = 0;
    while (!dut->m_axi_bready && cycles < max_cycles) {
        tick(dut, trace, sim_time);
        cycles++;
    }

    // Provide write response
    dut->m_axi_bvalid = 1;
    dut->m_axi_bresp = 0;  // OKAY
    dut->m_axi_bid = 1;
    tick(dut, trace, sim_time);
    dut->m_axi_bvalid = 0;

    // Wait for DUT to return to idle
    cycles = 0;
    while (dut->busy && cycles < max_cycles) {
        tick(dut, trace, sim_time);
        cycles++;
    }

    captured_writes.push_back(txn);
    return true;
}

// Verify a write transaction
bool verify_write(const WriteTransaction& txn) {
    // Calculate expected byte address
    uint32_t expected_byte_addr = FB_BASE_ADDR + (txn.pixel_y * FB_WIDTH + txn.pixel_x) * 2;

    // Expected AXI address (32-byte aligned)
    uint32_t expected_axi_addr = expected_byte_addr & ~0x1F;

    // Expected pixel lane (0-15)
    int expected_lane = (expected_byte_addr >> 1) & 0xF;

    // Expected byte strobe (2 bytes for RGB565)
    uint32_t expected_strobe = 0x3 << (expected_lane * 2);

    bool addr_ok = (txn.addr == expected_axi_addr);
    bool strobe_ok = (txn.strobe == expected_strobe);

    if (!addr_ok || !strobe_ok) {
        printf("FAIL: Pixel (%d, %d) color=0x%04X\n", txn.pixel_x, txn.pixel_y, txn.color);
        printf("  Expected addr: 0x%08X, got: 0x%08X %s\n",
               expected_axi_addr, txn.addr, addr_ok ? "OK" : "FAIL");
        printf("  Expected strobe: 0x%08X, got: 0x%08X %s\n",
               expected_strobe, txn.strobe, strobe_ok ? "OK" : "FAIL");
        printf("  (byte_addr=0x%08X, lane=%d)\n", expected_byte_addr, expected_lane);
        return false;
    }

    return true;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    // Create DUT
    Vpixel_write_master* dut = new Vpixel_write_master;

    // Setup tracing
    Verilated::traceEverOn(true);
    VerilatedVcdC* trace = new VerilatedVcdC;
    dut->trace(trace, TRACE_DEPTH);
    trace->open("pixel_write_master.vcd");

    uint64_t sim_time = 0;

    // Initialize inputs
    dut->clk = 0;
    dut->rst_n = 0;
    dut->pixel_x = 0;
    dut->pixel_y = 0;
    dut->pixel_color = 0;
    dut->pixel_valid = 0;
    dut->m_axi_awready = 0;
    dut->m_axi_wready = 0;
    dut->m_axi_bvalid = 0;
    dut->m_axi_bresp = 0;
    dut->m_axi_bid = 0;

    // Reset
    for (int i = 0; i < 10; i++) {
        tick(dut, trace, sim_time);
    }
    dut->rst_n = 1;
    for (int i = 0; i < 5; i++) {
        tick(dut, trace, sim_time);
    }

    printf("=== Pixel Write Master Testbench ===\n\n");

    // Test 1: Write pixel at (0, 0)
    printf("Test 1: Write pixel at (0, 0)...\n");
    if (!write_pixel(dut, trace, sim_time, 0, 0, 0xF800)) {  // Red
        printf("FAIL: Write failed\n");
        return 1;
    }

    // Test 2: Write pixel at (1, 0) - adjacent pixel, same AXI beat
    printf("Test 2: Write pixel at (1, 0)...\n");
    if (!write_pixel(dut, trace, sim_time, 1, 0, 0x07E0)) {  // Green
        printf("FAIL: Write failed\n");
        return 1;
    }

    // Test 3: Write pixel at (15, 0) - last pixel in first beat
    printf("Test 3: Write pixel at (15, 0)...\n");
    if (!write_pixel(dut, trace, sim_time, 15, 0, 0x001F)) {  // Blue
        printf("FAIL: Write failed\n");
        return 1;
    }

    // Test 4: Write pixel at (16, 0) - first pixel in second beat
    printf("Test 4: Write pixel at (16, 0)...\n");
    if (!write_pixel(dut, trace, sim_time, 16, 0, 0xFFFF)) {  // White
        printf("FAIL: Write failed\n");
        return 1;
    }

    // Test 5: Write pixel at (320, 240) - center of screen
    printf("Test 5: Write pixel at (320, 240)...\n");
    if (!write_pixel(dut, trace, sim_time, 320, 240, 0xF81F)) {  // Magenta
        printf("FAIL: Write failed\n");
        return 1;
    }

    // Test 6: Write pixel at (639, 479) - last pixel
    printf("Test 6: Write pixel at (639, 479)...\n");
    if (!write_pixel(dut, trace, sim_time, 639, 479, 0x0000)) {  // Black
        printf("FAIL: Write failed\n");
        return 1;
    }

    // Test 7: Random pixels
    printf("Test 7: 100 random pixels...\n");
    srand(12345);
    for (int i = 0; i < 100; i++) {
        int x = rand() % FB_WIDTH;
        int y = rand() % FB_HEIGHT;
        uint16_t color = rand() & 0xFFFF;
        if (!write_pixel(dut, trace, sim_time, x, y, color)) {
            printf("FAIL: Write failed at random pixel %d\n", i);
            return 1;
        }
    }

    printf("\n=== Verifying all writes ===\n");

    int pass_count = 0;
    int fail_count = 0;

    for (const auto& txn : captured_writes) {
        if (verify_write(txn)) {
            pass_count++;
        } else {
            fail_count++;
        }
    }

    printf("\n=== Results ===\n");
    printf("Total writes: %zu\n", captured_writes.size());
    printf("Passed: %d\n", pass_count);
    printf("Failed: %d\n", fail_count);

    // Cleanup
    trace->close();
    delete trace;
    delete dut;

    if (fail_count > 0) {
        printf("\n*** TEST FAILED ***\n");
        return 1;
    }

    printf("\n*** ALL TESTS PASSED ***\n");
    return 0;
}
