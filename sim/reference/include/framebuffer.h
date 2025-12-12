#ifndef FRAMEBUFFER_H
#define FRAMEBUFFER_H

#include "celery_types.h"

// Create a new framebuffer
Framebuffer* framebuffer_create(int width, int height);

// Destroy framebuffer
void framebuffer_destroy(Framebuffer* fb);

// Clear the color buffer
void framebuffer_clear_color(Framebuffer* fb, color16_t color);

// Clear the depth buffer
void framebuffer_clear_depth(Framebuffer* fb, float depth);

// Clear both buffers
void framebuffer_clear(Framebuffer* fb, color16_t color, float depth);

// Write a pixel (with optional depth test)
void framebuffer_write_pixel(Framebuffer* fb, int x, int y, color16_t color,
                             float depth, bool depth_test);

// Get pixel color
color16_t framebuffer_read_pixel(Framebuffer* fb, int x, int y);

// Get depth value
float framebuffer_read_depth(Framebuffer* fb, int x, int y);

#endif // FRAMEBUFFER_H
