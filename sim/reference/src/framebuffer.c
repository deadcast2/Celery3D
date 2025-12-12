#include "framebuffer.h"
#include <stdlib.h>
#include <string.h>

Framebuffer* framebuffer_create(int width, int height) {
    Framebuffer* fb = malloc(sizeof(Framebuffer));
    if (!fb) return NULL;

    fb->width = width;
    fb->height = height;

    // Allocate color buffer (RGB565)
    fb->color = malloc(width * height * sizeof(color16_t));
    if (!fb->color) {
        free(fb);
        return NULL;
    }

    // Allocate depth buffer
    fb->depth = malloc(width * height * sizeof(float));
    if (!fb->depth) {
        free(fb->color);
        free(fb);
        return NULL;
    }

    // Initialize to black and far depth
    framebuffer_clear(fb, 0x0000, 1.0f);

    return fb;
}

void framebuffer_destroy(Framebuffer* fb) {
    if (fb) {
        free(fb->color);
        free(fb->depth);
        free(fb);
    }
}

void framebuffer_clear_color(Framebuffer* fb, color16_t color) {
    int size = fb->width * fb->height;
    for (int i = 0; i < size; i++) {
        fb->color[i] = color;
    }
}

void framebuffer_clear_depth(Framebuffer* fb, float depth) {
    int size = fb->width * fb->height;
    for (int i = 0; i < size; i++) {
        fb->depth[i] = depth;
    }
}

void framebuffer_clear(Framebuffer* fb, color16_t color, float depth) {
    framebuffer_clear_color(fb, color);
    framebuffer_clear_depth(fb, depth);
}

void framebuffer_write_pixel(Framebuffer* fb, int x, int y, color16_t color,
                             float depth, bool depth_test) {
    // Bounds check
    if (x < 0 || x >= fb->width || y < 0 || y >= fb->height) {
        return;
    }

    int index = y * fb->width + x;

    // Depth test (less than = closer = visible)
    if (depth_test) {
        if (depth >= fb->depth[index]) {
            return; // Fragment is behind existing pixel
        }
    }

    // Write pixel
    fb->color[index] = color;
    fb->depth[index] = depth;
}

color16_t framebuffer_read_pixel(Framebuffer* fb, int x, int y) {
    if (x < 0 || x >= fb->width || y < 0 || y >= fb->height) {
        return 0;
    }
    return fb->color[y * fb->width + x];
}

float framebuffer_read_depth(Framebuffer* fb, int x, int y) {
    if (x < 0 || x >= fb->width || y < 0 || y >= fb->height) {
        return 1.0f;
    }
    return fb->depth[y * fb->width + x];
}
