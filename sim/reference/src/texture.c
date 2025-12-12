#include "texture.h"
#include <stdlib.h>
#include <math.h>

Texture* texture_create(uint16_t width, uint16_t height) {
    Texture* tex = malloc(sizeof(Texture));
    if (!tex) return NULL;

    tex->width = width;
    tex->height = height;
    tex->data = malloc(width * height * sizeof(color16_t));

    if (!tex->data) {
        free(tex);
        return NULL;
    }

    // Initialize to black
    for (int i = 0; i < width * height; i++) {
        tex->data[i] = 0;
    }

    return tex;
}

void texture_destroy(Texture* tex) {
    if (tex) {
        free(tex->data);
        free(tex);
    }
}

void texture_set_pixel(Texture* tex, int x, int y, color16_t color) {
    if (x >= 0 && x < tex->width && y >= 0 && y < tex->height) {
        tex->data[y * tex->width + x] = color;
    }
}

// Wrap UV coordinates to [0, 1) range
static inline float wrap_uv(float v) {
    v = v - floorf(v);  // Get fractional part
    if (v < 0) v += 1.0f;
    return v;
}

color16_t texture_sample_nearest(Texture* tex, float u, float v) {
    // Wrap coordinates
    u = wrap_uv(u);
    v = wrap_uv(v);

    // Convert to texel coordinates
    int x = (int)(u * tex->width) % tex->width;
    int y = (int)(v * tex->height) % tex->height;

    return tex->data[y * tex->width + x];
}

color16_t texture_sample_bilinear(Texture* tex, float u, float v) {
    // Wrap coordinates
    u = wrap_uv(u);
    v = wrap_uv(v);

    // Convert to texel coordinates (with sub-pixel precision)
    float tx = u * tex->width - 0.5f;
    float ty = v * tex->height - 0.5f;

    // Get integer and fractional parts
    int x0 = (int)floorf(tx);
    int y0 = (int)floorf(ty);
    float fx = tx - x0;
    float fy = ty - y0;

    // Wrap coordinates
    x0 = ((x0 % tex->width) + tex->width) % tex->width;
    y0 = ((y0 % tex->height) + tex->height) % tex->height;
    int x1 = (x0 + 1) % tex->width;
    int y1 = (y0 + 1) % tex->height;

    // Fetch 4 texels
    color16_t c00 = tex->data[y0 * tex->width + x0];
    color16_t c10 = tex->data[y0 * tex->width + x1];
    color16_t c01 = tex->data[y1 * tex->width + x0];
    color16_t c11 = tex->data[y1 * tex->width + x1];

    // Extract RGB components
    uint8_t r00, g00, b00, r10, g10, b10, r01, g01, b01, r11, g11, b11;
    color565_to_rgb(c00, &r00, &g00, &b00);
    color565_to_rgb(c10, &r10, &g10, &b10);
    color565_to_rgb(c01, &r01, &g01, &b01);
    color565_to_rgb(c11, &r11, &g11, &b11);

    // Bilinear interpolation
    float w00 = (1.0f - fx) * (1.0f - fy);
    float w10 = fx * (1.0f - fy);
    float w01 = (1.0f - fx) * fy;
    float w11 = fx * fy;

    uint8_t r = (uint8_t)(r00 * w00 + r10 * w10 + r01 * w01 + r11 * w11);
    uint8_t g = (uint8_t)(g00 * w00 + g10 * w10 + g01 * w01 + g11 * w11);
    uint8_t b = (uint8_t)(b00 * w00 + b10 * w10 + b01 * w01 + b11 * w11);

    return rgb_to_565(r, g, b);
}

Texture* texture_create_checkerboard(uint16_t size, int check_size,
                                     color16_t color1, color16_t color2) {
    Texture* tex = texture_create(size, size);
    if (!tex) return NULL;

    for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
            int cx = x / check_size;
            int cy = y / check_size;
            color16_t color = ((cx + cy) % 2 == 0) ? color1 : color2;
            tex->data[y * size + x] = color;
        }
    }

    return tex;
}

Texture* texture_create_gradient(uint16_t width, uint16_t height) {
    Texture* tex = texture_create(width, height);
    if (!tex) return NULL;

    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            uint8_t r = (uint8_t)((x * 255) / width);
            uint8_t g = (uint8_t)((y * 255) / height);
            uint8_t b = 128;
            tex->data[y * width + x] = rgb_to_565(r, g, b);
        }
    }

    return tex;
}
