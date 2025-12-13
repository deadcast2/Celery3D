// Celery3D GPU - Verilator Testbench for Rasterizer
// Outputs a PPM image file for visual verification
// Renders multiple triangles to demonstrate perspective correction

#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vrasterizer_top.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cmath>

#define SCREEN_WIDTH 640
#define SCREEN_HEIGHT 480
#define FP_FRAC_BITS 16

// Triangle vertex structure
struct Vertex {
    float x, y, z;
    float u, v;
    float r, g, b;
};

struct Triangle {
    Vertex v[3];
    const char* name;
};

// Fixed-point conversion
int32_t float_to_fp(float f) {
    return (int32_t)(f * (1 << FP_FRAC_BITS));
}

float fp_to_float(int32_t fp) {
    return (float)fp / (1 << FP_FRAC_BITS);
}

// RGB565 framebuffer
uint16_t framebuffer[SCREEN_WIDTH * SCREEN_HEIGHT];

// Convert RGB565 to 24-bit RGB for PPM output
void rgb565_to_rgb888(uint16_t c, uint8_t* r, uint8_t* g, uint8_t* b) {
    *r = ((c >> 11) & 0x1F) << 3;
    *g = ((c >> 5) & 0x3F) << 2;
    *b = (c & 0x1F) << 3;
}

// Pack float RGB to RGB565
uint16_t pack_rgb565(float r, float g, float b) {
    uint8_t ri = (uint8_t)(r * 31);
    uint8_t gi = (uint8_t)(g * 63);
    uint8_t bi = (uint8_t)(b * 31);
    return (ri << 11) | (gi << 5) | bi;
}

// Save framebuffer as PPM
void save_ppm(const char* filename) {
    FILE* f = fopen(filename, "wb");
    if (!f) {
        printf("Error: could not open %s for writing\n", filename);
        return;
    }

    fprintf(f, "P6\n%d %d\n255\n", SCREEN_WIDTH, SCREEN_HEIGHT);

    for (int i = 0; i < SCREEN_WIDTH * SCREEN_HEIGHT; i++) {
        uint8_t r, g, b;
        rgb565_to_rgb888(framebuffer[i], &r, &g, &b);
        fputc(r, f);
        fputc(g, f);
        fputc(b, f);
    }

    fclose(f);
    printf("Saved framebuffer to %s\n", filename);
}

// Clear framebuffer
void clear_framebuffer(uint16_t color) {
    for (int i = 0; i < SCREEN_WIDTH * SCREEN_HEIGHT; i++) {
        framebuffer[i] = color;
    }
}

// Write pixel to framebuffer
void write_pixel(int x, int y, uint16_t color) {
    if (x >= 0 && x < SCREEN_WIDTH && y >= 0 && y < SCREEN_HEIGHT) {
        framebuffer[y * SCREEN_WIDTH + x] = color;
    }
}

// Set vertex data on the DUT
// Verilator represents the 288-bit vertex_t as VlWide<9> (9 x 32-bit words)
// SystemVerilog packed struct packs fields MSB-first in declaration order:
//   vertex_t = {x, y, z, w, u, v, r, g, b}
// Verilator stores LSB in word[0]:
//   word[0] = b, word[1] = g, word[2] = r, word[3] = v, word[4] = u,
//   word[5] = w, word[6] = z, word[7] = y, word[8] = x
void set_vertex(Vrasterizer_top* dut, int idx, float x, float y, float z,
                float u, float v, float r, float g, float b) {
    int32_t fp_x = float_to_fp(x);
    int32_t fp_y = float_to_fp(y);
    int32_t fp_z = float_to_fp(z);
    int32_t fp_w = float_to_fp(1.0f / (z + 0.001f));  // 1/z for perspective
    int32_t fp_u = float_to_fp(u);
    int32_t fp_v = float_to_fp(v);
    int32_t fp_r = float_to_fp(r);
    int32_t fp_g = float_to_fp(g);
    int32_t fp_b = float_to_fp(b);

    // Select the vertex port (Verilator exposes wide signals as arrays directly)
    uint32_t* vptr;
    if (idx == 0) vptr = dut->v0;
    else if (idx == 1) vptr = dut->v1;
    else vptr = dut->v2;

    // Pack into Verilator's word array (LSB-first ordering)
    vptr[0] = (uint32_t)fp_b;  // bits [31:0]
    vptr[1] = (uint32_t)fp_g;  // bits [63:32]
    vptr[2] = (uint32_t)fp_r;  // bits [95:64]
    vptr[3] = (uint32_t)fp_v;  // bits [127:96]
    vptr[4] = (uint32_t)fp_u;  // bits [159:128]
    vptr[5] = (uint32_t)fp_w;  // bits [191:160]
    vptr[6] = (uint32_t)fp_z;  // bits [223:192]
    vptr[7] = (uint32_t)fp_y;  // bits [255:224]
    vptr[8] = (uint32_t)fp_x;  // bits [287:256]
}

// Extract fragment data from the DUT output
// fragment_t (217 bits) = {x[12], y[12], z[32], u[32], v[32], r[32], g[32], b[32], valid[1]}
// Verilator stores as VlWide<7> (7 x 32-bit words)
void get_fragment(Vrasterizer_top* dut, int* x, int* y, float* r, float* g, float* b) {
    uint32_t* fptr = dut->frag_out;

    // Extract fields from packed representation
    // valid is bit 0, b is bits [32:1], g is bits [64:33], etc.
    // word[0] = {b[30:0], valid}
    // word[1] = {g[29:0], b[31]}
    // etc. - need to handle bit alignment

    // Simpler extraction using bit operations on the full width:
    // valid = bit 0
    // b = bits [32:1]
    // g = bits [64:33]
    // r = bits [96:65]
    // v = bits [128:97]
    // u = bits [160:129]
    // z = bits [192:161]
    // y = bits [204:193]
    // x = bits [216:205]

    uint64_t w0 = fptr[0];
    uint64_t w1 = fptr[1];
    uint64_t w2 = fptr[2];
    uint64_t w3 = fptr[3];
    uint64_t w4 = fptr[4];
    uint64_t w5 = fptr[5];
    uint64_t w6 = fptr[6];

    // Extract b: bits [32:1] - crosses word boundary
    int32_t fp_b = (int32_t)((w0 >> 1) | ((w1 & 0x1) << 31));
    // Extract g: bits [64:33]
    int32_t fp_g = (int32_t)((w1 >> 1) | ((w2 & 0x1) << 31));
    // Extract r: bits [96:65]
    int32_t fp_r = (int32_t)((w2 >> 1) | ((w3 & 0x1) << 31));
    // Extract y: bits [204:193]
    *y = (int)((w6 >> 1) & 0xFFF);
    // Extract x: bits [216:205]
    *x = (int)((w6 >> 13) & 0xFFF);

    // Convert fixed-point color to float
    *r = fp_to_float(fp_r);
    *g = fp_to_float(fp_g);
    *b = fp_to_float(fp_b);
}

// Helper to load triangle vertices into DUT
void load_triangle(Vrasterizer_top* dut, const Triangle& tri) {
    for (int i = 0; i < 3; i++) {
        set_vertex(dut, i,
            tri.v[i].x, tri.v[i].y, tri.v[i].z,
            tri.v[i].u, tri.v[i].v,
            tri.v[i].r, tri.v[i].g, tri.v[i].b);
    }
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    // Create DUT instance
    Vrasterizer_top* dut = new Vrasterizer_top;

    // Enable VCD tracing
    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    dut->trace(tfp, 99);
    tfp->open("rasterizer.vcd");

    // Initialize
    dut->clk = 0;
    dut->rst_n = 0;
    dut->tri_valid = 0;
    dut->frag_ready = 1;

    // Clear framebuffer to dark blue
    clear_framebuffer(pack_rgb565(0.05f, 0.05f, 0.15f));

    // Reset sequence
    for (int i = 0; i < 10; i++) {
        dut->clk = !dut->clk;
        dut->eval();
        tfp->dump(i);
    }
    dut->rst_n = 1;

    printf("==============================================\n");
    printf("Celery3D Rasterizer - Perspective Correction Demo\n");
    printf("==============================================\n");
    printf("Screen: %dx%d\n\n", SCREEN_WIDTH, SCREEN_HEIGHT);

    // Define test triangles showcasing perspective correction
    // All triangles use CCW winding
    Triangle triangles[7];

    // Triangle 0: Classic RGB triangle with depth variation
    // Top vertex close, bottom vertices far - shows perspective color shift
    triangles[0].v[0] = {320.0f, 60.0f, 0.15f, 0.5f, 0.0f, 1.0f, 0.2f, 0.2f};   // top (red, very close)
    triangles[0].v[1] = {180.0f, 220.0f, 0.7f, 0.0f, 1.0f, 0.2f, 1.0f, 0.2f};   // bottom-left (green, far)
    triangles[0].v[2] = {460.0f, 220.0f, 0.7f, 1.0f, 1.0f, 0.2f, 0.2f, 1.0f};   // bottom-right (blue, far)
    triangles[0].name = "RGB pyramid (top close)";

    // Triangle 1: Floor tile left - receding into distance
    triangles[1].v[0] = {50.0f, 250.0f, 0.3f, 0.0f, 0.0f, 0.6f, 0.4f, 0.2f};    // front-left (close, brown)
    triangles[1].v[1] = {50.0f, 450.0f, 0.9f, 0.0f, 1.0f, 0.2f, 0.15f, 0.1f};   // back-left (far, dark)
    triangles[1].v[2] = {320.0f, 450.0f, 0.9f, 1.0f, 1.0f, 0.2f, 0.15f, 0.1f};  // back-right (far, dark)
    triangles[1].name = "Floor left (front bright)";

    // Triangle 2: Floor tile right - matching the left tile
    triangles[2].v[0] = {50.0f, 250.0f, 0.3f, 0.0f, 0.0f, 0.6f, 0.4f, 0.2f};    // front-left (close)
    triangles[2].v[1] = {320.0f, 450.0f, 0.9f, 1.0f, 1.0f, 0.2f, 0.15f, 0.1f};  // back-right (far)
    triangles[2].v[2] = {320.0f, 250.0f, 0.3f, 1.0f, 0.0f, 0.6f, 0.4f, 0.2f};   // front-right (close)
    triangles[2].name = "Floor right (front bright)";

    // Triangle 3: Cyan pillar left side - vertical with depth
    triangles[3].v[0] = {500.0f, 100.0f, 0.25f, 0.0f, 0.0f, 0.0f, 0.9f, 0.9f};  // top-front (cyan, close)
    triangles[3].v[1] = {500.0f, 400.0f, 0.25f, 0.0f, 1.0f, 0.0f, 0.9f, 0.9f};  // bottom-front (cyan, close)
    triangles[3].v[2] = {560.0f, 420.0f, 0.6f, 1.0f, 1.0f, 0.0f, 0.3f, 0.3f};   // bottom-back (dark, far)
    triangles[3].name = "Pillar left face";

    // Triangle 4: Cyan pillar right side
    triangles[4].v[0] = {500.0f, 100.0f, 0.25f, 0.0f, 0.0f, 0.0f, 0.9f, 0.9f};  // top-front (cyan, close)
    triangles[4].v[1] = {560.0f, 420.0f, 0.6f, 1.0f, 1.0f, 0.0f, 0.3f, 0.3f};   // bottom-back (dark, far)
    triangles[4].v[2] = {560.0f, 120.0f, 0.6f, 1.0f, 0.0f, 0.0f, 0.3f, 0.3f};   // top-back (dark, far)
    triangles[4].name = "Pillar right face";

    // Triangle 5: Magenta accent - tilted plane
    triangles[5].v[0] = {580.0f, 200.0f, 0.2f, 0.0f, 0.0f, 1.0f, 0.0f, 0.8f};   // left (magenta, close)
    triangles[5].v[1] = {580.0f, 350.0f, 0.5f, 0.0f, 1.0f, 0.5f, 0.0f, 0.4f};   // bottom (purple, mid)
    triangles[5].v[2] = {630.0f, 275.0f, 0.8f, 1.0f, 0.5f, 0.2f, 0.0f, 0.2f};   // right (dark, far)
    triangles[5].name = "Magenta accent";

    // Triangle 6: Yellow warning stripe - dramatic depth
    triangles[6].v[0] = {350.0f, 280.0f, 0.2f, 0.0f, 0.0f, 1.0f, 0.9f, 0.0f};   // front (yellow, close)
    triangles[6].v[1] = {380.0f, 400.0f, 0.85f, 0.5f, 1.0f, 0.3f, 0.25f, 0.0f}; // back-left (dark yellow, far)
    triangles[6].v[2] = {450.0f, 320.0f, 0.5f, 1.0f, 0.5f, 0.7f, 0.6f, 0.0f};   // mid-right (orange, mid)
    triangles[6].name = "Yellow accent";

    const int num_triangles = 7;

    // Simulation state
    uint64_t sim_time = 10;
    int total_fragments = 0;
    int current_triangle = 0;
    bool triangle_submitted = false;
    bool waiting_for_done = false;
    int drain_cycles = 0;
    int submit_delay = 0;

    printf("Rendering %d triangles...\n\n", num_triangles);

    // Main simulation loop
    int max_cycles = 2000000;  // Enough for all triangles
    for (int cycle = 0; cycle < max_cycles; cycle++) {
        // Rising edge
        dut->clk = 1;
        dut->eval();
        tfp->dump(sim_time++);

        // Collect fragments
        if (dut->frag_valid && dut->frag_ready) {
            total_fragments++;

            int frag_x, frag_y;
            float frag_r, frag_g, frag_b;
            get_fragment(dut, &frag_x, &frag_y, &frag_r, &frag_g, &frag_b);

            // Clamp colors
            frag_r = frag_r < 0.0f ? 0.0f : (frag_r > 1.0f ? 1.0f : frag_r);
            frag_g = frag_g < 0.0f ? 0.0f : (frag_g > 1.0f ? 1.0f : frag_g);
            frag_b = frag_b < 0.0f ? 0.0f : (frag_b > 1.0f ? 1.0f : frag_b);

            write_pixel(frag_x, frag_y, pack_rgb565(frag_r, frag_g, frag_b));
        }

        // Triangle submission state machine
        if (current_triangle < num_triangles) {
            if (!triangle_submitted && !waiting_for_done) {
                // Load and submit next triangle
                if (dut->tri_ready && submit_delay > 5) {
                    load_triangle(dut, triangles[current_triangle]);
                    printf("[%d] %s\n", current_triangle, triangles[current_triangle].name);
                    dut->tri_valid = 1;
                    triangle_submitted = true;
                } else {
                    submit_delay++;
                }
            } else if (triangle_submitted) {
                dut->tri_valid = 0;
                waiting_for_done = true;
                triangle_submitted = false;
            } else if (waiting_for_done) {
                // Wait for rasterizer to finish
                if (!dut->busy) {
                    drain_cycles++;
                    // Drain perspective correction pipeline (8 stages + margin)
                    if (drain_cycles > 15) {
                        current_triangle++;
                        waiting_for_done = false;
                        drain_cycles = 0;
                        submit_delay = 0;
                    }
                }
            }
        } else {
            // All triangles done
            break;
        }

        // Falling edge
        dut->clk = 0;
        dut->eval();
        tfp->dump(sim_time++);
    }

    printf("\n==============================================\n");
    printf("Rendering complete!\n");
    printf("Total fragments: %d\n", total_fragments);
    printf("==============================================\n");

    // Save output
    save_ppm("rasterizer_output.ppm");

    // Cleanup
    tfp->close();
    delete tfp;
    delete dut;

    printf("\nOutput: rasterizer_output.ppm\n");
    printf("Waveform: rasterizer.vcd\n");
    return 0;
}
