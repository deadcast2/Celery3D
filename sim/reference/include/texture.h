#ifndef TEXTURE_H
#define TEXTURE_H

#include "celery_types.h"

// Create a texture
Texture* texture_create(uint16_t width, uint16_t height);

// Destroy a texture
void texture_destroy(Texture* tex);

// Set pixel in texture
void texture_set_pixel(Texture* tex, int x, int y, color16_t color);

// Sample texture at UV coordinates (nearest neighbor)
color16_t texture_sample_nearest(Texture* tex, float u, float v);

// Sample texture at UV coordinates (bilinear filtering)
color16_t texture_sample_bilinear(Texture* tex, float u, float v);

// Generate a checkerboard test texture
Texture* texture_create_checkerboard(uint16_t size, int check_size,
                                     color16_t color1, color16_t color2);

// Generate a gradient test texture
Texture* texture_create_gradient(uint16_t width, uint16_t height);

#endif // TEXTURE_H
