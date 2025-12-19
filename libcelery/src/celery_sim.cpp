/*
 * Celery3D Graphics Library - Simulation Backend
 *
 * Implements the celery.h API using the Verilator RTL simulation.
 * This allows testing the full graphics pipeline without hardware.
 *
 * Copyright (c) 2024 Celery3D Project
 * SPDX-License-Identifier: Apache-2.0
 */

#include "celery.h"
#include <verilated.h>
#include "Vrasterizer_top.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>

/* ============================================================================
 * Internal State
 * ============================================================================ */

static struct {
    bool initialized;
    int width;
    int height;

    Vrasterizer_top* dut;
    uint64_t sim_time;

    /* Render state */
    bool depth_test_enable;
    bool depth_write_enable;
    CeleryCmpFunc depth_func;

    bool blend_enable;
    CeleryBlendFactor blend_src;
    CeleryBlendFactor blend_dst;
    CeleryAlphaSource alpha_source;
    uint8_t constant_alpha;

    bool tex_enable;
    CeleryTexFilter tex_filter;
    CeleryTexFormat tex_format;
    bool tex_modulate;
    int tex_width;
    int tex_height;

    /* Software framebuffer for readback */
    uint16_t* framebuffer;
} ctx;

/* ============================================================================
 * Internal Helpers
 * ============================================================================ */

#define FP_FRAC_BITS 16

static int32_t float_to_fp(float f) {
    return (int32_t)(f * (1 << FP_FRAC_BITS));
}

static void clock_cycle(void) {
    ctx.dut->clk = 1;
    ctx.dut->eval();
    ctx.sim_time++;

    ctx.dut->clk = 0;
    ctx.dut->eval();
    ctx.sim_time++;
}

static void clock_cycles(int n) {
    for (int i = 0; i < n; i++) {
        clock_cycle();
    }
}

static void set_vertex(int idx, const CeleryVertex* v) {
    /*
     * Convert CeleryVertex to RTL vertex format.
     * RTL expects: x, y, z, w, u, v, r, g, b, a in fixed-point S15.16
     *
     * Note: CeleryVertex uses sow/tow (s/w, t/w) which is what the hardware
     * expects for perspective-correct interpolation.
     */
    int32_t fp_x = float_to_fp(v->x);
    int32_t fp_y = float_to_fp(v->y);
    int32_t fp_z = float_to_fp(v->z);
    int32_t fp_w = float_to_fp(v->oow);  /* 1/w for perspective correction */
    int32_t fp_u = float_to_fp(v->sow);  /* s/w texture coordinate */
    int32_t fp_v = float_to_fp(v->tow);  /* t/w texture coordinate */
    int32_t fp_r = float_to_fp(v->r);
    int32_t fp_g = float_to_fp(v->g);
    int32_t fp_b = float_to_fp(v->b);
    int32_t fp_a = float_to_fp(v->a);

    uint32_t* vptr;
    if (idx == 0) vptr = ctx.dut->v0;
    else if (idx == 1) vptr = ctx.dut->v1;
    else vptr = ctx.dut->v2;

    /* Pack into Verilator's word array (LSB-first ordering matches RTL struct) */
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

static void apply_render_state(void) {
    /* Depth state */
    ctx.dut->depth_test_enable = ctx.depth_test_enable ? 1 : 0;
    ctx.dut->depth_write_enable = ctx.depth_write_enable ? 1 : 0;
    ctx.dut->depth_func = (uint8_t)ctx.depth_func;

    /* Blend state */
    ctx.dut->blend_enable = ctx.blend_enable ? 1 : 0;
    ctx.dut->blend_src_factor = (uint8_t)ctx.blend_src;
    ctx.dut->blend_dst_factor = (uint8_t)ctx.blend_dst;
    ctx.dut->blend_alpha_source = (uint8_t)ctx.alpha_source;
    ctx.dut->blend_constant_alpha = ctx.constant_alpha;

    /* Texture state */
    ctx.dut->tex_enable = ctx.tex_enable ? 1 : 0;
    ctx.dut->tex_filter_bilinear = (ctx.tex_filter == CELERY_FILTER_BILINEAR) ? 1 : 0;
    ctx.dut->tex_format_rgba4444 = (ctx.tex_format == CELERY_TEXFMT_RGBA4444) ? 1 : 0;
    ctx.dut->modulate_enable = ctx.tex_modulate ? 1 : 0;
}

static void render_triangle_internal(const CeleryVertex* v0,
                                     const CeleryVertex* v1,
                                     const CeleryVertex* v2) {
    apply_render_state();

    bool triangle_submitted = false;
    bool waiting_for_done = false;
    int drain_cycles = 0;
    int submit_delay = 0;

    for (int cycle = 0; cycle < 200000; cycle++) {
        /* Rising edge */
        ctx.dut->clk = 1;
        ctx.dut->eval();
        ctx.sim_time++;

        /* Triangle submission state machine */
        if (!triangle_submitted && !waiting_for_done) {
            if (ctx.dut->tri_ready && submit_delay > 5) {
                set_vertex(0, v0);
                set_vertex(1, v1);
                set_vertex(2, v2);
                ctx.dut->tri_valid = 1;
                triangle_submitted = true;
            } else {
                submit_delay++;
            }
        } else if (triangle_submitted) {
            ctx.dut->tri_valid = 0;
            waiting_for_done = true;
            triangle_submitted = false;
        } else if (waiting_for_done) {
            if (!ctx.dut->busy) {
                drain_cycles++;
                if (drain_cycles > 25) {
                    break;
                }
            }
        }

        /* Falling edge */
        ctx.dut->clk = 0;
        ctx.dut->eval();
        ctx.sim_time++;
    }
}

static void read_hw_framebuffer(void) {
    for (int y = 0; y < ctx.height; y++) {
        for (int x = 0; x < ctx.width; x++) {
            ctx.dut->fb_read_x = x;
            ctx.dut->fb_read_y = y;
            ctx.dut->fb_read_en = 1;

            clock_cycle();
            ctx.dut->fb_read_en = 0;
            clock_cycles(2);

            ctx.framebuffer[y * ctx.width + x] = ctx.dut->fb_read_data;
        }
    }
}

static void save_ppm(const char* filename) {
    FILE* f = fopen(filename, "wb");
    if (!f) {
        fprintf(stderr, "celery: error opening %s for writing\n", filename);
        return;
    }

    fprintf(f, "P6\n%d %d\n255\n", ctx.width, ctx.height);

    for (int i = 0; i < ctx.width * ctx.height; i++) {
        uint16_t c = ctx.framebuffer[i];
        uint8_t r = ((c >> 11) & 0x1F) << 3;
        uint8_t g = ((c >> 5) & 0x3F) << 2;
        uint8_t b = (c & 0x1F) << 3;
        fputc(r, f);
        fputc(g, f);
        fputc(b, f);
    }

    fclose(f);
}

/* ============================================================================
 * Public API Implementation
 * ============================================================================ */

CeleryError celeryInit(CeleryBackend backend, int width, int height) {
    if (backend != CELERY_BACKEND_SIM) {
        fprintf(stderr, "celery: only simulation backend currently supported\n");
        return CELERY_ERR_BACKEND;
    }

    if (ctx.initialized) {
        celeryShutdown();
    }

    memset(&ctx, 0, sizeof(ctx));

    ctx.width = width;
    ctx.height = height;
    ctx.sim_time = 0;

    /* Allocate software framebuffer */
    ctx.framebuffer = (uint16_t*)calloc(width * height, sizeof(uint16_t));
    if (!ctx.framebuffer) {
        return CELERY_ERR_INIT;
    }

    /* Create Verilator DUT */
    ctx.dut = new Vrasterizer_top;
    if (!ctx.dut) {
        free(ctx.framebuffer);
        return CELERY_ERR_INIT;
    }

    /* Initialize signals */
    ctx.dut->clk = 0;
    ctx.dut->rst_n = 0;
    ctx.dut->tri_valid = 0;
    ctx.dut->frag_ready = 1;

    /* Default state */
    ctx.depth_test_enable = true;
    ctx.depth_write_enable = true;
    ctx.depth_func = CELERY_CMP_LESS;

    ctx.blend_enable = false;
    ctx.blend_src = CELERY_BLEND_ONE;
    ctx.blend_dst = CELERY_BLEND_ZERO;
    ctx.alpha_source = CELERY_ALPHA_ONE;
    ctx.constant_alpha = 0xFF;

    ctx.tex_enable = false;
    ctx.tex_filter = CELERY_FILTER_NEAREST;
    ctx.tex_format = CELERY_TEXFMT_RGB565;
    ctx.tex_modulate = true;
    ctx.tex_width = 64;
    ctx.tex_height = 64;

    /* Apply initial state to hardware */
    apply_render_state();

    ctx.dut->fb_clear = 0;
    ctx.dut->fb_clear_color = 0x0000;
    ctx.dut->fb_read_x = 0;
    ctx.dut->fb_read_y = 0;
    ctx.dut->fb_read_en = 0;

    ctx.dut->depth_clear = 0;
    ctx.dut->depth_clear_value = 0xFFFF;

    ctx.dut->tex_wr_en = 0;

    /* Reset sequence */
    clock_cycles(5);
    ctx.dut->rst_n = 1;
    clock_cycles(5);

    ctx.initialized = true;
    return CELERY_OK;
}

void celeryShutdown(void) {
    if (!ctx.initialized) return;

    if (ctx.dut) {
        ctx.dut->final();
        delete ctx.dut;
    }

    if (ctx.framebuffer) {
        free(ctx.framebuffer);
    }

    memset(&ctx, 0, sizeof(ctx));
}

int celeryGetWidth(void) {
    return ctx.width;
}

int celeryGetHeight(void) {
    return ctx.height;
}

/* Buffer Management */

void celeryClearColor(uint16_t color) {
    if (!ctx.initialized) return;

    ctx.dut->fb_clear_color = color;
    ctx.dut->fb_clear = 1;
    clock_cycles(5);

    int clear_cycles = ctx.width * ctx.height + 100;
    for (int i = 0; i < clear_cycles; i++) {
        clock_cycle();
        if (!ctx.dut->fb_clearing && i > 10) break;
    }

    ctx.dut->fb_clear = 0;
    clock_cycles(5);
}

void celeryClearColorRGB(float r, float g, float b) {
    celeryClearColor(celeryPackRGB565(r, g, b));
}

void celeryClearDepth(uint16_t depth) {
    if (!ctx.initialized) return;

    ctx.dut->depth_clear_value = depth;
    ctx.dut->depth_clear = 1;

    int clear_cycles = ctx.width * ctx.height + 10;
    for (int i = 0; i < clear_cycles; i++) {
        clock_cycle();
    }

    ctx.dut->depth_clear = 0;
    clock_cycles(5);
}

void celeryClearBuffers(uint16_t color, uint16_t depth) {
    celeryClearColor(color);
    celeryClearDepth(depth);
}

void celerySwapBuffers(const char* filename) {
    if (!ctx.initialized) return;

    read_hw_framebuffer();

    if (filename) {
        save_ppm(filename);
    }
}

/* Depth Buffer State */

void celeryDepthTest(bool enable) {
    ctx.depth_test_enable = enable;
}

void celeryDepthFunc(CeleryCmpFunc func) {
    ctx.depth_func = func;
}

void celeryDepthMask(bool enable) {
    ctx.depth_write_enable = enable;
}

/* Alpha Blending State */

void celeryBlendEnable(bool enable) {
    ctx.blend_enable = enable;
}

void celeryBlendFunc(CeleryBlendFactor srcFactor, CeleryBlendFactor dstFactor) {
    ctx.blend_src = srcFactor;
    ctx.blend_dst = dstFactor;
}

void celeryAlphaSource(CeleryAlphaSource source) {
    ctx.alpha_source = source;
}

void celeryConstantAlpha(uint8_t alpha) {
    ctx.constant_alpha = alpha;
}

/* Texture State */

CeleryError celeryTexImage(int width, int height, const uint16_t* data,
                           CeleryTexFormat format) {
    if (!ctx.initialized) return CELERY_ERR_NO_CONTEXT;
    if (!data) return CELERY_ERR_INVALID_ARG;
    if (width > CELERY_MAX_TEXTURE_SIZE || height > CELERY_MAX_TEXTURE_SIZE) {
        return CELERY_ERR_INVALID_ARG;
    }

    ctx.tex_width = width;
    ctx.tex_height = height;
    ctx.tex_format = format;

    /* Upload texture to hardware */
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            ctx.dut->tex_wr_addr = y * width + x;
            ctx.dut->tex_wr_data = data[y * width + x];
            ctx.dut->tex_wr_en = 1;
            clock_cycle();
        }
    }
    ctx.dut->tex_wr_en = 0;

    return CELERY_OK;
}

void celeryTexEnable(bool enable) {
    ctx.tex_enable = enable;
}

void celeryTexFilter(CeleryTexFilter filter) {
    ctx.tex_filter = filter;
}

void celeryTexModulate(bool enable) {
    ctx.tex_modulate = enable;
}

/* Drawing */

void celeryDrawTriangle(const CeleryVertex* v0,
                        const CeleryVertex* v1,
                        const CeleryVertex* v2) {
    if (!ctx.initialized) return;
    if (!v0 || !v1 || !v2) return;

    render_triangle_internal(v0, v1, v2);
}

void celeryDrawTriangles(const CeleryVertex* vertices, int numTris) {
    if (!ctx.initialized) return;
    if (!vertices || numTris <= 0) return;

    for (int i = 0; i < numTris; i++) {
        render_triangle_internal(&vertices[i * 3],
                                 &vertices[i * 3 + 1],
                                 &vertices[i * 3 + 2]);
    }
}

void celeryDrawIndexedTriangles(const CeleryVertex* vertices,
                                const uint16_t* indices,
                                int numTris) {
    if (!ctx.initialized) return;
    if (!vertices || !indices || numTris <= 0) return;

    for (int i = 0; i < numTris; i++) {
        render_triangle_internal(&vertices[indices[i * 3]],
                                 &vertices[indices[i * 3 + 1]],
                                 &vertices[indices[i * 3 + 2]]);
    }
}
