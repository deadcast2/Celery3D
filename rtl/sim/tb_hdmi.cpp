// Celery3D GPU - Verilator Testbench for HDMI Output
// Simulates video timing, test pattern generation, and ADV7511 I2C init
// Captures one frame of YCbCr output and converts to PPM for verification

#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vhdmi_top.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <vector>

// Video parameters (must match video_pkg.sv)
#define H_ACTIVE      640
#define V_ACTIVE      480
#define H_TOTAL       800
#define V_TOTAL       525

// Simulation parameters
#define MAX_SIM_TIME  (H_TOTAL * V_TOTAL * 5)  // 5 frames worth (need extra for I2C init)
#define TRACE_DEPTH   99

// I2C transaction log
struct I2CTransaction {
    uint8_t slave_addr;
    uint8_t reg_addr;
    uint8_t data;
    bool    ack_ok;
};

std::vector<I2CTransaction> i2c_log;

// Framebuffer for captured video
uint16_t ycbcr_frame[H_ACTIVE * V_ACTIVE];
uint8_t  rgb_frame[H_ACTIVE * V_ACTIVE * 3];

// YCbCr to RGB conversion (BT.601)
void ycbcr_to_rgb(uint8_t y, uint8_t cb, uint8_t cr, uint8_t* r, uint8_t* g, uint8_t* b) {
    // Y is offset by 16, Cb/Cr are offset by 128
    int y_adj = y - 16;
    int cb_adj = cb - 128;
    int cr_adj = cr - 128;

    // BT.601 conversion
    int r_val = (298 * y_adj + 409 * cr_adj + 128) >> 8;
    int g_val = (298 * y_adj - 100 * cb_adj - 208 * cr_adj + 128) >> 8;
    int b_val = (298 * y_adj + 516 * cb_adj + 128) >> 8;

    // Clamp to 0-255
    *r = (r_val < 0) ? 0 : (r_val > 255) ? 255 : r_val;
    *g = (g_val < 0) ? 0 : (g_val > 255) ? 255 : g_val;
    *b = (b_val < 0) ? 0 : (b_val > 255) ? 255 : b_val;
}

// Save PPM image
void save_ppm(const char* filename, uint8_t* rgb, int width, int height) {
    FILE* f = fopen(filename, "wb");
    if (!f) {
        printf("Error: Could not open %s for writing\n", filename);
        return;
    }
    fprintf(f, "P6\n%d %d\n255\n", width, height);
    fwrite(rgb, 3, width * height, f);
    fclose(f);
    printf("Saved %s\n", filename);
}

// Behavioral I2C slave model - simplified for ADV7511
class I2CSlave {
public:
    bool scl_prev = true;
    bool sda_prev = true;
    bool in_transaction = false;
    int  bit_count = 0;
    int  byte_count = 0;
    uint8_t shift_reg = 0;
    uint8_t slave_addr = 0;
    uint8_t reg_addr = 0;
    uint8_t write_data = 0;
    bool in_ack_phase = false;
    bool ack_scl_was_high = false;  // Tracks if we've seen SCL high during ACK

    // Debug counter
    int update_count = 0;

    // Returns SDA value to drive (for ACK)
    bool update(bool scl, bool sda) {
        bool sda_out = true;  // Default: release (high-Z)
        update_count++;

        // Detect START condition: SDA falls while SCL is high
        if (scl && scl_prev && !sda && sda_prev) {
            in_transaction = true;
            bit_count = 0;
            byte_count = 0;
            shift_reg = 0;
            in_ack_phase = false;
            ack_scl_was_high = false;
        }

        // Detect STOP condition: SDA rises while SCL is high
        if (scl && scl_prev && sda && !sda_prev) {
            if (in_transaction && byte_count >= 3) {
                // Complete transaction
                I2CTransaction txn;
                txn.slave_addr = slave_addr;
                txn.reg_addr = reg_addr;
                txn.data = write_data;
                txn.ack_ok = true;
                i2c_log.push_back(txn);
            }
            in_transaction = false;
            in_ack_phase = false;
        }

        if (in_transaction) {
            if (in_ack_phase) {
                // During ACK phase, hold SDA low (always ACK for ADV7511 address)
                bool should_ack = (slave_addr == 0x39 || byte_count > 0);
                if (should_ack) {
                    sda_out = false;  // ACK
                }

                // Track when SCL goes high
                if (scl) {
                    ack_scl_was_high = true;
                }

                // End ACK phase on falling SCL edge AFTER it was high
                if (!scl && scl_prev && ack_scl_was_high) {
                    in_ack_phase = false;
                    ack_scl_was_high = false;
                }
            } else {
                // Data phase: sample on rising SCL edge
                if (scl && !scl_prev) {
                    shift_reg = (shift_reg << 1) | (sda ? 1 : 0);
                    bit_count++;

                    if (bit_count == 8) {
                        // Received a byte, store it
                        if (byte_count == 0) {
                            slave_addr = (shift_reg >> 1);
                        } else if (byte_count == 1) {
                            reg_addr = shift_reg;
                        } else if (byte_count == 2) {
                            write_data = shift_reg;
                        }
                        byte_count++;
                        shift_reg = 0;
                        // bit_count stays at 8 to signal "waiting for ACK"
                    }
                }

                // Enter ACK phase on falling edge after 8th bit
                if (!scl && scl_prev && bit_count == 8) {
                    in_ack_phase = true;
                    ack_scl_was_high = false;
                    bit_count = 0;  // Reset for next byte
                }
            }
        }

        scl_prev = scl;
        sda_prev = sda;
        return sda_out;
    }
};

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    // Create DUT instance
    Vhdmi_top* dut = new Vhdmi_top;

    // Enable tracing
    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    dut->trace(tfp, TRACE_DEPTH);
    tfp->open("hdmi.vcd");

    // I2C slave model
    I2CSlave i2c_slave;

    // Initialize signals
    dut->clk_50mhz = 0;
    dut->rst_n = 0;
    dut->pattern_sel = 0;  // Color bars
    dut->use_framebuffer = 0;
    dut->fb_read_data = 0;
    dut->fb_read_valid = 0;
    dut->i2c_scl_i = 1;
    dut->i2c_sda_i = 1;

    // Reset sequence
    printf("HDMI Testbench Starting...\n");
    printf("Resolution: %dx%d\n", H_ACTIVE, V_ACTIVE);

    for (int i = 0; i < 20; i++) {
        dut->clk_50mhz = !dut->clk_50mhz;
        dut->eval();
        tfp->dump(i);
    }
    dut->rst_n = 1;

    // State for frame capture
    bool capturing = false;
    bool frame_captured = false;
    int pixel_x = 0;
    int pixel_y = 0;
    int frame_count = 0;
    bool prev_vsync = true;
    bool prev_de = false;
    uint8_t cb_saved = 128;  // For 4:2:2 reconstruction

    // Simulation loop
    uint64_t sim_time = 20;
    uint64_t max_time = MAX_SIM_TIME * 2;  // 50 MHz clock = 2 edges per pixel clock

    printf("Waiting for MMCM lock and ADV7511 init...\n");

    while (sim_time < max_time) {
        dut->clk_50mhz = !dut->clk_50mhz;
        dut->eval();

        // Update I2C slave model (on 50 MHz clock edges)
        if (dut->clk_50mhz) {
            // Reconstruct SCL/SDA from open-drain outputs
            bool scl = dut->i2c_scl_oen ? true : false;  // oen=1 means high-Z (pulled high)
            bool sda_master = dut->i2c_sda_oen ? true : false;

            bool sda_slave = i2c_slave.update(scl, sda_master);

            // SDA is wire-AND of master and slave
            bool sda = sda_master && sda_slave;
            dut->i2c_sda_i = sda;
            dut->i2c_scl_i = scl;

        }

        // Check for initialization complete
        static bool init_logged = false;
        if (dut->hdmi_init_done && !init_logged) {
            printf("ADV7511 initialization complete! (%zu I2C transactions)\n", i2c_log.size());
            init_logged = true;
            printf("Starting frame capture...\n");
            capturing = true;
        }

        if (dut->hdmi_init_error && !capturing) {
            printf("ERROR: ADV7511 initialization failed!\n");
            break;
        }

        // Frame capture (on pixel clock edges, simulated as 25 MHz)
        // Since we're running at 50 MHz and pixel clock is 25 MHz,
        // capture on every other cycle
        static bool pixel_clk_prev = false;
        bool pixel_clk_edge = dut->hdmi_clk && !pixel_clk_prev;
        pixel_clk_prev = dut->hdmi_clk;

        if (capturing && pixel_clk_edge && !frame_captured) {
            // Detect new frame (vsync falling edge for active-low sync)
            bool vsync_start = !dut->hdmi_vsync && prev_vsync;
            if (vsync_start) {
                frame_count++;
                if (frame_count == 1) {  // Start capturing on first frame
                    printf("Frame %d start - capturing...\n", frame_count);
                    pixel_x = 0;
                    pixel_y = 0;
                    memset(ycbcr_frame, 0, sizeof(ycbcr_frame));
                }
            }
            prev_vsync = dut->hdmi_vsync;

            // Capture pixels during DE
            if (dut->hdmi_de && frame_count == 1) {
                if (pixel_y < V_ACTIVE && pixel_x < H_ACTIVE) {
                    ycbcr_frame[pixel_y * H_ACTIVE + pixel_x] = dut->hdmi_d;
                }
                pixel_x++;
            }

            // Detect end of line (DE falling edge)
            if (!dut->hdmi_de && prev_de && frame_count == 1) {
                if (pixel_x > 0) {
                    pixel_y++;
                    pixel_x = 0;
                    if (pixel_y % 100 == 0) {
                        printf("  Captured line %d\n", pixel_y);
                    }
                    if (pixel_y >= V_ACTIVE) {
                        printf("Frame capture complete!\n");
                        frame_captured = true;
                    }
                }
            }
            prev_de = dut->hdmi_de;
        }

        tfp->dump(sim_time);
        sim_time++;

        if (frame_captured) break;
    }

    // Convert YCbCr 4:2:2 to RGB
    printf("Converting YCbCr to RGB...\n");
    for (int y = 0; y < V_ACTIVE; y++) {
        for (int x = 0; x < H_ACTIVE; x += 2) {
            int idx0 = y * H_ACTIVE + x;
            int idx1 = y * H_ACTIVE + x + 1;

            // Even pixel: {Cb, Y0}
            uint16_t pix0 = ycbcr_frame[idx0];
            uint8_t cb = (pix0 >> 8) & 0xFF;
            uint8_t y0 = pix0 & 0xFF;

            // Odd pixel: {Cr, Y1}
            uint16_t pix1 = (x + 1 < H_ACTIVE) ? ycbcr_frame[idx1] : pix0;
            uint8_t cr = (pix1 >> 8) & 0xFF;
            uint8_t y1 = pix1 & 0xFF;

            // Convert both pixels (they share Cb/Cr)
            uint8_t r0, g0, b0, r1, g1, b1;
            ycbcr_to_rgb(y0, cb, cr, &r0, &g0, &b0);
            ycbcr_to_rgb(y1, cb, cr, &r1, &g1, &b1);

            rgb_frame[idx0 * 3 + 0] = r0;
            rgb_frame[idx0 * 3 + 1] = g0;
            rgb_frame[idx0 * 3 + 2] = b0;

            if (x + 1 < H_ACTIVE) {
                rgb_frame[idx1 * 3 + 0] = r1;
                rgb_frame[idx1 * 3 + 1] = g1;
                rgb_frame[idx1 * 3 + 2] = b1;
            }
        }
    }

    // Save output image
    save_ppm("hdmi_output.ppm", rgb_frame, H_ACTIVE, V_ACTIVE);

    // Print summary
    printf("\nSimulation Summary:\n");
    printf("  Pixel clock locked: %s\n", dut->pixel_clk_locked ? "YES" : "NO");
    printf("  ADV7511 init done:  %s\n", dut->hdmi_init_done ? "YES" : "NO");
    printf("  ADV7511 init error: %s\n", dut->hdmi_init_error ? "YES" : "NO");
    printf("  Frames captured:    %d\n", frame_count);
    printf("  I2C transactions:   %zu\n", i2c_log.size());

    // Cleanup
    tfp->close();
    delete tfp;
    delete dut;

    printf("\nDone! View hdmi_output.ppm to verify color bars.\n");
    printf("View hdmi.vcd for waveforms.\n");

    return 0;
}
