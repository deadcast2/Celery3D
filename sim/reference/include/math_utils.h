#ifndef MATH_UTILS_H
#define MATH_UTILS_H

#include <math.h>

// 4x4 Matrix for transformations
typedef struct {
    float m[4][4];
} Mat4;

// 3D Vector
typedef struct {
    float x, y, z;
} Vec3;

// 4D Vector (homogeneous coordinates)
typedef struct {
    float x, y, z, w;
} Vec4;

// Matrix operations
Mat4 mat4_identity(void);
Mat4 mat4_multiply(Mat4 a, Mat4 b);
Vec4 mat4_transform(Mat4 m, Vec4 v);

// Projection matrices
Mat4 mat4_perspective(float fov_y, float aspect, float near, float far);

// View matrices
Mat4 mat4_look_at(Vec3 eye, Vec3 target, Vec3 up);

// Model matrices
Mat4 mat4_translate(float x, float y, float z);
Mat4 mat4_rotate_x(float angle);
Mat4 mat4_rotate_y(float angle);
Mat4 mat4_rotate_z(float angle);
Mat4 mat4_scale(float x, float y, float z);

// Vector operations
Vec3 vec3_add(Vec3 a, Vec3 b);
Vec3 vec3_sub(Vec3 a, Vec3 b);
Vec3 vec3_scale(Vec3 v, float s);
Vec3 vec3_cross(Vec3 a, Vec3 b);
float vec3_dot(Vec3 a, Vec3 b);
Vec3 vec3_normalize(Vec3 v);
float vec3_length(Vec3 v);

#endif // MATH_UTILS_H
