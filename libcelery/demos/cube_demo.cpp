/*
 * Celery3D Cube Demo
 *
 * Renders a rotating textured cube using the libcelery API.
 * This demonstrates the complete graphics pipeline working through
 * the simulation backend.
 *
 * Usage: ./cube_demo [num_frames]
 * Output: frame_000.ppm, frame_001.ppm, ... (combine with ImageMagick)
 *
 * Copyright (c) 2024 Celery3D Project
 * SPDX-License-Identifier: Apache-2.0
 */

#include "celery.h"
#include <cstdio>
#include <cmath>
#include <cstdlib>

/* Screen dimensions (must match RTL SCREEN_WIDTH/HEIGHT) */
#define SCREEN_WIDTH 64
#define SCREEN_HEIGHT 64

/* ============================================================================
 * 3D Math Library
 * ============================================================================ */

struct Vec3 { float x, y, z; };
struct Vec4 { float x, y, z, w; };
struct Mat4 { float m[4][4]; };

static Mat4 mat4_identity() {
    Mat4 r = {{{0}}};
    r.m[0][0] = r.m[1][1] = r.m[2][2] = r.m[3][3] = 1.0f;
    return r;
}

static Mat4 mat4_multiply(Mat4 a, Mat4 b) {
    Mat4 r = {{{0}}};
    for (int i = 0; i < 4; i++)
        for (int j = 0; j < 4; j++)
            for (int k = 0; k < 4; k++)
                r.m[i][j] += a.m[i][k] * b.m[k][j];
    return r;
}

static Vec4 mat4_transform(Mat4 m, Vec4 v) {
    return {
        m.m[0][0]*v.x + m.m[0][1]*v.y + m.m[0][2]*v.z + m.m[0][3]*v.w,
        m.m[1][0]*v.x + m.m[1][1]*v.y + m.m[1][2]*v.z + m.m[1][3]*v.w,
        m.m[2][0]*v.x + m.m[2][1]*v.y + m.m[2][2]*v.z + m.m[2][3]*v.w,
        m.m[3][0]*v.x + m.m[3][1]*v.y + m.m[3][2]*v.z + m.m[3][3]*v.w
    };
}

static Mat4 mat4_perspective(float fov_y, float aspect, float near_p, float far_p) {
    Mat4 m = {{{0}}};
    float tan_half = tanf(fov_y / 2.0f);
    m.m[0][0] = 1.0f / (aspect * tan_half);
    m.m[1][1] = 1.0f / tan_half;
    m.m[2][2] = -(far_p + near_p) / (far_p - near_p);
    m.m[2][3] = -(2.0f * far_p * near_p) / (far_p - near_p);
    m.m[3][2] = -1.0f;
    return m;
}

static Vec3 vec3_sub(Vec3 a, Vec3 b) { return {a.x-b.x, a.y-b.y, a.z-b.z}; }
static float vec3_dot(Vec3 a, Vec3 b) { return a.x*b.x + a.y*b.y + a.z*b.z; }
static Vec3 vec3_cross(Vec3 a, Vec3 b) {
    return {a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x};
}

static Vec3 vec3_normalize(Vec3 v) {
    float len = sqrtf(vec3_dot(v, v));
    if (len > 0.0001f) return {v.x/len, v.y/len, v.z/len};
    return v;
}

static Mat4 mat4_look_at(Vec3 eye, Vec3 target, Vec3 up) {
    Vec3 f = vec3_normalize(vec3_sub(target, eye));
    Vec3 r = vec3_normalize(vec3_cross(f, up));
    Vec3 u = vec3_cross(r, f);
    Mat4 m = mat4_identity();
    m.m[0][0] = r.x;  m.m[0][1] = r.y;  m.m[0][2] = r.z;
    m.m[1][0] = u.x;  m.m[1][1] = u.y;  m.m[1][2] = u.z;
    m.m[2][0] = -f.x; m.m[2][1] = -f.y; m.m[2][2] = -f.z;
    m.m[0][3] = -vec3_dot(r, eye);
    m.m[1][3] = -vec3_dot(u, eye);
    m.m[2][3] = vec3_dot(f, eye);
    return m;
}

static Mat4 mat4_rotate_x(float a) {
    Mat4 m = mat4_identity();
    m.m[1][1] = cosf(a); m.m[1][2] = -sinf(a);
    m.m[2][1] = sinf(a); m.m[2][2] = cosf(a);
    return m;
}

static Mat4 mat4_rotate_y(float a) {
    Mat4 m = mat4_identity();
    m.m[0][0] = cosf(a);  m.m[0][2] = sinf(a);
    m.m[2][0] = -sinf(a); m.m[2][2] = cosf(a);
    return m;
}

/* ============================================================================
 * Cube Geometry
 * ============================================================================ */

static Vec3 cube_positions[24] = {
    /* Front face */
    {-1, -1,  1}, { 1, -1,  1}, { 1,  1,  1}, {-1,  1,  1},
    /* Back face */
    { 1, -1, -1}, {-1, -1, -1}, {-1,  1, -1}, { 1,  1, -1},
    /* Top face */
    {-1,  1,  1}, { 1,  1,  1}, { 1,  1, -1}, {-1,  1, -1},
    /* Bottom face */
    {-1, -1, -1}, { 1, -1, -1}, { 1, -1,  1}, {-1, -1,  1},
    /* Right face */
    { 1, -1,  1}, { 1, -1, -1}, { 1,  1, -1}, { 1,  1,  1},
    /* Left face */
    {-1, -1, -1}, {-1, -1,  1}, {-1,  1,  1}, {-1,  1, -1}
};

static float cube_uvs[48] = {
    0,1, 1,1, 1,0, 0,0,  /* Front */
    0,1, 1,1, 1,0, 0,0,  /* Back */
    0,1, 1,1, 1,0, 0,0,  /* Top */
    0,1, 1,1, 1,0, 0,0,  /* Bottom */
    0,1, 1,1, 1,0, 0,0,  /* Right */
    0,1, 1,1, 1,0, 0,0   /* Left */
};

static Vec3 face_colors[6] = {
    {1.0f, 0.8f, 0.8f},  /* Front - red tint */
    {0.8f, 1.0f, 0.8f},  /* Back - green tint */
    {0.8f, 0.8f, 1.0f},  /* Top - blue tint */
    {1.0f, 1.0f, 0.8f},  /* Bottom - yellow tint */
    {1.0f, 0.8f, 1.0f},  /* Right - magenta tint */
    {0.8f, 1.0f, 1.0f}   /* Left - cyan tint */
};

static int cube_indices[36] = {
    0,  1,  2,   0,  2,  3,   /* Front */
    4,  5,  6,   4,  6,  7,   /* Back */
    8,  9,  10,  8,  10, 11,  /* Top */
    12, 13, 14,  12, 14, 15,  /* Bottom */
    16, 17, 18,  16, 18, 19,  /* Right */
    20, 21, 22,  20, 22, 23   /* Left */
};

/* ============================================================================
 * Vertex Transformation
 * ============================================================================ */

static CeleryVertex transform_vertex(Vec3 pos, float u, float v, Vec3 color, Mat4 mvp) {
    Vec4 clip = mat4_transform(mvp, {pos.x, pos.y, pos.z, 1.0f});

    /* Perspective divide */
    float inv_w = 1.0f / clip.w;
    float ndc_x = clip.x * inv_w;
    float ndc_y = clip.y * inv_w;
    float ndc_z = clip.z * inv_w;

    /* NDC to screen coordinates */
    CeleryVertex vert;
    vert.x = (ndc_x + 1.0f) * 0.5f * SCREEN_WIDTH;
    vert.y = (1.0f - ndc_y) * 0.5f * SCREEN_HEIGHT;  /* Flip Y */
    vert.z = (ndc_z + 1.0f) * 0.5f;  /* Map to [0, 1] */

    /*
     * 1/w for perspective correction.
     * Must be proportional to 1/clip.w for correct perspective.
     * We scale up to keep values in a range the fixed-point RTL handles well.
     * (Raw inv_w is ~0.2-0.5, but RTL expects values in ~[1, 10] range)
     */
    vert.oow = inv_w * 16.0f;

    /* Texture coords (raw - RTL internally computes s*w, t*w for interpolation) */
    vert.sow = u;
    vert.tow = v;

    /* Vertex color */
    vert.r = color.x;
    vert.g = color.y;
    vert.b = color.z;
    vert.a = 1.0f;

    return vert;
}

/* ============================================================================
 * Texture Generation
 * ============================================================================ */

static void generate_checkerboard(uint16_t* texture, int size, int check_size) {
    for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
            int cx = x / check_size;
            int cy = y / check_size;
            /* White and gray checkerboard */
            texture[y * size + x] = ((cx + cy) % 2 == 0) ? 0xFFFF : 0x8410;
        }
    }
}

/* ============================================================================
 * Main
 * ============================================================================ */

int main(int argc, char** argv) {
    int num_frames = 60;
    if (argc > 1) {
        num_frames = atoi(argv[1]);
        if (num_frames < 1) num_frames = 1;
        if (num_frames > 360) num_frames = 360;
    }

    printf("Celery3D Cube Demo\n");
    printf("Rendering %d frames at %dx%d...\n", num_frames, SCREEN_WIDTH, SCREEN_HEIGHT);

    /* Initialize Celery */
    CeleryError err = celeryInit(CELERY_BACKEND_SIM, SCREEN_WIDTH, SCREEN_HEIGHT);
    if (err != CELERY_OK) {
        fprintf(stderr, "Failed to initialize Celery: %d\n", err);
        return 1;
    }

    /* Generate and upload texture */
    uint16_t texture[64 * 64];
    generate_checkerboard(texture, 64, 8);
    celeryTexImage(64, 64, texture, CELERY_TEXFMT_RGB565);

    /* Configure render state */
    celeryTexEnable(true);
    celeryTexFilter(CELERY_FILTER_BILINEAR);
    celeryTexModulate(true);  /* Multiply texture by vertex color */

    celeryDepthTest(true);
    celeryDepthFunc(CELERY_CMP_LESS);
    celeryDepthMask(true);

    celeryBlendEnable(false);

    /* Set up camera */
    Vec3 eye = {0.0f, 0.0f, 4.0f};
    Vec3 target = {0.0f, 0.0f, 0.0f};
    Vec3 up = {0.0f, 1.0f, 0.0f};
    Mat4 view = mat4_look_at(eye, target, up);
    Mat4 proj = mat4_perspective(M_PI / 4.0f, 1.0f, 0.1f, 100.0f);

    /* Render animation frames */
    for (int frame = 0; frame < num_frames; frame++) {
        printf("  Frame %d/%d\r", frame + 1, num_frames);
        fflush(stdout);

        /* Clear buffers */
        celeryClearBuffers(0x0000, 0xFFFF);

        /* Compute model-view-projection matrix */
        float angle = (float)frame * (2.0f * M_PI / num_frames);
        Mat4 model = mat4_multiply(mat4_rotate_y(angle), mat4_rotate_x(0.3f));
        Mat4 mvp = mat4_multiply(proj, mat4_multiply(view, model));

        /* Draw all triangles */
        for (int i = 0; i < 36; i += 3) {
            int face = i / 6;
            Vec3 color = face_colors[face];

            int i0 = cube_indices[i];
            int i1 = cube_indices[i + 1];
            int i2 = cube_indices[i + 2];

            CeleryVertex v0 = transform_vertex(cube_positions[i0],
                                               cube_uvs[i0 * 2], cube_uvs[i0 * 2 + 1],
                                               color, mvp);
            CeleryVertex v1 = transform_vertex(cube_positions[i1],
                                               cube_uvs[i1 * 2], cube_uvs[i1 * 2 + 1],
                                               color, mvp);
            CeleryVertex v2 = transform_vertex(cube_positions[i2],
                                               cube_uvs[i2 * 2], cube_uvs[i2 * 2 + 1],
                                               color, mvp);

            celeryDrawTriangle(&v0, &v1, &v2);
        }

        /* Output frame */
        char filename[64];
        snprintf(filename, sizeof(filename), "frame_%03d.ppm", frame);
        celerySwapBuffers(filename);
    }

    printf("\nDone! Convert to GIF with:\n");
    printf("  convert -delay 3 -loop 0 frame_*.ppm cube_animation.gif\n");

    celeryShutdown();
    return 0;
}
