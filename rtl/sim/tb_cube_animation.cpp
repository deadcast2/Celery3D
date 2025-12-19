// Celery3D GPU - 3D Cube Animation Testbench
// Renders a rotating cube using the RTL rasterizer
// Outputs numbered PPM frames that can be combined into an animated GIF

#include <verilated.h>
#include "Vrasterizer_top.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cmath>

// Resolution (64x64 for simulation, fits in BRAM)
#define SCREEN_WIDTH 64
#define SCREEN_HEIGHT 64
#define FP_FRAC_BITS 16

// Number of frames for animation (60 = ~one full rotation)
#define NUM_FRAMES 60

// Depth comparison functions
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

// ============================================================================
// 3D Math Library (ported from reference renderer)
// ============================================================================

struct Vec3 {
    float x, y, z;
};

struct Vec4 {
    float x, y, z, w;
};

struct Mat4 {
    float m[4][4];
};

Mat4 mat4_identity() {
    Mat4 result = {{{0}}};
    result.m[0][0] = 1.0f;
    result.m[1][1] = 1.0f;
    result.m[2][2] = 1.0f;
    result.m[3][3] = 1.0f;
    return result;
}

Mat4 mat4_multiply(Mat4 a, Mat4 b) {
    Mat4 result = {{{0}}};
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            for (int k = 0; k < 4; k++) {
                result.m[i][j] += a.m[i][k] * b.m[k][j];
            }
        }
    }
    return result;
}

Vec4 mat4_transform(Mat4 m, Vec4 v) {
    Vec4 result;
    result.x = m.m[0][0] * v.x + m.m[0][1] * v.y + m.m[0][2] * v.z + m.m[0][3] * v.w;
    result.y = m.m[1][0] * v.x + m.m[1][1] * v.y + m.m[1][2] * v.z + m.m[1][3] * v.w;
    result.z = m.m[2][0] * v.x + m.m[2][1] * v.y + m.m[2][2] * v.z + m.m[2][3] * v.w;
    result.w = m.m[3][0] * v.x + m.m[3][1] * v.y + m.m[3][2] * v.z + m.m[3][3] * v.w;
    return result;
}

Mat4 mat4_perspective(float fov_y, float aspect, float near_plane, float far_plane) {
    Mat4 m = {{{0}}};
    float tan_half_fov = tanf(fov_y / 2.0f);

    m.m[0][0] = 1.0f / (aspect * tan_half_fov);
    m.m[1][1] = 1.0f / tan_half_fov;
    m.m[2][2] = -(far_plane + near_plane) / (far_plane - near_plane);
    m.m[2][3] = -(2.0f * far_plane * near_plane) / (far_plane - near_plane);
    m.m[3][2] = -1.0f;

    return m;
}

float vec3_dot(Vec3 a, Vec3 b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

Vec3 vec3_sub(Vec3 a, Vec3 b) {
    return {a.x - b.x, a.y - b.y, a.z - b.z};
}

Vec3 vec3_cross(Vec3 a, Vec3 b) {
    return {
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    };
}

Vec3 vec3_scale(Vec3 v, float s) {
    return {v.x * s, v.y * s, v.z * s};
}

float vec3_length(Vec3 v) {
    return sqrtf(vec3_dot(v, v));
}

Vec3 vec3_normalize(Vec3 v) {
    float len = vec3_length(v);
    if (len > 0.0001f) {
        return vec3_scale(v, 1.0f / len);
    }
    return v;
}

Mat4 mat4_look_at(Vec3 eye, Vec3 target, Vec3 up) {
    Vec3 f = vec3_normalize(vec3_sub(target, eye));
    Vec3 r = vec3_normalize(vec3_cross(f, up));
    Vec3 u = vec3_cross(r, f);

    Mat4 m = mat4_identity();
    m.m[0][0] = r.x;  m.m[0][1] = r.y;  m.m[0][2] = r.z;
    m.m[1][0] = u.x;  m.m[1][1] = u.y;  m.m[1][2] = u.z;
    m.m[2][0] = -f.x; m.m[2][1] = -f.y; m.m[2][2] = -f.z;

    m.m[0][3] = -vec3_dot(r, eye);
    m.m[1][3] = -vec3_dot(u, eye);
    m.m[2][3] = vec3_dot(f, eye);

    return m;
}

Mat4 mat4_rotate_x(float angle) {
    Mat4 m = mat4_identity();
    float c = cosf(angle);
    float s = sinf(angle);
    m.m[1][1] = c;  m.m[1][2] = -s;
    m.m[2][1] = s;  m.m[2][2] = c;
    return m;
}

Mat4 mat4_rotate_y(float angle) {
    Mat4 m = mat4_identity();
    float c = cosf(angle);
    float s = sinf(angle);
    m.m[0][0] = c;  m.m[0][2] = s;
    m.m[2][0] = -s; m.m[2][2] = c;
    return m;
}

// ============================================================================
// Cube Geometry (same as reference renderer)
// ============================================================================

// Cube vertex positions (8 unique vertices, but 24 for separate face normals)
static const Vec3 cube_positions[] = {
    // Front face
    {-1, -1,  1}, { 1, -1,  1}, { 1,  1,  1}, {-1,  1,  1},
    // Back face
    { 1, -1, -1}, {-1, -1, -1}, {-1,  1, -1}, { 1,  1, -1},
    // Top face
    {-1,  1,  1}, { 1,  1,  1}, { 1,  1, -1}, {-1,  1, -1},
    // Bottom face
    {-1, -1, -1}, { 1, -1, -1}, { 1, -1,  1}, {-1, -1,  1},
    // Right face
    { 1, -1,  1}, { 1, -1, -1}, { 1,  1, -1}, { 1,  1,  1},
    // Left face
    {-1, -1, -1}, {-1, -1,  1}, {-1,  1,  1}, {-1,  1, -1},
};

// UV coordinates for texture mapping
static const float cube_uvs[] = {
    0, 1,  1, 1,  1, 0,  0, 0,  // Front
    0, 1,  1, 1,  1, 0,  0, 0,  // Back
    0, 1,  1, 1,  1, 0,  0, 0,  // Top
    0, 1,  1, 1,  1, 0,  0, 0,  // Bottom
    0, 1,  1, 1,  1, 0,  0, 0,  // Right
    0, 1,  1, 1,  1, 0,  0, 0,  // Left
};

// Face colors (Gouraud shading)
static const Vec3 face_colors[] = {
    {1.0f, 0.8f, 0.8f},  // Front - light red
    {0.8f, 1.0f, 0.8f},  // Back - light green
    {0.8f, 0.8f, 1.0f},  // Top - light blue
    {1.0f, 1.0f, 0.8f},  // Bottom - light yellow
    {1.0f, 0.8f, 1.0f},  // Right - light magenta
    {0.8f, 1.0f, 1.0f},  // Left - light cyan
};

// Triangle indices (2 triangles per face, 12 total)
static const int cube_indices[] = {
    0, 1, 2,  0, 2, 3,      // Front
    4, 5, 6,  4, 6, 7,      // Back
    8, 9, 10, 8, 10, 11,    // Top
    12, 13, 14, 12, 14, 15, // Bottom
    16, 17, 18, 16, 18, 19, // Right
    20, 21, 22, 20, 22, 23, // Left
};

// ============================================================================
// Rasterizer Interface
// ============================================================================

// RGB565 framebuffer
uint16_t framebuffer[SCREEN_WIDTH * SCREEN_HEIGHT];

// Fixed-point conversion
int32_t float_to_fp(float f) {
    return (int32_t)(f * (1 << FP_FRAC_BITS));
}

// Pack float RGB to RGB565
uint16_t pack_rgb565(float r, float g, float b) {
    uint8_t ri = (uint8_t)(fminf(r, 1.0f) * 31);
    uint8_t gi = (uint8_t)(fminf(g, 1.0f) * 63);
    uint8_t bi = (uint8_t)(fminf(b, 1.0f) * 31);
    return (ri << 11) | (gi << 5) | bi;
}

// Convert RGB565 to 24-bit RGB for PPM output
void rgb565_to_rgb888(uint16_t c, uint8_t* r, uint8_t* g, uint8_t* b) {
    *r = ((c >> 11) & 0x1F) << 3;
    *g = ((c >> 5) & 0x3F) << 2;
    *b = (c & 0x1F) << 3;
}

// Save framebuffer as PPM with numbered filename
void save_ppm(const char* prefix, int frame_num) {
    char filename[256];
    snprintf(filename, sizeof(filename), "%s_%03d.ppm", prefix, frame_num);

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
}

// Set vertex data on the DUT
void set_vertex(Vrasterizer_top* dut, int idx, float x, float y, float z, float w,
                float u, float v, float r, float g, float b) {
    int32_t fp_x = float_to_fp(x);
    int32_t fp_y = float_to_fp(y);
    int32_t fp_z = float_to_fp(z);
    int32_t fp_w = float_to_fp(w);  // 1/clip.w for perspective correction
    int32_t fp_u = float_to_fp(u);
    int32_t fp_v = float_to_fp(v);
    int32_t fp_r = float_to_fp(r);
    int32_t fp_g = float_to_fp(g);
    int32_t fp_b = float_to_fp(b);
    int32_t fp_a = float_to_fp(1.0f);

    uint32_t* vptr;
    if (idx == 0) vptr = dut->v0;
    else if (idx == 1) vptr = dut->v1;
    else vptr = dut->v2;

    // Pack into Verilator's word array (LSB-first ordering)
    vptr[0] = (uint32_t)fp_a;
    vptr[1] = (uint32_t)fp_b;
    vptr[2] = (uint32_t)fp_g;
    vptr[3] = (uint32_t)fp_r;
    vptr[4] = (uint32_t)fp_v;
    vptr[5] = (uint32_t)fp_u;
    vptr[6] = (uint32_t)fp_w;
    vptr[7] = (uint32_t)fp_z;
    vptr[8] = (uint32_t)fp_y;
    vptr[9] = (uint32_t)fp_x;
}

// Clear hardware framebuffer
void clear_hw_framebuffer(Vrasterizer_top* dut, uint16_t color, uint64_t& sim_time) {
    dut->fb_clear_color = color;
    dut->fb_clear = 1;

    for (int i = 0; i < 5; i++) {
        dut->clk = 1; dut->eval(); sim_time++;
        dut->clk = 0; dut->eval(); sim_time++;
    }

    int clear_cycles = SCREEN_WIDTH * SCREEN_HEIGHT + 100;
    for (int i = 0; i < clear_cycles; i++) {
        dut->clk = 1; dut->eval(); sim_time++;
        dut->clk = 0; dut->eval(); sim_time++;
        if (!dut->fb_clearing && i > 10) break;
    }

    dut->fb_clear = 0;

    for (int i = 0; i < 5; i++) {
        dut->clk = 1; dut->eval(); sim_time++;
        dut->clk = 0; dut->eval(); sim_time++;
    }
}

// Clear depth buffer
void clear_depth_buffer(Vrasterizer_top* dut, uint16_t clear_value, uint64_t& sim_time) {
    dut->depth_clear_value = clear_value;
    dut->depth_clear = 1;

    int clear_cycles = SCREEN_WIDTH * SCREEN_HEIGHT + 10;
    for (int i = 0; i < clear_cycles; i++) {
        dut->clk = 1; dut->eval(); sim_time++;
        dut->clk = 0; dut->eval(); sim_time++;
    }

    dut->depth_clear = 0;

    for (int i = 0; i < 5; i++) {
        dut->clk = 1; dut->eval(); sim_time++;
        dut->clk = 0; dut->eval(); sim_time++;
    }
}

// Read hardware framebuffer into software buffer
void read_hw_framebuffer(Vrasterizer_top* dut, uint64_t& sim_time) {
    for (int y = 0; y < SCREEN_HEIGHT; y++) {
        for (int x = 0; x < SCREEN_WIDTH; x++) {
            dut->fb_read_x = x;
            dut->fb_read_y = y;
            dut->fb_read_en = 1;

            dut->clk = 1; dut->eval(); sim_time++;
            dut->clk = 0; dut->eval(); sim_time++;

            dut->fb_read_en = 0;

            dut->clk = 1; dut->eval(); sim_time++;
            dut->clk = 0; dut->eval(); sim_time++;

            dut->clk = 1; dut->eval(); sim_time++;
            dut->clk = 0; dut->eval(); sim_time++;

            framebuffer[y * SCREEN_WIDTH + x] = dut->fb_read_data;
        }
    }
}

// Transform a 3D vertex to screen space
struct ScreenVertex {
    float x, y, z;
    float w;  // 1/clip.w for perspective correction
    float u, v;
    float r, g, b;
};

ScreenVertex transform_vertex(Vec3 pos, float u, float v, Vec3 color, Mat4 mvp) {
    Vec4 clip = mat4_transform(mvp, {pos.x, pos.y, pos.z, 1.0f});

    // Perspective divide
    float inv_w = 1.0f / clip.w;
    float ndc_x = clip.x * inv_w;
    float ndc_y = clip.y * inv_w;
    float ndc_z = clip.z * inv_w;

    // NDC to screen coordinates
    ScreenVertex vert;
    vert.x = (ndc_x + 1.0f) * 0.5f * SCREEN_WIDTH;
    vert.y = (1.0f - ndc_y) * 0.5f * SCREEN_HEIGHT;  // Flip Y
    vert.z = (ndc_z + 1.0f) * 0.5f;  // Map to [0, 1]
    // Use 1/clip.w for perspective-correct interpolation
    // Scale up to keep values in a range the fixed-point RTL handles well
    vert.w = inv_w * 16.0f;
    vert.u = u;
    vert.v = v;
    vert.r = color.x;
    vert.g = color.y;
    vert.b = color.z;

    return vert;
}

// Render one triangle through the RTL (exactly matches original testbench pattern)
void render_triangle(Vrasterizer_top* dut, ScreenVertex v0, ScreenVertex v1, ScreenVertex v2, uint64_t& sim_time, bool debug = false) {
    if (debug) {
        printf("    Triangle: (%.1f,%.1f,%.3f) (%.1f,%.1f,%.3f) (%.1f,%.1f,%.3f)\n",
               v0.x, v0.y, v0.z, v1.x, v1.y, v1.z, v2.x, v2.y, v2.z);
    }

    bool triangle_submitted = false;
    bool waiting_for_done = false;
    int drain_cycles = 0;
    int submit_delay = 0;

    for (int cycle = 0; cycle < 200000; cycle++) {
        // Rising edge
        dut->clk = 1;
        dut->eval();
        sim_time++;

        // Triangle submission state machine (same as original testbench)
        if (!triangle_submitted && !waiting_for_done) {
            if (dut->tri_ready && submit_delay > 5) {
                // Set vertices AND tri_valid in same cycle (before falling edge)
                set_vertex(dut, 0, v0.x, v0.y, v0.z, v0.w, v0.u, v0.v, v0.r, v0.g, v0.b);
                set_vertex(dut, 1, v1.x, v1.y, v1.z, v1.w, v1.u, v1.v, v1.r, v1.g, v1.b);
                set_vertex(dut, 2, v2.x, v2.y, v2.z, v2.w, v2.u, v2.v, v2.r, v2.g, v2.b);
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
                    // Done with this triangle
                    break;
                }
            }
        }

        // Falling edge
        dut->clk = 0;
        dut->eval();
        sim_time++;
    }
}

// Render the cube for one frame
void render_cube(Vrasterizer_top* dut, Mat4 mvp, uint64_t& sim_time, bool debug = false) {
    for (int i = 0; i < 36; i += 3) {
        int face = i / 6;
        Vec3 color = face_colors[face];

        int i0 = cube_indices[i];
        int i1 = cube_indices[i + 1];
        int i2 = cube_indices[i + 2];

        ScreenVertex v0 = transform_vertex(cube_positions[i0],
                                           cube_uvs[i0 * 2], cube_uvs[i0 * 2 + 1],
                                           color, mvp);
        ScreenVertex v1 = transform_vertex(cube_positions[i1],
                                           cube_uvs[i1 * 2], cube_uvs[i1 * 2 + 1],
                                           color, mvp);
        ScreenVertex v2 = transform_vertex(cube_positions[i2],
                                           cube_uvs[i2 * 2], cube_uvs[i2 * 2 + 1],
                                           color, mvp);

        // Try original order (v0, v1, v2)
        render_triangle(dut, v0, v1, v2, sim_time, debug);
    }
}

// Load checkerboard texture
void load_checkerboard_texture(Vrasterizer_top* dut, uint64_t& sim_time) {
    const int check_size = 8;

    for (int y = 0; y < 64; y++) {
        for (int x = 0; x < 64; x++) {
            int cx = x / check_size;
            int cy = y / check_size;
            // White and gray checkerboard
            uint16_t color = ((cx + cy) % 2 == 0) ? 0xFFFF : 0x8410;

            dut->tex_wr_addr = y * 64 + x;
            dut->tex_wr_data = color;
            dut->tex_wr_en = 1;

            dut->clk = 1; dut->eval(); sim_time++;
            dut->clk = 0; dut->eval(); sim_time++;
        }
    }
    dut->tex_wr_en = 0;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    // Create DUT instance
    Vrasterizer_top* dut = new Vrasterizer_top;

    // Initialize signals
    dut->clk = 0;
    dut->rst_n = 0;
    dut->tri_valid = 0;
    dut->frag_ready = 1;

    // Texture settings (Gouraud shading with texture modulation)
    dut->tex_enable = 1;
    dut->modulate_enable = 1;
    dut->tex_filter_bilinear = 1;
    dut->tex_wr_en = 0;
    dut->tex_format_rgba4444 = 0;

    // Depth buffer settings
    dut->depth_test_enable = 1;
    dut->depth_write_enable = 1;
    dut->depth_func = GR_CMP_LESS;
    dut->depth_clear = 0;
    dut->depth_clear_value = 0xFFFF;

    // Blending disabled (opaque rendering)
    dut->blend_enable = 0;
    dut->blend_src_factor = 0;
    dut->blend_dst_factor = 0;
    dut->blend_alpha_source = 0;
    dut->blend_constant_alpha = 0xFF;

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
    printf("Celery3D - 3D Cube Animation\n");
    printf("==============================================\n");
    printf("Resolution: %dx%d\n", SCREEN_WIDTH, SCREEN_HEIGHT);
    printf("Frames: %d\n\n", NUM_FRAMES);

    // Load texture
    printf("Loading checkerboard texture...\n");
    load_checkerboard_texture(dut, sim_time);

    // Setup projection matrix (60 degree FOV)
    float aspect = (float)SCREEN_WIDTH / (float)SCREEN_HEIGHT;
    Mat4 proj = mat4_perspective(60.0f * 3.14159f / 180.0f, aspect, 0.1f, 100.0f);

    // Setup view matrix (camera at [0, 2, 5] looking at origin)
    Vec3 eye = {0, 2, 5};
    Vec3 target = {0, 0, 0};
    Vec3 up = {0, 1, 0};
    Mat4 view = mat4_look_at(eye, target, up);

    // Background color (dark blue)
    uint16_t bg_color = pack_rgb565(0.1f, 0.1f, 0.25f);

    // First, test with a simple hardcoded triangle to verify pipeline works
    // Use the exact same triangle as original testbench triangles[2] (RGB triangle)
    printf("Testing simple triangle...\n");
    clear_hw_framebuffer(dut, bg_color, sim_time);

    // RGB triangle from original testbench (z=0.5, so w=1/(0.5+0.001)≈1.996)
    float test_z = 0.5f;
    float test_w = 1.0f / (test_z + 0.001f);  // Same formula as original
    ScreenVertex test_v0 = {48.0f, 8.0f, test_z, test_w, 0.5f, 0.0f, 1.0f, 0.3f, 0.3f};
    ScreenVertex test_v1 = {42.0f, 28.0f, test_z, test_w, 0.0f, 1.0f, 0.3f, 1.0f, 0.3f};
    ScreenVertex test_v2 = {58.0f, 28.0f, test_z, test_w, 1.0f, 1.0f, 0.3f, 0.3f, 1.0f};
    printf("  Test triangle: (%.1f,%.1f,%.3f,w=%.3f) (%.1f,%.1f) (%.1f,%.1f)\n",
           test_v0.x, test_v0.y, test_v0.z, test_v0.w, test_v1.x, test_v1.y, test_v2.x, test_v2.y);
    render_triangle(dut, test_v0, test_v1, test_v2, sim_time, false);

    read_hw_framebuffer(dut, sim_time);
    save_ppm("test_triangle", 0);
    printf("  Saved: test_triangle_000.ppm\n\n");

    // Render animation frames
    printf("Rendering %d frames...\n", NUM_FRAMES);
    for (int frame = 0; frame < NUM_FRAMES; frame++) {
        // Calculate rotation angle (full rotation over NUM_FRAMES)
        float angle = (float)frame / NUM_FRAMES * 2.0f * 3.14159f;

        // Create model matrix (rotation around Y and X axes)
        Mat4 model = mat4_multiply(mat4_rotate_y(angle),
                                   mat4_rotate_x(angle * 0.7f));

        // Create MVP matrix
        Mat4 mv = mat4_multiply(view, model);
        Mat4 mvp = mat4_multiply(proj, mv);

        // Clear framebuffer and depth buffer
        clear_hw_framebuffer(dut, bg_color, sim_time);
        clear_depth_buffer(dut, 0xFFFF, sim_time);

        // Render the cube (debug output on first frame)
        bool debug = (frame == 0);
        if (debug) printf("  Debug: Triangle coordinates for frame 0:\n");
        render_cube(dut, mvp, sim_time, debug);

        // Read back and save frame
        read_hw_framebuffer(dut, sim_time);
        save_ppm("frame", frame);

        printf("  Frame %d/%d\n", frame + 1, NUM_FRAMES);
    }

    printf("\n==============================================\n");
    printf("Animation complete!\n");
    printf("==============================================\n");
    printf("Output: frame_000.ppm through frame_%03d.ppm\n", NUM_FRAMES - 1);
    printf("\nTo create animated GIF:\n");
    printf("  convert -delay 3 -loop 0 frame_*.ppm cube_animation.gif\n");
    printf("\nTo create MP4 video:\n");
    printf("  ffmpeg -framerate 30 -i frame_%%03d.ppm -c:v libx264 -pix_fmt yuv420p cube.mp4\n");

    delete dut;
    return 0;
}
