#include <SDL2/SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <math.h>

#include "celery_types.h"
#include "framebuffer.h"
#include "rasterizer.h"
#include "texture.h"
#include "math_utils.h"

#define WINDOW_SCALE 1  // Scale factor for window (1 = 640x480)

// Convert RGB565 framebuffer to ARGB8888 for SDL
static void framebuffer_to_sdl(Framebuffer* fb, uint32_t* pixels) {
    for (int i = 0; i < fb->width * fb->height; i++) {
        color16_t c = fb->color[i];
        uint8_t r, g, b;
        color565_to_rgb(c, &r, &g, &b);
        pixels[i] = (0xFF << 24) | (r << 16) | (g << 8) | b;
    }
}

// Transform a 3D vertex through MVP matrix to screen space
static Vertex transform_vertex(Vec3 pos, float u, float v, Vec3 color, Mat4 mvp) {
    Vec4 clip = mat4_transform(mvp, (Vec4){pos.x, pos.y, pos.z, 1.0f});

    // Perspective divide
    float inv_w = 1.0f / clip.w;
    float ndc_x = clip.x * inv_w;
    float ndc_y = clip.y * inv_w;
    float ndc_z = clip.z * inv_w;

    // NDC to screen coordinates
    Vertex vert;
    vert.x = (ndc_x + 1.0f) * 0.5f * SCREEN_WIDTH;
    vert.y = (1.0f - ndc_y) * 0.5f * SCREEN_HEIGHT;  // Flip Y
    vert.z = (ndc_z + 1.0f) * 0.5f;  // Map to [0, 1]
    vert.w = inv_w;  // Store 1/w for perspective correction
    vert.u = u;
    vert.v = v;
    vert.r = color.x;
    vert.g = color.y;
    vert.b = color.z;
    vert.a = 1.0f;

    return vert;
}

// Cube vertex data
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

static const float cube_uvs[] = {
    0, 1,  1, 1,  1, 0,  0, 0,  // Front
    0, 1,  1, 1,  1, 0,  0, 0,  // Back
    0, 1,  1, 1,  1, 0,  0, 0,  // Top
    0, 1,  1, 1,  1, 0,  0, 0,  // Bottom
    0, 1,  1, 1,  1, 0,  0, 0,  // Right
    0, 1,  1, 1,  1, 0,  0, 0,  // Left
};

static const Vec3 face_colors[] = {
    {1.0f, 0.8f, 0.8f},  // Front - light red
    {0.8f, 1.0f, 0.8f},  // Back - light green
    {0.8f, 0.8f, 1.0f},  // Top - light blue
    {1.0f, 1.0f, 0.8f},  // Bottom - light yellow
    {1.0f, 0.8f, 1.0f},  // Right - light magenta
    {0.8f, 1.0f, 1.0f},  // Left - light cyan
};

static const int cube_indices[] = {
    0, 1, 2,  0, 2, 3,    // Front
    4, 5, 6,  4, 6, 7,    // Back
    8, 9, 10, 8, 10, 11,  // Top
    12, 13, 14, 12, 14, 15, // Bottom
    16, 17, 18, 16, 18, 19, // Right
    20, 21, 22, 20, 22, 23, // Left
};

static void draw_cube(Mat4 mvp, Texture* tex) {
    rasterizer_set_texture(tex);

    for (int i = 0; i < 36; i += 3) {
        int face = i / 6;
        Vec3 color = face_colors[face];

        int i0 = cube_indices[i];
        int i1 = cube_indices[i + 1];
        int i2 = cube_indices[i + 2];

        Vertex v0 = transform_vertex(cube_positions[i0],
                                     cube_uvs[i0 * 2], cube_uvs[i0 * 2 + 1],
                                     color, mvp);
        Vertex v1 = transform_vertex(cube_positions[i1],
                                     cube_uvs[i1 * 2], cube_uvs[i1 * 2 + 1],
                                     color, mvp);
        Vertex v2 = transform_vertex(cube_positions[i2],
                                     cube_uvs[i2 * 2], cube_uvs[i2 * 2 + 1],
                                     color, mvp);

        rasterizer_draw_triangle(&v0, &v1, &v2);
    }
}

int main(int argc, char* argv[]) {
    (void)argc;
    (void)argv;

    // Initialize SDL
    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        fprintf(stderr, "SDL init failed: %s\n", SDL_GetError());
        return 1;
    }

    // Create window
    SDL_Window* window = SDL_CreateWindow(
        "Celery3D Reference Renderer",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        SCREEN_WIDTH * WINDOW_SCALE, SCREEN_HEIGHT * WINDOW_SCALE,
        SDL_WINDOW_SHOWN
    );
    if (!window) {
        fprintf(stderr, "Window creation failed: %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }

    // Create renderer
    SDL_Renderer* renderer = SDL_CreateRenderer(window, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!renderer) {
        fprintf(stderr, "Renderer creation failed: %s\n", SDL_GetError());
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }

    // Create texture for framebuffer display
    SDL_Texture* sdl_texture = SDL_CreateTexture(renderer,
        SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING,
        SCREEN_WIDTH, SCREEN_HEIGHT);
    if (!sdl_texture) {
        fprintf(stderr, "Texture creation failed: %s\n", SDL_GetError());
        SDL_DestroyRenderer(renderer);
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }

    // Create framebuffer
    Framebuffer* fb = framebuffer_create(SCREEN_WIDTH, SCREEN_HEIGHT);
    if (!fb) {
        fprintf(stderr, "Framebuffer creation failed\n");
        SDL_DestroyTexture(sdl_texture);
        SDL_DestroyRenderer(renderer);
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }

    // Initialize rasterizer
    rasterizer_init(fb);
    rasterizer_enable_depth_test(true);
    rasterizer_enable_texturing(true);
    rasterizer_enable_gouraud(true);

    // Create test texture
    Texture* checkerboard = texture_create_checkerboard(64, 8,
        rgb_to_565(255, 255, 255), rgb_to_565(100, 100, 100));

    // Allocate pixel buffer for SDL
    uint32_t* sdl_pixels = malloc(SCREEN_WIDTH * SCREEN_HEIGHT * sizeof(uint32_t));

    // Setup projection matrix
    float aspect = (float)SCREEN_WIDTH / (float)SCREEN_HEIGHT;
    Mat4 proj = mat4_perspective(60.0f * 3.14159f / 180.0f, aspect, 0.1f, 100.0f);

    // Setup view matrix
    Vec3 eye = {0, 2, 5};
    Vec3 target = {0, 0, 0};
    Vec3 up = {0, 1, 0};
    Mat4 view = mat4_look_at(eye, target, up);

    // Main loop
    bool running = true;
    float angle = 0.0f;
    Uint32 last_time = SDL_GetTicks();
    int frame_count = 0;

    printf("Celery3D Reference Renderer\n");
    printf("Controls: ESC to quit, T to toggle texturing, G to toggle Gouraud shading\n");

    while (running) {
        // Handle events
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT) {
                running = false;
            } else if (event.type == SDL_KEYDOWN) {
                switch (event.key.keysym.sym) {
                    case SDLK_ESCAPE:
                        running = false;
                        break;
                    case SDLK_t:
                        rasterizer_enable_texturing(
                            !rasterizer_is_texturing_enabled());
                        printf("Texturing: %s\n",
                               rasterizer_is_texturing_enabled() ? "ON" : "OFF");
                        break;
                    case SDLK_g:
                        rasterizer_enable_gouraud(
                            !rasterizer_is_gouraud_enabled());
                        printf("Gouraud shading: %s\n",
                               rasterizer_is_gouraud_enabled() ? "ON" : "OFF");
                        break;
                }
            }
        }

        // Clear framebuffer
        framebuffer_clear(fb, rgb_to_565(32, 32, 64), 1.0f);
        rasterizer_reset_stats();

        // Update rotation
        angle += 0.02f;

        // Create model matrix (rotation)
        Mat4 model = mat4_multiply(mat4_rotate_y(angle),
                                   mat4_rotate_x(angle * 0.7f));

        // Create MVP matrix
        Mat4 mv = mat4_multiply(view, model);
        Mat4 mvp = mat4_multiply(proj, mv);

        // Draw cube
        draw_cube(mvp, checkerboard);

        // Convert framebuffer to SDL format
        framebuffer_to_sdl(fb, sdl_pixels);

        // Update SDL texture
        SDL_UpdateTexture(sdl_texture, NULL, sdl_pixels,
                          SCREEN_WIDTH * sizeof(uint32_t));

        // Render
        SDL_RenderClear(renderer);
        SDL_RenderCopy(renderer, sdl_texture, NULL, NULL);
        SDL_RenderPresent(renderer);

        // FPS counter
        frame_count++;
        Uint32 current_time = SDL_GetTicks();
        if (current_time - last_time >= 1000) {
            RasterizerStats stats = rasterizer_get_stats();
            printf("FPS: %d | Tris: %llu | Pixels: %llu\n",
                   frame_count, stats.triangles_submitted, stats.pixels_drawn);
            frame_count = 0;
            last_time = current_time;
        }
    }

    // Cleanup
    free(sdl_pixels);
    texture_destroy(checkerboard);
    framebuffer_destroy(fb);
    SDL_DestroyTexture(sdl_texture);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();

    return 0;
}
