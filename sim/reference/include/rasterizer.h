#ifndef RASTERIZER_H
#define RASTERIZER_H

#include "celery_types.h"
#include "framebuffer.h"
#include "texture.h"

// Initialize the rasterizer with a framebuffer
void rasterizer_init(Framebuffer* fb);

// Set render state
void rasterizer_set_texture(Texture* tex);
void rasterizer_enable_depth_test(bool enable);
void rasterizer_enable_texturing(bool enable);
void rasterizer_enable_gouraud(bool enable);

// Triangle setup - computes edge equations and gradients
// Returns false if triangle is degenerate (zero area)
bool triangle_setup(const Vertex* v0, const Vertex* v1, const Vertex* v2,
                    TriangleSetup* setup);

// Rasterize a triangle (main entry point)
void rasterizer_draw_triangle(const Vertex* v0, const Vertex* v1, const Vertex* v2);

// Statistics
typedef struct {
    uint64_t triangles_submitted;
    uint64_t triangles_culled;
    uint64_t pixels_drawn;
    uint64_t pixels_rejected;  // Failed depth test
} RasterizerStats;

RasterizerStats rasterizer_get_stats(void);
void rasterizer_reset_stats(void);

// Query state
bool rasterizer_is_texturing_enabled(void);
bool rasterizer_is_gouraud_enabled(void);
bool rasterizer_is_depth_test_enabled(void);

#endif // RASTERIZER_H
