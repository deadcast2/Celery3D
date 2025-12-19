/*
 * Celery3D Graphics Library
 *
 * A Glide-inspired graphics API for the Celery3D GPU.
 * Designed for screen-space rendering - the application handles all
 * transformation and lighting (T&L), just like the original 3dfx Voodoo.
 *
 * Target ports: Quake, OpenLara, and other classic 3D engines.
 *
 * Copyright (c) 2024 Celery3D Project
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef CELERY_H
#define CELERY_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Constants
 * ============================================================================ */

#define CELERY_MAX_TEXTURE_SIZE 256

/* ============================================================================
 * Types and Enumerations
 * ============================================================================ */

/* Depth comparison functions (matches Glide GR_CMP_*) */
typedef enum {
    CELERY_CMP_NEVER    = 0,
    CELERY_CMP_LESS     = 1,
    CELERY_CMP_EQUAL    = 2,
    CELERY_CMP_LEQUAL   = 3,
    CELERY_CMP_GREATER  = 4,
    CELERY_CMP_NOTEQUAL = 5,
    CELERY_CMP_GEQUAL   = 6,
    CELERY_CMP_ALWAYS   = 7
} CeleryCmpFunc;

/* Blend factors (matches Glide GR_BLEND_*) */
typedef enum {
    CELERY_BLEND_ZERO                = 0,
    CELERY_BLEND_SRC_ALPHA           = 1,
    CELERY_BLEND_SRC_COLOR           = 2,
    CELERY_BLEND_DST_ALPHA           = 3,
    CELERY_BLEND_DST_COLOR           = 4,
    CELERY_BLEND_ONE                 = 5,
    CELERY_BLEND_ONE_MINUS_SRC_ALPHA = 6,
    CELERY_BLEND_ONE_MINUS_SRC_COLOR = 7,
    CELERY_BLEND_ONE_MINUS_DST_ALPHA = 8,
    CELERY_BLEND_ONE_MINUS_DST_COLOR = 9,
    CELERY_BLEND_ALPHA_SATURATE      = 10
} CeleryBlendFactor;

/* Alpha source selection */
typedef enum {
    CELERY_ALPHA_TEXTURE  = 0,   /* From RGBA4444 texture alpha channel */
    CELERY_ALPHA_VERTEX   = 1,   /* From vertex color interpolation */
    CELERY_ALPHA_CONSTANT = 2,   /* From celeryConstantAlpha() value */
    CELERY_ALPHA_ONE      = 3    /* Always fully opaque (1.0) */
} CeleryAlphaSource;

/* Texture formats */
typedef enum {
    CELERY_TEXFMT_RGB565   = 0,  /* 16-bit RGB (5-6-5), no alpha */
    CELERY_TEXFMT_RGBA4444 = 1   /* 16-bit RGBA (4-4-4-4) */
} CeleryTexFormat;

/* Texture filter modes */
typedef enum {
    CELERY_FILTER_NEAREST  = 0,  /* Point sampling */
    CELERY_FILTER_BILINEAR = 1   /* Bilinear interpolation */
} CeleryTexFilter;

/* Backend type for initialization */
typedef enum {
    CELERY_BACKEND_SIM = 0,      /* Verilator simulation backend */
    CELERY_BACKEND_HW  = 1       /* Real hardware (PCIe) - future */
} CeleryBackend;

/* Error codes */
typedef enum {
    CELERY_OK              =  0,
    CELERY_ERR_INIT        = -1,  /* Initialization failed */
    CELERY_ERR_NO_CONTEXT  = -2,  /* No active context */
    CELERY_ERR_INVALID_ARG = -3,  /* Invalid argument */
    CELERY_ERR_BACKEND     = -4   /* Backend error */
} CeleryError;

/*
 * Vertex structure (screen-space)
 *
 * Coordinates are in screen pixels with sub-pixel precision.
 * The application performs all T&L and submits screen-space vertices.
 *
 * For perspective-correct interpolation:
 *   - Set 'oow' to 1/w where w is the clip-space W coordinate
 *   - Texture coords should be pre-divided: sow = s/w, tow = t/w
 *
 * Color components are in [0.0, 1.0] range.
 */
typedef struct {
    float x, y;         /* Screen position (pixels, sub-pixel precision) */
    float z;            /* Depth value [0.0 = near, 1.0 = far] */
    float oow;          /* 1/w for perspective correction */
    float sow, tow;     /* Texture coordinates (s/w, t/w) */
    float r, g, b, a;   /* Vertex color [0.0 - 1.0] */
} CeleryVertex;

/* ============================================================================
 * Initialization and Shutdown
 * ============================================================================ */

/*
 * Initialize the Celery graphics system.
 *
 * @param backend  Which backend to use (CELERY_BACKEND_SIM or CELERY_BACKEND_HW)
 * @param width    Framebuffer width in pixels
 * @param height   Framebuffer height in pixels
 * @return         CELERY_OK on success, error code on failure
 */
CeleryError celeryInit(CeleryBackend backend, int width, int height);

/*
 * Shut down the Celery graphics system and release resources.
 */
void celeryShutdown(void);

/*
 * Get the current screen dimensions.
 */
int celeryGetWidth(void);
int celeryGetHeight(void);

/* ============================================================================
 * Buffer Management
 * ============================================================================ */

/*
 * Clear the color buffer to the specified RGB565 color.
 *
 * @param color  16-bit RGB565 color value
 */
void celeryClearColor(uint16_t color);

/*
 * Clear the color buffer using float RGB values.
 *
 * @param r, g, b  Color components [0.0 - 1.0]
 */
void celeryClearColorRGB(float r, float g, float b);

/*
 * Clear the depth buffer to the specified value.
 *
 * @param depth  16-bit depth value (0xFFFF = far, 0x0000 = near)
 */
void celeryClearDepth(uint16_t depth);

/*
 * Clear both color and depth buffers.
 *
 * @param color  16-bit RGB565 color value
 * @param depth  16-bit depth value
 */
void celeryClearBuffers(uint16_t color, uint16_t depth);

/*
 * Finish rendering and present the frame.
 *
 * For simulation backend: writes output image file.
 * For hardware backend: performs buffer swap.
 *
 * @param filename  Output filename (simulation only, can be NULL for hardware)
 */
void celerySwapBuffers(const char* filename);

/* ============================================================================
 * Depth Buffer State
 * ============================================================================ */

/*
 * Enable or disable depth testing.
 *
 * @param enable  true to enable depth testing
 */
void celeryDepthTest(bool enable);

/*
 * Set the depth comparison function.
 *
 * @param func  Comparison function (CELERY_CMP_*)
 */
void celeryDepthFunc(CeleryCmpFunc func);

/*
 * Enable or disable writes to the depth buffer.
 *
 * @param enable  true to enable depth writes
 */
void celeryDepthMask(bool enable);

/* ============================================================================
 * Alpha Blending State
 * ============================================================================ */

/*
 * Enable or disable alpha blending.
 *
 * @param enable  true to enable blending
 */
void celeryBlendEnable(bool enable);

/*
 * Set the blend function.
 *
 * Final color = src * srcFactor + dst * dstFactor
 *
 * Common combinations:
 *   Standard alpha:  (SRC_ALPHA, ONE_MINUS_SRC_ALPHA)
 *   Additive:        (ONE, ONE)
 *   Multiplicative:  (DST_COLOR, ZERO)
 *
 * @param srcFactor  Source blend factor
 * @param dstFactor  Destination blend factor
 */
void celeryBlendFunc(CeleryBlendFactor srcFactor, CeleryBlendFactor dstFactor);

/*
 * Set the alpha source for blending operations.
 *
 * @param source  Where to get alpha from (CELERY_ALPHA_*)
 */
void celeryAlphaSource(CeleryAlphaSource source);

/*
 * Set the constant alpha value (used when alpha source is CELERY_ALPHA_CONSTANT).
 *
 * @param alpha  Alpha value [0-255]
 */
void celeryConstantAlpha(uint8_t alpha);

/* ============================================================================
 * Texture State
 * ============================================================================ */

/*
 * Upload a texture to the GPU.
 *
 * @param width   Texture width (must be power of 2, max 256)
 * @param height  Texture height (must be power of 2, max 256)
 * @param data    Pointer to pixel data (16-bit per pixel)
 * @param format  Pixel format (CELERY_TEXFMT_*)
 * @return        CELERY_OK on success
 */
CeleryError celeryTexImage(int width, int height, const uint16_t* data,
                           CeleryTexFormat format);

/*
 * Enable or disable texturing.
 *
 * @param enable  true to enable texturing
 */
void celeryTexEnable(bool enable);

/*
 * Set the texture filter mode.
 *
 * @param filter  Filter mode (CELERY_FILTER_*)
 */
void celeryTexFilter(CeleryTexFilter filter);

/*
 * Enable or disable Gouraud color modulation with texture.
 *
 * When enabled: final_color = texture_color * vertex_color
 * When disabled: final_color = texture_color
 *
 * @param enable  true to enable modulation
 */
void celeryTexModulate(bool enable);

/* ============================================================================
 * Drawing
 * ============================================================================ */

/*
 * Draw a single triangle.
 *
 * Vertices should be in counter-clockwise order for front-facing triangles.
 * All coordinates are in screen space (pixels).
 *
 * @param v0, v1, v2  Pointers to the three vertices
 */
void celeryDrawTriangle(const CeleryVertex* v0,
                        const CeleryVertex* v1,
                        const CeleryVertex* v2);

/*
 * Draw a list of triangles.
 *
 * @param vertices   Array of vertices (3 per triangle)
 * @param numTris    Number of triangles to draw
 */
void celeryDrawTriangles(const CeleryVertex* vertices, int numTris);

/*
 * Draw an indexed triangle list.
 *
 * @param vertices   Array of vertices
 * @param indices    Array of indices (3 per triangle)
 * @param numTris    Number of triangles to draw
 */
void celeryDrawIndexedTriangles(const CeleryVertex* vertices,
                                const uint16_t* indices,
                                int numTris);

/* ============================================================================
 * Utility Functions
 * ============================================================================ */

/*
 * Pack RGB floats into RGB565 format.
 *
 * @param r, g, b  Color components [0.0 - 1.0]
 * @return         Packed RGB565 value
 */
static inline uint16_t celeryPackRGB565(float r, float g, float b) {
    uint8_t ri = (uint8_t)(r * 31.0f);
    uint8_t gi = (uint8_t)(g * 63.0f);
    uint8_t bi = (uint8_t)(b * 31.0f);
    if (ri > 31) ri = 31;
    if (gi > 63) gi = 63;
    if (bi > 31) bi = 31;
    return (uint16_t)((ri << 11) | (gi << 5) | bi);
}

/*
 * Pack RGBA floats into RGBA4444 format.
 *
 * @param r, g, b, a  Color components [0.0 - 1.0]
 * @return            Packed RGBA4444 value
 */
static inline uint16_t celeryPackRGBA4444(float r, float g, float b, float a) {
    uint8_t ri = (uint8_t)(r * 15.0f);
    uint8_t gi = (uint8_t)(g * 15.0f);
    uint8_t bi = (uint8_t)(b * 15.0f);
    uint8_t ai = (uint8_t)(a * 15.0f);
    if (ri > 15) ri = 15;
    if (gi > 15) gi = 15;
    if (bi > 15) bi = 15;
    if (ai > 15) ai = 15;
    return (uint16_t)((ri << 12) | (gi << 8) | (bi << 4) | ai);
}

#ifdef __cplusplus
}
#endif

#endif /* CELERY_H */
