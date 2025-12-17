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

    // Fixed-point type (standard 32-bit for attributes)
    typedef logic signed [FP_TOTAL_BITS-1:0] fp32_t;

    // Wide fixed-point type for edge equation computations
    // S31.16 format: handles products of screen coordinates without overflow
    // Needed because edge constant C = x0*y1 - x1*y0 can exceed 32 bits
    parameter FP_WIDE_BITS = 48;
    typedef logic signed [FP_WIDE_BITS-1:0] fp48_t;

    // Screen coordinate type (12 bits = 0-4095, plenty for 640x480)
    typedef logic [11:0] screen_coord_t;

    // Color types
    typedef logic [4:0]  red_t;    // 5 bits
    typedef logic [5:0]  green_t;  // 6 bits
    typedef logic [4:0]  blue_t;   // 5 bits
    typedef logic [15:0] rgb565_t; // Packed RGB565

    // Depth comparison functions (Glide GR_CMP_* compatible)
    typedef enum logic [2:0] {
        GR_CMP_NEVER    = 3'b000,  // Never pass
        GR_CMP_LESS     = 3'b001,  // Pass if z_new < z_buffer
        GR_CMP_EQUAL    = 3'b010,  // Pass if z_new == z_buffer
        GR_CMP_LEQUAL   = 3'b011,  // Pass if z_new <= z_buffer
        GR_CMP_GREATER  = 3'b100,  // Pass if z_new > z_buffer
        GR_CMP_NOTEQUAL = 3'b101,  // Pass if z_new != z_buffer
        GR_CMP_GEQUAL   = 3'b110,  // Pass if z_new >= z_buffer
        GR_CMP_ALWAYS   = 3'b111   // Always pass
    } depth_func_t;

    // Alpha channel type (8-bit)
    typedef logic [7:0] alpha_t;

    // Blend factors (Glide GR_BLEND_* compatible - 12 factors)
    typedef enum logic [3:0] {
        GR_BLEND_ZERO                = 4'h0,
        GR_BLEND_SRC_ALPHA           = 4'h1,
        GR_BLEND_SRC_COLOR           = 4'h2,
        GR_BLEND_DST_ALPHA           = 4'h3,
        GR_BLEND_DST_COLOR           = 4'h4,
        GR_BLEND_ONE                 = 4'h5,
        GR_BLEND_ONE_MINUS_SRC_ALPHA = 4'h6,
        GR_BLEND_ONE_MINUS_SRC_COLOR = 4'h7,
        GR_BLEND_ONE_MINUS_DST_ALPHA = 4'h8,
        GR_BLEND_ONE_MINUS_DST_COLOR = 4'h9,
        GR_BLEND_ALPHA_SATURATE      = 4'hA,
        GR_BLEND_PREFOG_COLOR        = 4'hB   // Reserved for fog
    } blend_factor_t;

    // Alpha source selection
    typedef enum logic [1:0] {
        ALPHA_SRC_TEXTURE  = 2'b00,  // From RGBA4444 texture
        ALPHA_SRC_VERTEX   = 2'b01,  // From vertex interpolation
        ALPHA_SRC_CONSTANT = 2'b10,  // From constant register
        ALPHA_SRC_ONE      = 2'b11   // Always 1.0 (fully opaque)
    } alpha_source_t;

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
        fp32_t a;           // Alpha (0.0 - 1.0)
    } vertex_t;

    // Edge equation coefficients
    // Edge equation: E(x,y) = A*x + B*y + C
    // Pixel is inside if E >= 0 (for CCW winding)
    // Using fp48_t (wide) for all coefficients to prevent overflow
    // when evaluating edge equations at screen coordinates
    typedef struct packed {
        fp48_t a;           // dY coefficient (y0 - y1)
        fp48_t b;           // dX coefficient (x1 - x0)
        fp48_t c;           // Constant term
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
        fp32_t dadx, dady;  // Alpha

        // Starting values at v0
        fp32_t z0, w0;
        fp32_t uw0, vw0;    // u*w, v*w at v0
        fp32_t rw0, gw0, bw0;
        fp32_t aw0;         // a*w at v0
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
        fp32_t a;           // Interpolated alpha
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
    // Result is 64-bit intermediate, then truncated to 32 bits
    // Vivado will auto-infer DSP48 blocks for this multiplication
    function automatic fp32_t fp_mul(input fp32_t a, input fp32_t b);
        logic signed [63:0] product;
        product = 64'(a) * 64'(b);
        return fp32_t'(product >>> FP_FRAC_BITS);
    endfunction

    // Fixed-point division: (a << FRAC_BITS) / b
    // Returns a/b in fixed-point format
    // Note: Returns 0 if b is 0 to avoid divide-by-zero
    function automatic fp32_t fp_div(input fp32_t a, input fp32_t b);
        logic signed [63:0] numerator;
        logic signed [63:0] result;
        if (b == 0)
            return FP_ZERO;
        numerator = 64'(a) <<< FP_FRAC_BITS;
        result = numerator / 64'(b);
        return fp32_t'(result);
    endfunction

    // Compute attribute gradient with full precision
    // gradient = (diff1*delta1 - diff2*delta2) / area
    // Uses 64-bit intermediates to avoid overflow for large triangles
    function automatic fp32_t fp_gradient(
        input fp32_t diff1, input fp32_t delta1,
        input fp32_t diff2, input fp32_t delta2,
        input logic signed [63:0] area
    );
        logic signed [63:0] term1, term2, numerator, result;
        if (area == 0)
            return FP_ZERO;
        // Compute products with full precision
        term1 = (64'(diff1) * 64'(delta1)) >>> FP_FRAC_BITS;
        term2 = (64'(diff2) * 64'(delta2)) >>> FP_FRAC_BITS;
        numerator = term1 - term2;
        // Divide by area: shift numerator up, then divide
        result = (numerator <<< FP_FRAC_BITS) / area;
        return fp32_t'(result);
    endfunction

    // Wide fixed-point multiplication returning 64-bit result
    // For computing area and other large intermediate values
    function automatic logic signed [63:0] fp_mul64(input fp32_t a, input fp32_t b);
        logic signed [63:0] product;
        product = 64'(a) * 64'(b);
        return product >>> FP_FRAC_BITS;
    endfunction

    // Wide fixed-point multiplication: returns 48-bit result
    // Used for edge equation computations where products can exceed 32 bits
    function automatic fp48_t fp_mul_wide(input fp32_t a, input fp32_t b);
        logic signed [63:0] product;
        product = 64'(a) * 64'(b);
        return fp48_t'(product >>> FP_FRAC_BITS);
    endfunction

    // Sign-extend fp32_t to fp48_t
    function automatic fp48_t fp32_to_fp48(input fp32_t val);
        return fp48_t'(val);  // Sign extension happens automatically
    endfunction

    // Multiply fp48_t by fp32_t, return fp48_t
    // Used for edge equation evaluation: E = A*x + B*y + C
    // where A,B,C are fp48_t and x,y are fp32_t
    function automatic fp48_t fp48_mul_fp32(input fp48_t a, input fp32_t b);
        logic signed [95:0] product;
        product = 96'(a) * 96'(signed'(b));
        return fp48_t'(product >>> FP_FRAC_BITS);
    endfunction

    // Wide fixed-point constant zero
    parameter fp48_t FP48_ZERO = 48'h0;
    parameter fp48_t FP48_HALF = 48'h000000008000;  // 0.5 in S31.16

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
