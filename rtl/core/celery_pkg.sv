// Celery3D GPU - Common Types and Parameters
// Fixed-point format: S15.16 (32-bit signed, 16 fractional bits)

package celery_pkg;

    // Screen parameters (matching Voodoo 1)
    parameter SCREEN_WIDTH  = 640;
    parameter SCREEN_HEIGHT = 480;

    // Fixed-point configuration
    // S15.16 format: 1 sign + 15 integer + 16 fractional = 32 bits
    parameter FP_INT_BITS  = 16;  // Including sign
    parameter FP_FRAC_BITS = 16;
    parameter FP_TOTAL_BITS = FP_INT_BITS + FP_FRAC_BITS;

    // Fixed-point type
    typedef logic signed [FP_TOTAL_BITS-1:0] fp32_t;

    // Screen coordinate type (12 bits = 0-4095, plenty for 640x480)
    typedef logic [11:0] screen_coord_t;

    // Color types
    typedef logic [4:0]  red_t;    // 5 bits
    typedef logic [5:0]  green_t;  // 6 bits
    typedef logic [4:0]  blue_t;   // 5 bits
    typedef logic [15:0] rgb565_t; // Packed RGB565

    // Vertex structure (screen space, after CPU transformation)
    typedef struct packed {
        fp32_t x;           // Screen X (fixed-point for sub-pixel precision)
        fp32_t y;           // Screen Y
        fp32_t z;           // Depth (0 = near, 1 = far)
        fp32_t w;           // 1/z for perspective correction
        fp32_t u;           // Texture U
        fp32_t v;           // Texture V
        fp32_t r;           // Red (0.0 - 1.0)
        fp32_t g;           // Green
        fp32_t b;           // Blue
    } vertex_t;

    // Edge equation coefficients
    // Edge equation: E(x,y) = A*x + B*y + C
    // Pixel is inside if E >= 0 (for CCW winding)
    typedef struct packed {
        fp32_t a;           // dY coefficient (y0 - y1)
        fp32_t b;           // dX coefficient (x1 - x0)
        fp32_t c;           // Constant term
        logic  top_left;    // Is this a top or left edge?
    } edge_t;

    // Triangle setup result
    typedef struct packed {
        edge_t e0, e1, e2;  // Three edge equations

        // Bounding box (integer screen coords)
        screen_coord_t min_x, min_y;
        screen_coord_t max_x, max_y;

        // Attribute gradients (per-pixel deltas)
        fp32_t dzdx, dzdy;  // Depth
        fp32_t dwdx, dwdy;  // 1/z
        fp32_t dudx, dudy;  // Texture U (perspective-corrected: u/z)
        fp32_t dvdx, dvdy;  // Texture V
        fp32_t drdx, drdy;  // Red
        fp32_t dgdx, dgdy;  // Green
        fp32_t dbdx, dbdy;  // Blue

        // Starting values at v0
        fp32_t z0, w0;
        fp32_t uw0, vw0;    // u*w, v*w at v0
        fp32_t rw0, gw0, bw0;
        fp32_t x0, y0;      // Reference point for interpolation

        logic valid;        // Triangle is valid (non-degenerate)
        logic ccw;          // Counter-clockwise winding
    } triangle_setup_t;

    // Fragment output from rasterizer
    typedef struct packed {
        screen_coord_t x, y;
        fp32_t z;           // Depth for z-buffer test
        fp32_t u, v;        // Texture coordinates (perspective-corrected)
        fp32_t r, g, b;     // Interpolated color
        logic  valid;       // Fragment is valid
    } fragment_t;

    // Fixed-point conversion functions
    function automatic fp32_t int_to_fp(input int val);
        return fp32_t'(val) << FP_FRAC_BITS;
    endfunction

    function automatic int fp_to_int(input fp32_t val);
        return int'(val >>> FP_FRAC_BITS);  // Arithmetic shift for signed
    endfunction

    // Fixed-point multiplication: (a * b) >> FRAC_BITS
    // Result is 64-bit intermediate, then truncated
    function automatic fp32_t fp_mul(input fp32_t a, input fp32_t b);
        logic signed [63:0] product;
        product = 64'(a) * 64'(b);
        return fp32_t'(product >>> FP_FRAC_BITS);
    endfunction

    // Fixed-point constants
    parameter fp32_t FP_ZERO = 32'h00000000;
    parameter fp32_t FP_ONE  = 32'h00010000;  // 1.0 in S15.16
    parameter fp32_t FP_HALF = 32'h00008000;  // 0.5 in S15.16

    // RGB565 packing/unpacking
    function automatic rgb565_t pack_rgb565(input red_t r, input green_t g, input blue_t b);
        return {r, g, b};
    endfunction

    function automatic red_t unpack_red(input rgb565_t c);
        return c[15:11];
    endfunction

    function automatic green_t unpack_green(input rgb565_t c);
        return c[10:5];
    endfunction

    function automatic blue_t unpack_blue(input rgb565_t c);
        return c[4:0];
    endfunction

endpackage
