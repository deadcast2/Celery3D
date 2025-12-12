#include "rasterizer.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

// Global state (in a real implementation, this would be in a context struct)
static Framebuffer* g_framebuffer = NULL;
static RenderState g_state = {
    .bound_texture = NULL,
    .depth_test_enabled = true,
    .texture_enabled = true,
    .gouraud_enabled = true,
    .clear_color = 0x0000
};
static RasterizerStats g_stats = {0};

void rasterizer_init(Framebuffer* fb) {
    g_framebuffer = fb;
    rasterizer_reset_stats();
}

void rasterizer_set_texture(Texture* tex) {
    g_state.bound_texture = tex;
}

void rasterizer_enable_depth_test(bool enable) {
    g_state.depth_test_enabled = enable;
}

void rasterizer_enable_texturing(bool enable) {
    g_state.texture_enabled = enable;
}

void rasterizer_enable_gouraud(bool enable) {
    g_state.gouraud_enabled = enable;
}

RasterizerStats rasterizer_get_stats(void) {
    return g_stats;
}

void rasterizer_reset_stats(void) {
    memset(&g_stats, 0, sizeof(g_stats));
}

bool rasterizer_is_texturing_enabled(void) {
    return g_state.texture_enabled;
}

bool rasterizer_is_gouraud_enabled(void) {
    return g_state.gouraud_enabled;
}

bool rasterizer_is_depth_test_enabled(void) {
    return g_state.depth_test_enabled;
}

// Compute edge equation: returns positive value if point is inside edge
// Edge equation: E(x,y) = (y0-y1)*x + (x1-x0)*y + (x0*y1 - x1*y0)
static void compute_edge_equation(const Vertex* v0, const Vertex* v1,
                                  EdgeEquation* edge) {
    edge->a = v0->y - v1->y;
    edge->b = v1->x - v0->x;
    edge->c = v0->x * v1->y - v1->x * v0->y;

    // Determine if this is a top or left edge (for tie-breaking)
    // Top edge: horizontal edge where v0 is to the right of v1
    // Left edge: edge going up (v0.y > v1.y)
    bool is_top = (edge->a == 0 && edge->b > 0);
    bool is_left = (edge->a > 0);
    edge->top_left = is_top || is_left;
}

// Evaluate edge equation at point (x, y)
static inline float edge_evaluate(const EdgeEquation* edge, float x, float y) {
    return edge->a * x + edge->b * y + edge->c;
}

bool triangle_setup(const Vertex* v0, const Vertex* v1, const Vertex* v2,
                    TriangleSetup* setup) {
    // Compute edge equations (counter-clockwise winding)
    compute_edge_equation(v0, v1, &setup->edges[0]);  // v0 -> v1
    compute_edge_equation(v1, v2, &setup->edges[1]);  // v1 -> v2
    compute_edge_equation(v2, v0, &setup->edges[2]);  // v2 -> v0

    // Compute 2x triangle area (signed)
    // Positive = counter-clockwise, negative = clockwise
    setup->area2 = (v1->x - v0->x) * (v2->y - v0->y) -
                   (v2->x - v0->x) * (v1->y - v0->y);

    // Cull degenerate triangles
    if (fabsf(setup->area2) < 0.0001f) {
        return false;
    }

    // If clockwise, we could flip winding or cull
    // For now, we'll handle both windings by using absolute area
    float inv_area2 = 1.0f / setup->area2;

    // Compute bounding box
    float minx = fminf(fminf(v0->x, v1->x), v2->x);
    float miny = fminf(fminf(v0->y, v1->y), v2->y);
    float maxx = fmaxf(fmaxf(v0->x, v1->x), v2->x);
    float maxy = fmaxf(fmaxf(v0->y, v1->y), v2->y);

    // Clip to screen
    setup->min_x = clampi((int)floorf(minx), 0, g_framebuffer->width - 1);
    setup->min_y = clampi((int)floorf(miny), 0, g_framebuffer->height - 1);
    setup->max_x = clampi((int)ceilf(maxx), 0, g_framebuffer->width - 1);
    setup->max_y = clampi((int)ceilf(maxy), 0, g_framebuffer->height - 1);

    // Compute attribute gradients
    // For any attribute A, we have:
    // dA/dx = ((A1-A0)*(y2-y0) - (A2-A0)*(y1-y0)) / area2
    // dA/dy = ((A2-A0)*(x1-x0) - (A1-A0)*(x2-x0)) / area2

    float dx01 = v1->x - v0->x, dy01 = v1->y - v0->y;
    float dx02 = v2->x - v0->x, dy02 = v2->y - v0->y;

    // Depth gradients
    float dz01 = v1->z - v0->z, dz02 = v2->z - v0->z;
    setup->dzdx = (dz01 * dy02 - dz02 * dy01) * inv_area2;
    setup->dzdy = (dz02 * dx01 - dz01 * dx02) * inv_area2;

    // 1/w gradients (for perspective correction)
    float dw01 = v1->w - v0->w, dw02 = v2->w - v0->w;
    setup->dwdx = (dw01 * dy02 - dw02 * dy01) * inv_area2;
    setup->dwdy = (dw02 * dx01 - dw01 * dx02) * inv_area2;

    // Texture coordinate gradients (perspective-corrected: u/w, v/w)
    float du01 = v1->u * v1->w - v0->u * v0->w;
    float du02 = v2->u * v2->w - v0->u * v0->w;
    float dv01 = v1->v * v1->w - v0->v * v0->w;
    float dv02 = v2->v * v2->w - v0->v * v0->w;
    setup->dudx = (du01 * dy02 - du02 * dy01) * inv_area2;
    setup->dudy = (du02 * dx01 - du01 * dx02) * inv_area2;
    setup->dvdx = (dv01 * dy02 - dv02 * dy01) * inv_area2;
    setup->dvdy = (dv02 * dx01 - dv01 * dx02) * inv_area2;

    // Color gradients (also perspective-corrected for proper interpolation)
    float dr01 = v1->r * v1->w - v0->r * v0->w;
    float dr02 = v2->r * v2->w - v0->r * v0->w;
    float dg01 = v1->g * v1->w - v0->g * v0->w;
    float dg02 = v2->g * v2->w - v0->g * v0->w;
    float db01 = v1->b * v1->w - v0->b * v0->w;
    float db02 = v2->b * v2->w - v0->b * v0->w;
    float da01 = v1->a * v1->w - v0->a * v0->w;
    float da02 = v2->a * v2->w - v0->a * v0->w;

    setup->drdx = (dr01 * dy02 - dr02 * dy01) * inv_area2;
    setup->drdy = (dr02 * dx01 - dr01 * dx02) * inv_area2;
    setup->dgdx = (dg01 * dy02 - dg02 * dy01) * inv_area2;
    setup->dgdy = (dg02 * dx01 - dg01 * dx02) * inv_area2;
    setup->dbdx = (db01 * dy02 - db02 * dy01) * inv_area2;
    setup->dbdy = (db02 * dx01 - db01 * dx02) * inv_area2;
    setup->dadx = (da01 * dy02 - da02 * dy01) * inv_area2;
    setup->dady = (da02 * dx01 - da01 * dx02) * inv_area2;

    return true;
}

void rasterizer_draw_triangle(const Vertex* v0, const Vertex* v1, const Vertex* v2) {
    if (!g_framebuffer) return;

    g_stats.triangles_submitted++;

    // Triangle setup
    TriangleSetup setup;
    if (!triangle_setup(v0, v1, v2, &setup)) {
        g_stats.triangles_culled++;
        return;
    }

    // Starting values at v0
    float x0 = v0->x, y0 = v0->y;
    float z0 = v0->z;
    float w0 = v0->w;
    float uw0 = v0->u * v0->w;
    float vw0 = v0->v * v0->w;
    float rw0 = v0->r * v0->w;
    float gw0 = v0->g * v0->w;
    float bw0 = v0->b * v0->w;
    (void)v0->a;  // Alpha not yet used

    // Iterate over bounding box
    for (int py = setup.min_y; py <= setup.max_y; py++) {
        for (int px = setup.min_x; px <= setup.max_x; px++) {
            // Sample at pixel center
            float x = px + 0.5f;
            float y = py + 0.5f;

            // Evaluate edge equations
            float e0 = edge_evaluate(&setup.edges[0], x, y);
            float e1 = edge_evaluate(&setup.edges[1], x, y);
            float e2 = edge_evaluate(&setup.edges[2], x, y);

            // Apply fill rule (top-left rule)
            // A pixel is inside if all edges are positive, or zero and top-left
            bool inside = true;
            if (setup.area2 > 0) {
                // Counter-clockwise: inside when all edges >= 0
                if (e0 < 0 || (e0 == 0 && !setup.edges[0].top_left)) inside = false;
                if (e1 < 0 || (e1 == 0 && !setup.edges[1].top_left)) inside = false;
                if (e2 < 0 || (e2 == 0 && !setup.edges[2].top_left)) inside = false;
            } else {
                // Clockwise: inside when all edges <= 0
                if (e0 > 0 || (e0 == 0 && setup.edges[0].top_left)) inside = false;
                if (e1 > 0 || (e1 == 0 && setup.edges[1].top_left)) inside = false;
                if (e2 > 0 || (e2 == 0 && setup.edges[2].top_left)) inside = false;
            }

            if (!inside) continue;

            // Interpolate attributes using gradients
            float dx = x - x0;
            float dy = y - y0;

            float z = z0 + setup.dzdx * dx + setup.dzdy * dy;
            float w = w0 + setup.dwdx * dx + setup.dwdy * dy;

            // Depth test
            if (g_state.depth_test_enabled) {
                if (z >= framebuffer_read_depth(g_framebuffer, px, py)) {
                    g_stats.pixels_rejected++;
                    continue;
                }
            }

            // Perspective-correct interpolation
            float inv_w = 1.0f / w;

            // Interpolate texture coordinates
            float u = (uw0 + setup.dudx * dx + setup.dudy * dy) * inv_w;
            float v = (vw0 + setup.dvdx * dx + setup.dvdy * dy) * inv_w;

            // Interpolate color
            float r = (rw0 + setup.drdx * dx + setup.drdy * dy) * inv_w;
            float g = (gw0 + setup.dgdx * dx + setup.dgdy * dy) * inv_w;
            float b = (bw0 + setup.dbdx * dx + setup.dbdy * dy) * inv_w;

            // Clamp colors
            r = clampf(r, 0.0f, 1.0f);
            g = clampf(g, 0.0f, 1.0f);
            b = clampf(b, 0.0f, 1.0f);

            // Sample texture
            color16_t final_color;
            if (g_state.texture_enabled && g_state.bound_texture) {
                color16_t tex_color = texture_sample_bilinear(g_state.bound_texture, u, v);

                if (g_state.gouraud_enabled) {
                    // Modulate texture with vertex color
                    uint8_t tr, tg, tb;
                    color565_to_rgb(tex_color, &tr, &tg, &tb);
                    tr = (uint8_t)(tr * r);
                    tg = (uint8_t)(tg * g);
                    tb = (uint8_t)(tb * b);
                    final_color = rgb_to_565(tr, tg, tb);
                } else {
                    final_color = tex_color;
                }
            } else {
                // Just vertex color
                final_color = rgbf_to_565(r, g, b);
            }

            // Write pixel
            framebuffer_write_pixel(g_framebuffer, px, py, final_color,
                                    z, g_state.depth_test_enabled);
            g_stats.pixels_drawn++;
        }
    }
}
