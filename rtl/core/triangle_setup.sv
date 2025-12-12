// Celery3D GPU - Triangle Setup Unit
// Computes edge equations and attribute gradients from three vertices
// Synthesis-friendly: uses iterative division and serialized gradient computation

module triangle_setup
    import celery_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // Input vertices
    input  vertex_t     v0, v1, v2,
    input  logic        start,

    // Output
    output triangle_setup_t setup,
    output logic        done,
    output logic        busy
);

    // State machine - expanded for pipelined computation
    typedef enum logic [3:0] {
        IDLE,
        CALC_EDGES,
        CALC_AREA,
        CALC_RECIP_INIT,    // Initialize reciprocal computation
        CALC_RECIP,         // Iterative reciprocal (Newton-Raphson)
        CALC_GRAD_Z,        // Compute z gradients
        CALC_GRAD_W,        // Compute w gradients
        CALC_GRAD_R,        // Compute r gradients
        CALC_GRAD_G,        // Compute g gradients
        CALC_GRAD_B,        // Compute b gradients
        CALC_BBOX,
        DONE_STATE
    } state_t;

    state_t state, next_state;

    // Intermediate calculations
    logic signed [63:0] area2;      // 2x triangle area (64-bit to avoid overflow)
    logic signed [63:0] inv_area2;  // 1/area2 in fixed-point (computed iteratively)

    // Edge deltas (registered to break combinational paths)
    fp32_t dx01_r, dy01_r, dx02_r, dy02_r;

    // Attribute differences (pre-computed and registered)
    fp32_t dz01, dz02;      // z differences
    fp32_t dw01, dw02;      // w differences
    fp32_t drw01, drw02;    // r*w differences
    fp32_t dgw01, dgw02;    // g*w differences
    fp32_t dbw01, dbw02;    // b*w differences

    // Newton-Raphson iteration state
    logic [4:0] recip_iter;         // Iteration counter (16 iterations)
    logic signed [63:0] recip_x;    // Current estimate of 1/area2

    // Registered outputs
    triangle_setup_t setup_reg;

    // Combinational: compute edge deltas (simple subtraction, OK for one cycle)
    fp32_t dx01, dy01, dx02, dy02, dx12, dy12;
    always_comb begin
        dx01 = v1.x - v0.x;
        dy01 = v1.y - v0.y;
        dx02 = v2.x - v0.x;
        dy02 = v2.y - v0.y;
        dx12 = v2.x - v1.x;
        dy12 = v2.y - v1.y;
    end

    // State machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE:            if (start) next_state = CALC_EDGES;
            CALC_EDGES:      next_state = CALC_AREA;
            CALC_AREA:       next_state = CALC_RECIP_INIT;
            CALC_RECIP_INIT: next_state = CALC_RECIP;
            CALC_RECIP:      if (recip_iter == 0) next_state = CALC_GRAD_Z;
            CALC_GRAD_Z:     next_state = CALC_GRAD_W;
            CALC_GRAD_W:     next_state = CALC_GRAD_R;
            CALC_GRAD_R:     next_state = CALC_GRAD_G;
            CALC_GRAD_G:     next_state = CALC_GRAD_B;
            CALC_GRAD_B:     next_state = CALC_BBOX;
            CALC_BBOX:       next_state = DONE_STATE;
            DONE_STATE:      next_state = IDLE;
            default:         next_state = IDLE;
        endcase
    end

    // Gradient computation helper - computes (diff1*delta1 - diff2*delta2) * inv_area
    // Uses registered inputs and outputs for synthesis
    // NOTE: inv_area is scaled as 2^64/area2, so we shift by 48 bits (not 16)
    function automatic fp32_t compute_gradient_x(
        input fp32_t diff1, input fp32_t diff2,
        input fp32_t dy02_in, input fp32_t dy01_in,
        input logic signed [63:0] inv_area
    );
        logic signed [63:0] term1, term2, numerator;
        logic signed [127:0] result_wide;
        // diff1 * dy02 - diff2 * dy01
        term1 = (64'(diff1) * 64'(dy02_in)) >>> FP_FRAC_BITS;
        term2 = (64'(diff2) * 64'(dy01_in)) >>> FP_FRAC_BITS;
        numerator = term1 - term2;
        // Multiply by inverse area (scaled by 2^64/area2, shift by 48)
        result_wide = (128'(numerator) * 128'(inv_area)) >>> 48;
        return fp32_t'(result_wide);
    endfunction

    function automatic fp32_t compute_gradient_y(
        input fp32_t diff1, input fp32_t diff2,
        input fp32_t dx01_in, input fp32_t dx02_in,
        input logic signed [63:0] inv_area
    );
        logic signed [63:0] term1, term2, numerator;
        logic signed [127:0] result_wide;
        // diff2 * dx01 - diff1 * dx02
        term1 = (64'(diff2) * 64'(dx01_in)) >>> FP_FRAC_BITS;
        term2 = (64'(diff1) * 64'(dx02_in)) >>> FP_FRAC_BITS;
        numerator = term1 - term2;
        // Multiply by inverse area (scaled by 2^64/area2, shift by 48)
        result_wide = (128'(numerator) * 128'(inv_area)) >>> 48;
        return fp32_t'(result_wide);
    endfunction

    // Main computation - one operation per state for timing closure
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            setup_reg <= '0;
            area2 <= 64'h0;
            inv_area2 <= 64'h0;
            recip_iter <= '0;
            recip_x <= 64'h0;
            dx01_r <= FP_ZERO;
            dy01_r <= FP_ZERO;
            dx02_r <= FP_ZERO;
            dy02_r <= FP_ZERO;
            dz01 <= FP_ZERO;
            dz02 <= FP_ZERO;
            dw01 <= FP_ZERO;
            dw02 <= FP_ZERO;
            drw01 <= FP_ZERO;
            drw02 <= FP_ZERO;
            dgw01 <= FP_ZERO;
            dgw02 <= FP_ZERO;
            dbw01 <= FP_ZERO;
            dbw02 <= FP_ZERO;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        // Register edge deltas for use in later states
                        dx01_r <= dx01;
                        dy01_r <= dy01;
                        dx02_r <= dx02;
                        dy02_r <= dy02;
                    end
                end

                CALC_EDGES: begin
                    // Edge 0: v0 -> v1
                    setup_reg.e0.a <= fp32_to_fp48(v0.y - v1.y);
                    setup_reg.e0.b <= fp32_to_fp48(v1.x - v0.x);
                    setup_reg.e0.c <= fp_mul_wide(v0.x, v1.y) - fp_mul_wide(v1.x, v0.y);
                    setup_reg.e0.top_left <= ((v0.y == v1.y) && (v1.x > v0.x)) ||
                                             (v0.y > v1.y);

                    // Edge 1: v1 -> v2
                    setup_reg.e1.a <= fp32_to_fp48(v1.y - v2.y);
                    setup_reg.e1.b <= fp32_to_fp48(v2.x - v1.x);
                    setup_reg.e1.c <= fp_mul_wide(v1.x, v2.y) - fp_mul_wide(v2.x, v1.y);
                    setup_reg.e1.top_left <= ((v1.y == v2.y) && (v2.x > v1.x)) ||
                                             (v1.y > v2.y);

                    // Edge 2: v2 -> v0
                    setup_reg.e2.a <= fp32_to_fp48(v2.y - v0.y);
                    setup_reg.e2.b <= fp32_to_fp48(v0.x - v2.x);
                    setup_reg.e2.c <= fp_mul_wide(v2.x, v0.y) - fp_mul_wide(v0.x, v2.y);
                    setup_reg.e2.top_left <= ((v2.y == v0.y) && (v0.x > v2.x)) ||
                                             (v2.y > v0.y);

                    // Store reference point
                    setup_reg.x0 <= v0.x;
                    setup_reg.y0 <= v0.y;
                end

                CALC_AREA: begin
                    // Compute area using registered deltas
                    automatic logic signed [63:0] computed_area2;
                    computed_area2 = fp_mul64(dx01_r, dy02_r) - fp_mul64(dx02_r, dy01_r);
                    area2 <= computed_area2;

                    // Check for degenerate triangle
                    setup_reg.valid <= (computed_area2 != 64'h0);
                    setup_reg.ccw <= (computed_area2 > 0);

                    // Store starting attribute values
                    setup_reg.z0 <= v0.z;
                    setup_reg.w0 <= v0.w;
                    setup_reg.uw0 <= fp_mul(v0.u, v0.w);
                    setup_reg.vw0 <= fp_mul(v0.v, v0.w);
                    setup_reg.rw0 <= fp_mul(v0.r, v0.w);
                    setup_reg.gw0 <= fp_mul(v0.g, v0.w);
                    setup_reg.bw0 <= fp_mul(v0.b, v0.w);

                    // Pre-compute attribute differences for gradient calculation
                    dz01 <= v1.z - v0.z;
                    dz02 <= v2.z - v0.z;
                    dw01 <= v1.w - v0.w;
                    dw02 <= v2.w - v0.w;
                    drw01 <= fp_mul(v1.r, v1.w) - fp_mul(v0.r, v0.w);
                    drw02 <= fp_mul(v2.r, v2.w) - fp_mul(v0.r, v0.w);
                    dgw01 <= fp_mul(v1.g, v1.w) - fp_mul(v0.g, v0.w);
                    dgw02 <= fp_mul(v2.g, v2.w) - fp_mul(v0.g, v0.w);
                    dbw01 <= fp_mul(v1.b, v1.w) - fp_mul(v0.b, v0.w);
                    dbw02 <= fp_mul(v2.b, v2.w) - fp_mul(v0.b, v0.w);
                end

                CALC_RECIP_INIT: begin
                    // Newton-Raphson to compute: recip_x = 2^64 / area2
                    // This gives enough precision for gradient calculation
                    // Formula: x_{n+1} = x_n * (2 - area2 * x_n / 2^64)
                    recip_iter <= 5'd16;  // 16 iterations for convergence

                    // Initial estimate based on area2 magnitude
                    // For |area2| around 2^32, we want x around 2^32
                    // Use a simple power-of-2 estimate: 2^32 with correct sign
                    if (area2 > 0) begin
                        recip_x <= 64'h0000_0001_0000_0000;  // 2^32
                    end else begin
                        recip_x <= -64'sh0000_0001_0000_0000; // -2^32
                    end
                end

                CALC_RECIP: begin
                    // Newton-Raphson iteration: x = x * (2 - area2 * x / 2^64)
                    // We compute in Q31.32 for the intermediate (area2 * x / 2^32)
                    // At convergence: area2 * x / 2^64 = 1, so (area2 * x) >> 32 = 2^32
                    if (recip_iter > 0) begin
                        automatic logic signed [127:0] ax_wide, two_minus_ax, new_x;
                        // Compute (area2 * x) >> 32, which converges to 2^32 (representing 1.0 in Q31.32)
                        ax_wide = (128'(area2) * 128'(recip_x)) >>> 32;
                        // 2.0 in Q31.32 is 2 * 2^32 = 0x2_0000_0000
                        two_minus_ax = (128'sh2_0000_0000) - ax_wide;
                        // x * (2 - ax) >> 32 to maintain scaling
                        new_x = (128'(recip_x) * two_minus_ax) >>> 32;
                        recip_x <= 64'(new_x);
                        recip_iter <= recip_iter - 1;
                    end else begin
                        inv_area2 <= recip_x;
                    end
                end

                CALC_GRAD_Z: begin
                    // Depth gradients using pre-computed differences and reciprocal
                    setup_reg.dzdx <= compute_gradient_x(dz01, dz02, dy02_r, dy01_r, inv_area2);
                    setup_reg.dzdy <= compute_gradient_y(dz01, dz02, dx01_r, dx02_r, inv_area2);
                end

                CALC_GRAD_W: begin
                    // W gradients
                    setup_reg.dwdx <= compute_gradient_x(dw01, dw02, dy02_r, dy01_r, inv_area2);
                    setup_reg.dwdy <= compute_gradient_y(dw01, dw02, dx01_r, dx02_r, inv_area2);
                end

                CALC_GRAD_R: begin
                    // Red gradients (perspective-corrected)
                    setup_reg.drdx <= compute_gradient_x(drw01, drw02, dy02_r, dy01_r, inv_area2);
                    setup_reg.drdy <= compute_gradient_y(drw01, drw02, dx01_r, dx02_r, inv_area2);
                end

                CALC_GRAD_G: begin
                    // Green gradients
                    setup_reg.dgdx <= compute_gradient_x(dgw01, dgw02, dy02_r, dy01_r, inv_area2);
                    setup_reg.dgdy <= compute_gradient_y(dgw01, dgw02, dx01_r, dx02_r, inv_area2);
                end

                CALC_GRAD_B: begin
                    // Blue gradients
                    setup_reg.dbdx <= compute_gradient_x(dbw01, dbw02, dy02_r, dy01_r, inv_area2);
                    setup_reg.dbdy <= compute_gradient_y(dbw01, dbw02, dx01_r, dx02_r, inv_area2);
                end

                CALC_BBOX: begin
                    // Compute bounding box
                    automatic int x0i = fp_to_int(v0.x);
                    automatic int y0i = fp_to_int(v0.y);
                    automatic int x1i = fp_to_int(v1.x);
                    automatic int y1i = fp_to_int(v1.y);
                    automatic int x2i = fp_to_int(v2.x);
                    automatic int y2i = fp_to_int(v2.y);

                    automatic int minx = (x0i < x1i) ? ((x0i < x2i) ? x0i : x2i) :
                                                       ((x1i < x2i) ? x1i : x2i);
                    automatic int miny = (y0i < y1i) ? ((y0i < y2i) ? y0i : y2i) :
                                                       ((y1i < y2i) ? y1i : y2i);
                    automatic int maxx = (x0i > x1i) ? ((x0i > x2i) ? x0i : x2i) :
                                                       ((x1i > x2i) ? x1i : x2i);
                    automatic int maxy = (y0i > y1i) ? ((y0i > y2i) ? y0i : y2i) :
                                                       ((y1i > y2i) ? y1i : y2i);

                    // Clamp to screen
                    setup_reg.min_x <= (minx < 0) ? 0 :
                                       (minx >= SCREEN_WIDTH) ? SCREEN_WIDTH-1 :
                                       screen_coord_t'(minx);
                    setup_reg.min_y <= (miny < 0) ? 0 :
                                       (miny >= SCREEN_HEIGHT) ? SCREEN_HEIGHT-1 :
                                       screen_coord_t'(miny);
                    setup_reg.max_x <= (maxx < 0) ? 0 :
                                       (maxx >= SCREEN_WIDTH) ? SCREEN_WIDTH-1 :
                                       screen_coord_t'(maxx);
                    setup_reg.max_y <= (maxy < 0) ? 0 :
                                       (maxy >= SCREEN_HEIGHT) ? SCREEN_HEIGHT-1 :
                                       screen_coord_t'(maxy);
                end

                DONE_STATE: begin
                    // Output is ready
                end
            endcase
        end
    end

    // Output assignments
    assign setup = setup_reg;
    assign done = (state == DONE_STATE);
    assign busy = (state != IDLE);

endmodule
