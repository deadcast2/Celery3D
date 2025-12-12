// Celery3D GPU - Triangle Setup Unit
// Computes edge equations and attribute gradients from three vertices
// This is a multi-cycle operation (division is expensive)

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

    // State machine
    typedef enum logic [2:0] {
        IDLE,
        CALC_EDGES,
        CALC_AREA,
        CALC_GRADIENTS,
        CALC_BBOX,
        DONE
    } state_t;

    state_t state, next_state;

    // Intermediate calculations
    fp32_t area2;           // 2x triangle area (signed)
    fp32_t inv_area2;       // 1 / area2 (computed via iterative division)

    // Edge deltas
    fp32_t dx01, dy01, dx02, dy02, dx12, dy12;

    // Division state (iterative Newton-Raphson or shift-subtract)
    logic [5:0] div_count;
    fp32_t div_result;

    // Registered outputs
    triangle_setup_t setup_reg;

    // Combinational: compute edge deltas
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
            IDLE:        if (start) next_state = CALC_EDGES;
            CALC_EDGES:  next_state = CALC_AREA;
            CALC_AREA:   next_state = CALC_GRADIENTS;
            CALC_GRADIENTS: if (div_count == 0) next_state = CALC_BBOX;
            CALC_BBOX:   next_state = DONE;
            DONE:        next_state = IDLE;
            default:     next_state = IDLE;
        endcase
    end

    // Main computation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            setup_reg <= '0;
            area2 <= FP_ZERO;
            div_count <= '0;
            div_result <= FP_ZERO;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        // Initialize division counter
                        div_count <= 6'd32;  // 32 iterations for division
                    end
                end

                CALC_EDGES: begin
                    // Edge 0: v0 -> v1
                    // E0(x,y) = (y0-y1)*x + (x1-x0)*y + (x0*y1 - x1*y0)
                    // Using wide types (fp48_t) to prevent overflow
                    setup_reg.e0.a <= fp32_to_fp48(v0.y - v1.y);
                    setup_reg.e0.b <= fp32_to_fp48(v1.x - v0.x);
                    setup_reg.e0.c <= fp_mul_wide(v0.x, v1.y) - fp_mul_wide(v1.x, v0.y);
                    // Top edge: horizontal and v0 right of v1
                    // Left edge: going up (dy > 0)
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
                    // 2x area = (v1-v0) cross (v2-v0)
                    // = dx01 * dy02 - dx02 * dy01
                    automatic fp32_t computed_area2 = fp_mul(dx01, dy02) - fp_mul(dx02, dy01);
                    area2 <= computed_area2;

                    // Check for degenerate triangle (use computed value, not registered)
                    setup_reg.valid <= (computed_area2 != FP_ZERO);
                    // ccw flag determines inside test polarity:
                    // - If area2 > 0: interior has E > 0, use CCW test (E > 0)
                    // - If area2 < 0: interior has E < 0, use CW test (E < 0)
                    setup_reg.ccw <= (computed_area2 > 0);

                    // Store starting attribute values
                    setup_reg.z0 <= v0.z;
                    setup_reg.w0 <= v0.w;
                    setup_reg.uw0 <= fp_mul(v0.u, v0.w);
                    setup_reg.vw0 <= fp_mul(v0.v, v0.w);
                    setup_reg.rw0 <= fp_mul(v0.r, v0.w);
                    setup_reg.gw0 <= fp_mul(v0.g, v0.w);
                    setup_reg.bw0 <= fp_mul(v0.b, v0.w);
                end

                CALC_GRADIENTS: begin
                    // Simplified gradient calculation
                    // For proper implementation, we'd divide by area2
                    // Here we use a simplified approximation for initial testing

                    if (div_count > 0) begin
                        div_count <= div_count - 1;

                        // Iterative reciprocal calculation would go here
                        // For now, we'll use a lookup table approach in synthesis
                        // or accept the approximation for simulation
                    end

                    // Approximate gradients (will refine with proper division)
                    // dA/dx = (dA01 * dy02 - dA02 * dy01) / area2
                    if (div_count == 1) begin
                        // For simulation, we'll compute gradients directly
                        // In hardware, this would use the reciprocal

                        // Depth gradients
                        setup_reg.dzdx <= fp_mul(v1.z - v0.z, dy02) -
                                          fp_mul(v2.z - v0.z, dy01);
                        setup_reg.dzdy <= fp_mul(v2.z - v0.z, dx01) -
                                          fp_mul(v1.z - v0.z, dx02);

                        // W gradients
                        setup_reg.dwdx <= fp_mul(v1.w - v0.w, dy02) -
                                          fp_mul(v2.w - v0.w, dy01);
                        setup_reg.dwdy <= fp_mul(v2.w - v0.w, dx01) -
                                          fp_mul(v1.w - v0.w, dx02);
                    end
                end

                CALC_BBOX: begin
                    // Compute bounding box
                    // Convert fixed-point to integer screen coords
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

                DONE: begin
                    // Output is ready
                end
            endcase
        end
    end

    // Output assignments
    assign setup = setup_reg;
    assign done = (state == DONE);
    assign busy = (state != IDLE);

endmodule
