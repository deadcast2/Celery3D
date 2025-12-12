#ifndef CELERY_TYPES_H
#define CELERY_TYPES_H

#include <stdint.h>
#include <stdbool.h>

// Screen dimensions (Voodoo 1 standard)
#define SCREEN_WIDTH  640
#define SCREEN_HEIGHT 480

// Color format: RGB565 (16-bit, like Voodoo 1)
typedef uint16_t color16_t;

// Vertex structure - screen space coordinates
// This matches what the GPU will receive (CPU does T&L)
typedef struct {
    float x, y;         // Screen coordinates
    float z;            // Depth (0.0 = near, 1.0 = far)
    float w;            // 1/z for perspective correction
    float u, v;         // Texture coordinates
    float r, g, b, a;   // Vertex color (0.0 - 1.0)
} Vertex;

// Triangle structure
typedef struct {
    Vertex v[3];
} Triangle;

// Texture structure
typedef struct {
    uint16_t width;
    uint16_t height;
    color16_t* data;    // RGB565 pixel data
} Texture;

// Framebuffer structure
typedef struct {
    int width;
    int height;
    color16_t* color;   // Color buffer (RGB565)
    float* depth;       // Depth buffer (floating point)
} Framebuffer;

// Render state
typedef struct {
    Texture* bound_texture;
    bool depth_test_enabled;
    bool texture_enabled;
    bool gouraud_enabled;
    color16_t clear_color;
} RenderState;

// Edge equation for rasterization
// Ax + By + C = 0 defines the edge
typedef struct {
    float a, b, c;      // Edge equation coefficients
    bool top_left;      // Is this a top or left edge? (for fill rules)
} EdgeEquation;

// Triangle setup result
typedef struct {
    EdgeEquation edges[3];
    float area2;        // 2x triangle area (for barycentric)

    // Bounding box
    int min_x, min_y;
    int max_x, max_y;

    // Attribute gradients (change per pixel)
    float dzdx, dzdy;   // Depth gradients
    float dwdx, dwdy;   // 1/z gradients
    float dudx, dudy;   // Texture U gradients
    float dvdx, dvdy;   // Texture V gradients
    float drdx, drdy;   // Red gradients
    float dgdx, dgdy;   // Green gradients
    float dbdx, dbdy;   // Blue gradients
    float dadx, dady;   // Alpha gradients
} TriangleSetup;

// Color conversion utilities
static inline color16_t rgb_to_565(uint8_t r, uint8_t g, uint8_t b) {
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
}

static inline color16_t rgbf_to_565(float r, float g, float b) {
    uint8_t ri = (uint8_t)(r * 255.0f);
    uint8_t gi = (uint8_t)(g * 255.0f);
    uint8_t bi = (uint8_t)(b * 255.0f);
    return rgb_to_565(ri, gi, bi);
}

static inline void color565_to_rgb(color16_t c, uint8_t* r, uint8_t* g, uint8_t* b) {
    *r = ((c >> 11) & 0x1F) << 3;
    *g = ((c >> 5) & 0x3F) << 2;
    *b = (c & 0x1F) << 3;
}

// Clamp utility
static inline float clampf(float v, float min, float max) {
    if (v < min) return min;
    if (v > max) return max;
    return v;
}

static inline int clampi(int v, int min, int max) {
    if (v < min) return min;
    if (v > max) return max;
    return v;
}

#endif // CELERY_TYPES_H
