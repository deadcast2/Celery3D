// Celery3D GPU - Verilator Testbench for Rasterizer
// Outputs a PPM image file for visual verification
// Renders multiple triangles to demonstrate perspective correction, texture mapping,
// and depth buffering
// Supports bilinear texture filtering and Glide-compatible depth comparison functions

#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vrasterizer_top.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cmath>

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#define SCREEN_WIDTH 640
#define SCREEN_HEIGHT 480
#define FP_FRAC_BITS 16
#define TEX_SIZE 64
#define DB_SIZE 128  // Depth buffer dimension (128x128)
#define FB_WIDTH 640
#define FB_HEIGHT 480

// Depth comparison functions (matches Glide GR_CMP_*)
enum DepthFunc {
    GR_CMP_NEVER    = 0,
    GR_CMP_LESS     = 1,
    GR_CMP_EQUAL    = 2,
    GR_CMP_LEQUAL   = 3,
    GR_CMP_GREATER  = 4,
    GR_CMP_NOTEQUAL = 5,
    GR_CMP_GEQUAL   = 6,
    GR_CMP_ALWAYS   = 7
};

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

// Clear software framebuffer (for initialization)
void clear_framebuffer(uint16_t color) {
    for (int i = 0; i < SCREEN_WIDTH * SCREEN_HEIGHT; i++) {
        framebuffer[i] = color;
    }
}

// Clear hardware framebuffer
void clear_hw_framebuffer(Vrasterizer_top* dut, uint16_t color, uint64_t& sim_time) {
    dut->fb_clear_color = color;
    dut->fb_clear = 1;

    // Wait for clear to start
    for (int i = 0; i < 5; i++) {
        dut->clk = 1; dut->eval(); sim_time++;
        dut->clk = 0; dut->eval(); sim_time++;
    }

    // Wait for clear to complete (FB_WIDTH * FB_HEIGHT cycles)
    int clear_cycles = FB_WIDTH * FB_HEIGHT + 100;
    for (int i = 0; i < clear_cycles; i++) {
        dut->clk = 1; dut->eval(); sim_time++;
        dut->clk = 0; dut->eval(); sim_time++;
        if (!dut->fb_clearing && i > 10) break;
    }

    dut->fb_clear = 0;

    // A few extra cycles to settle
    for (int i = 0; i < 5; i++) {
        dut->clk = 1; dut->eval(); sim_time++;
        dut->clk = 0; dut->eval(); sim_time++;
    }

    printf("  Framebuffer cleared to 0x%04X\n", color);
}

// Read hardware framebuffer into software buffer
void read_hw_framebuffer(Vrasterizer_top* dut, uint64_t& sim_time) {
    for (int y = 0; y < FB_HEIGHT; y++) {
        for (int x = 0; x < FB_WIDTH; x++) {
            // Issue read request
            dut->fb_read_x = x;
            dut->fb_read_y = y;
            dut->fb_read_en = 1;

            // Clock cycle 1: request registered
            dut->clk = 1; dut->eval(); sim_time++;
            dut->clk = 0; dut->eval(); sim_time++;

            dut->fb_read_en = 0;

            // Clock cycle 2: address latched, read issued
            dut->clk = 1; dut->eval(); sim_time++;
            dut->clk = 0; dut->eval(); sim_time++;

            // Clock cycle 3: data valid
            dut->clk = 1; dut->eval(); sim_time++;
            dut->clk = 0; dut->eval(); sim_time++;

            // Read the data
            framebuffer[y * FB_WIDTH + x] = dut->fb_read_data;
        }
    }
}

// Write pixel to framebuffer (kept for compatibility, but not used with hw fb)
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

// Load a PNG texture into the texture unit (resizes to TEX_SIZE x TEX_SIZE)
bool load_png_texture(Vrasterizer_top* dut, const char* filename, uint64_t& sim_time) {
    int width, height, channels;
    unsigned char* img = stbi_load(filename, &width, &height, &channels, 3);  // Force RGB

    if (!img) {
        printf("Error: Could not load texture '%s': %s\n", filename, stbi_failure_reason());
        return false;
    }

    printf("Loading texture '%s' (%dx%d) -> %dx%d...\n", filename, width, height, TEX_SIZE, TEX_SIZE);

    // Box filter resize and convert to RGB565
    float scale_x = (float)width / TEX_SIZE;
    float scale_y = (float)height / TEX_SIZE;

    for (int ty = 0; ty < TEX_SIZE; ty++) {
        for (int tx = 0; tx < TEX_SIZE; tx++) {
            // Sample region in source image
            int sx0 = (int)(tx * scale_x);
            int sy0 = (int)(ty * scale_y);
            int sx1 = (int)((tx + 1) * scale_x);
            int sy1 = (int)((ty + 1) * scale_y);
            if (sx1 == sx0) sx1 = sx0 + 1;
            if (sy1 == sy0) sy1 = sy0 + 1;

            // Average pixels in the region (box filter)
            int r_sum = 0, g_sum = 0, b_sum = 0, count = 0;
            for (int sy = sy0; sy < sy1 && sy < height; sy++) {
                for (int sx = sx0; sx < sx1 && sx < width; sx++) {
                    int idx = (sy * width + sx) * 3;
                    r_sum += img[idx + 0];
                    g_sum += img[idx + 1];
                    b_sum += img[idx + 2];
                    count++;
                }
            }

            // Convert to RGB565
            uint8_t r = (r_sum / count) >> 3;  // 5 bits
            uint8_t g = (g_sum / count) >> 2;  // 6 bits
            uint8_t b = (b_sum / count) >> 3;  // 5 bits
            uint16_t color = (r << 11) | (g << 5) | b;

            // Write to texture memory
            dut->tex_wr_addr = ty * TEX_SIZE + tx;
            dut->tex_wr_data = color;
            dut->tex_wr_en = 1;

            dut->clk = 1;
            dut->eval();
            sim_time++;
            dut->clk = 0;
            dut->eval();
            sim_time++;
        }
    }

    dut->tex_wr_en = 0;
    stbi_image_free(img);
    printf("Texture loaded (%d texels)\n\n", TEX_SIZE * TEX_SIZE);
    return true;
}

// Load a checkerboard texture (fallback)
void load_checkerboard_texture(Vrasterizer_top* dut, int check_size, uint64_t& sim_time) {
    printf("Loading %dx%d checkerboard texture (check size %d)...\n", TEX_SIZE, TEX_SIZE, check_size);

    for (int y = 0; y < TEX_SIZE; y++) {
        for (int x = 0; x < TEX_SIZE; x++) {
            int cx = x / check_size;
            int cy = y / check_size;
            // Alternate between white and blue
            uint16_t color = ((cx + cy) % 2 == 0) ? 0xFFFF : 0x001F;

            dut->tex_wr_addr = y * TEX_SIZE + x;
            dut->tex_wr_data = color;
            dut->tex_wr_en = 1;

            // Clock cycle for write
            dut->clk = 1;
            dut->eval();
            sim_time++;
            dut->clk = 0;
            dut->eval();
            sim_time++;
        }
    }
    dut->tex_wr_en = 0;
    printf("Texture loaded (%d texels)\n\n", TEX_SIZE * TEX_SIZE);
}

// Clear the depth buffer by pulsing depth_clear
void clear_depth_buffer(Vrasterizer_top* dut, uint16_t clear_value, uint64_t& sim_time) {
    dut->depth_clear_value = clear_value;

    // Hold depth_clear high for the entire duration (don't rely on clearing signal)
    // The depth buffer is 128x128 = 16384 entries
    int clear_cycles = DB_SIZE * DB_SIZE + 10;

    dut->depth_clear = 1;

    for (int i = 0; i < clear_cycles; i++) {
        dut->clk = 1;
        dut->eval();
        sim_time++;
        dut->clk = 0;
        dut->eval();
        sim_time++;
    }

    dut->depth_clear = 0;

    // A few extra cycles to settle
    for (int i = 0; i < 5; i++) {
        dut->clk = 1;
        dut->eval();
        sim_time++;
        dut->clk = 0;
        dut->eval();
        sim_time++;
    }

    printf("  Debug: Depth clear to 0x%04X, ran %d cycles\n", clear_value, clear_cycles);
}

// Render a scene with current filter settings
void render_scene(Vrasterizer_top* dut, Triangle* triangles, int num_triangles,
                  uint64_t& sim_time, int& total_fragments) {
    int current_triangle = 0;
    bool triangle_submitted = false;
    bool waiting_for_done = false;
    int drain_cycles = 0;
    int submit_delay = 0;

    int max_cycles = 2000000;
    for (int cycle = 0; cycle < max_cycles; cycle++) {
        // Rising edge
        dut->clk = 1;
        dut->eval();
        sim_time++;

        // Count fragments (pixels are written to hardware framebuffer automatically)
        if (dut->frag_valid) {
            total_fragments++;
        }

        // Triangle submission state machine
        if (current_triangle < num_triangles) {
            if (!triangle_submitted && !waiting_for_done) {
                if (dut->tri_ready && submit_delay > 5) {
                    load_triangle(dut, triangles[current_triangle]);
                    printf("  [%d] %s\n", current_triangle, triangles[current_triangle].name);
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
                if (!dut->busy) {
                    drain_cycles++;
                    if (drain_cycles > 25) {
                        current_triangle++;
                        waiting_for_done = false;
                        drain_cycles = 0;
                        submit_delay = 0;
                    }
                }
            }
        } else {
            break;
        }

        // Falling edge
        dut->clk = 0;
        dut->eval();
        sim_time++;
    }
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    // Create DUT instance
    Vrasterizer_top* dut = new Vrasterizer_top;

    // Initialize
    dut->clk = 0;
    dut->rst_n = 0;
    dut->tri_valid = 0;
    dut->frag_ready = 1;

    // Texture control
    dut->tex_enable = 1;
    dut->modulate_enable = 1;
    dut->tex_filter_bilinear = 0;
    dut->tex_wr_en = 0;
    dut->tex_wr_addr = 0;
    dut->tex_wr_data = 0;

    // Depth buffer control
    dut->depth_test_enable = 0;   // Start with depth test disabled
    dut->depth_write_enable = 0;
    dut->depth_func = GR_CMP_LESS;
    dut->depth_clear = 0;
    dut->depth_clear_value = 0xFFFF;  // Far plane

    // Framebuffer control
    dut->fb_clear = 0;
    dut->fb_clear_color = 0x0000;
    dut->fb_read_x = 0;
    dut->fb_read_y = 0;
    dut->fb_read_en = 0;

    // Reset sequence
    uint64_t sim_time = 0;
    for (int i = 0; i < 10; i++) {
        dut->clk = !dut->clk;
        dut->eval();
        sim_time++;
    }
    dut->rst_n = 1;

    printf("==============================================\n");
    printf("Celery3D Rasterizer - Filter Comparison\n");
    printf("==============================================\n");
    printf("Screen: %dx%d, Texture: %dx%d\n\n", SCREEN_WIDTH, SCREEN_HEIGHT, TEX_SIZE, TEX_SIZE);

    // Load texture
    if (!load_png_texture(dut, "sim/textures/leaves.png", sim_time)) {
        printf("Falling back to checkerboard texture...\n");
        load_checkerboard_texture(dut, 8, sim_time);
    }

    // Define test triangles
    Triangle triangles[4];

    triangles[0].v[0] = {100.0f, 50.0f, 0.5f, 0.0f, 0.0f, 1.0f, 1.0f, 1.0f};
    triangles[0].v[1] = {100.0f, 300.0f, 0.5f, 0.0f, 2.0f, 1.0f, 1.0f, 1.0f};
    triangles[0].v[2] = {400.0f, 300.0f, 0.5f, 2.0f, 2.0f, 1.0f, 1.0f, 1.0f};
    triangles[0].name = "Textured quad (lower-left tri)";

    triangles[1].v[0] = {100.0f, 50.0f, 0.5f, 0.0f, 0.0f, 1.0f, 1.0f, 1.0f};
    triangles[1].v[1] = {400.0f, 300.0f, 0.5f, 2.0f, 2.0f, 1.0f, 1.0f, 1.0f};
    triangles[1].v[2] = {400.0f, 50.0f, 0.5f, 2.0f, 0.0f, 1.0f, 1.0f, 1.0f};
    triangles[1].name = "Textured quad (upper-right tri)";

    triangles[2].v[0] = {480.0f, 80.0f, 0.5f, 0.5f, 0.0f, 1.0f, 0.3f, 0.3f};
    triangles[2].v[1] = {420.0f, 280.0f, 0.5f, 0.0f, 1.0f, 0.3f, 1.0f, 0.3f};
    triangles[2].v[2] = {580.0f, 280.0f, 0.5f, 1.0f, 1.0f, 0.3f, 0.3f, 1.0f};
    triangles[2].name = "RGB triangle (texture modulated)";

    triangles[3].v[0] = {450.0f, 320.0f, 0.5f, 0.0f, 0.0f, 1.0f, 1.0f, 0.2f};
    triangles[3].v[1] = {420.0f, 450.0f, 0.5f, 0.0f, 1.0f, 0.8f, 0.8f, 0.1f};
    triangles[3].v[2] = {580.0f, 400.0f, 0.5f, 1.0f, 0.5f, 1.0f, 0.9f, 0.0f};
    triangles[3].name = "Yellow triangle (texture modulated)";

    const int num_triangles = 4;

    // ==================== NEAREST NEIGHBOR ====================
    printf("----------------------------------------------\n");
    printf("Pass 1: NEAREST NEIGHBOR filtering\n");
    printf("----------------------------------------------\n");

    clear_hw_framebuffer(dut, pack_rgb565(0.05f, 0.05f, 0.15f), sim_time);
    dut->tex_filter_bilinear = 0;  // Nearest neighbor

    int nearest_fragments = 0;
    render_scene(dut, triangles, num_triangles, sim_time, nearest_fragments);

    read_hw_framebuffer(dut, sim_time);
    save_ppm("output_nearest.ppm");
    printf("  Fragments: %d\n", nearest_fragments);
    printf("  Saved: output_nearest.ppm\n\n");

    // ==================== BILINEAR ====================
    printf("----------------------------------------------\n");
    printf("Pass 2: BILINEAR filtering\n");
    printf("----------------------------------------------\n");

    clear_hw_framebuffer(dut, pack_rgb565(0.05f, 0.05f, 0.15f), sim_time);
    dut->tex_filter_bilinear = 1;  // Bilinear

    int bilinear_fragments = 0;
    render_scene(dut, triangles, num_triangles, sim_time, bilinear_fragments);

    read_hw_framebuffer(dut, sim_time);
    save_ppm("output_bilinear.ppm");
    printf("  Fragments: %d\n", bilinear_fragments);
    printf("  Saved: output_bilinear.ppm\n\n");

    // ==================== DEPTH BUFFER TEST ====================
    // Test with overlapping triangles at different depths
    // Triangles are positioned within the 128x128 depth buffer area
    printf("----------------------------------------------\n");
    printf("Pass 3: DEPTH BUFFER test (GR_CMP_LESS)\n");
    printf("----------------------------------------------\n");

    // Define overlapping triangles at different depths
    Triangle depth_triangles[2];

    // Front triangle (closer, z=0.3) - RED
    // Position within depth buffer bounds (0-127)
    depth_triangles[0].v[0] = {20.0f, 20.0f, 0.3f, 0.0f, 0.0f, 1.0f, 0.2f, 0.2f};
    depth_triangles[0].v[1] = {20.0f, 100.0f, 0.3f, 0.0f, 1.0f, 1.0f, 0.2f, 0.2f};
    depth_triangles[0].v[2] = {100.0f, 60.0f, 0.3f, 1.0f, 0.5f, 1.0f, 0.2f, 0.2f};
    depth_triangles[0].name = "Front triangle (RED, z=0.3)";

    // Back triangle (farther, z=0.7) - BLUE (rendered second)
    depth_triangles[1].v[0] = {40.0f, 10.0f, 0.7f, 0.0f, 0.0f, 0.2f, 0.2f, 1.0f};
    depth_triangles[1].v[1] = {40.0f, 110.0f, 0.7f, 0.0f, 1.0f, 0.2f, 0.2f, 1.0f};
    depth_triangles[1].v[2] = {120.0f, 60.0f, 0.7f, 1.0f, 0.5f, 0.2f, 0.2f, 1.0f};
    depth_triangles[1].name = "Back triangle (BLUE, z=0.7)";

    printf("  Debug: z=0.3 -> fp=0x%08X, z=0.7 -> fp=0x%08X\n",
           float_to_fp(0.3f), float_to_fp(0.7f));
    printf("  Debug: depth16 from 0.3 = 0x%04X, from 0.7 = 0x%04X\n",
           float_to_fp(0.3f) & 0xFFFF, float_to_fp(0.7f) & 0xFFFF);

    // Enable depth testing with GR_CMP_LESS
    dut->tex_enable = 0;  // Disable texture for clarity
    dut->depth_test_enable = 1;
    dut->depth_write_enable = 1;
    dut->depth_func = GR_CMP_LESS;

    // Clear framebuffer and depth buffer
    clear_hw_framebuffer(dut, pack_rgb565(0.1f, 0.1f, 0.1f), sim_time);
    clear_depth_buffer(dut, 0xFFFF, sim_time);  // Clear to far plane

    int depth_less_fragments = 0;
    render_scene(dut, depth_triangles, 2, sim_time, depth_less_fragments);

    read_hw_framebuffer(dut, sim_time);
    save_ppm("output_depth_less.ppm");
    printf("  Fragments: %d\n", depth_less_fragments);
    printf("  Expected: Blue occluded by red where they overlap\n");
    printf("  Saved: output_depth_less.ppm\n\n");

    // ==================== DEPTH DISABLED TEST ====================
    printf("----------------------------------------------\n");
    printf("Pass 4: DEPTH TEST DISABLED (painter's order)\n");
    printf("----------------------------------------------\n");

    dut->depth_test_enable = 0;
    dut->depth_write_enable = 0;

    clear_hw_framebuffer(dut, pack_rgb565(0.1f, 0.1f, 0.1f), sim_time);

    int no_depth_fragments = 0;
    render_scene(dut, depth_triangles, 2, sim_time, no_depth_fragments);

    read_hw_framebuffer(dut, sim_time);
    save_ppm("output_depth_disabled.ppm");
    printf("  Fragments: %d\n", no_depth_fragments);
    printf("  Expected: Blue drawn on top (painter's algorithm)\n");
    printf("  Saved: output_depth_disabled.ppm\n\n");

    // ==================== DEPTH GR_CMP_GREATER TEST ====================
    printf("----------------------------------------------\n");
    printf("Pass 5: DEPTH BUFFER test (GR_CMP_GREATER)\n");
    printf("----------------------------------------------\n");

    dut->depth_test_enable = 1;
    dut->depth_write_enable = 1;
    dut->depth_func = GR_CMP_GREATER;

    clear_hw_framebuffer(dut, pack_rgb565(0.1f, 0.1f, 0.1f), sim_time);
    clear_depth_buffer(dut, 0x0000, sim_time);  // Clear to near plane

    int depth_greater_fragments = 0;
    render_scene(dut, depth_triangles, 2, sim_time, depth_greater_fragments);

    read_hw_framebuffer(dut, sim_time);
    save_ppm("output_depth_greater.ppm");
    printf("  Fragments: %d\n", depth_greater_fragments);
    printf("  Expected: All fragments pass (reverse depth: farther overwrites closer)\n");
    printf("  Saved: output_depth_greater.ppm\n\n");

    // ==================== SUMMARY ====================
    printf("==============================================\n");
    printf("All tests complete!\n");
    printf("==============================================\n");
    printf("Texture filtering:\n");
    printf("  Nearest neighbor: output_nearest.ppm\n");
    printf("  Bilinear filter:  output_bilinear.ppm\n");
    printf("\nDepth buffer:\n");
    printf("  GR_CMP_LESS:     output_depth_less.ppm\n");
    printf("  Depth disabled:  output_depth_disabled.ppm\n");
    printf("  GR_CMP_GREATER:  output_depth_greater.ppm\n");
    printf("\nCompare the depth outputs to verify occlusion works.\n");

    delete dut;
    return 0;
}
