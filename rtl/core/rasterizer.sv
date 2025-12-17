// Celery3D GPU - Rasterizer Core
// Iterates over triangle bounding box, tests pixels against edge equations,
// interpolates attributes, and outputs fragments
// Synthesis-friendly: pipelined initialization to meet timing

module rasterizer
    import celery_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // Triangle setup input
    input  triangle_setup_t tri_in,
    input  logic        start,

    // Fragment output (to perspective correction or pixel ops)
    output fragment_t   frag_out,
    output fp32_t       w_out,          // Interpolated w for perspective correction
    output logic        frag_valid,
    input  logic        frag_ready,     // Backpressure from downstream

    // Status
    output logic        done,
    output logic        busy
);

    // State machine - expanded for pipelined initialization
    typedef enum logic [2:0] {
        IDLE,
        INIT_EDGES,     // Evaluate edge equations at start position
        INIT_ATTR,      // Initialize attribute interpolants
        RASTERIZE,
        NEXT_ROW,
        DONE_STATE
    } state_t;

    state_t state, next_state;

    // Current pixel position
    screen_coord_t cur_x, cur_y;

    // Edge equation values at current pixel (wide to prevent overflow)
    fp48_t e0_val, e1_val, e2_val;

    // Edge equation increments (cached from triangle setup, wide)
    fp48_t e0_a, e1_a, e2_a;  // X increments
    fp48_t e0_b, e1_b, e2_b;  // Y increments

    // Row start values (for Y stepping, wide)
    fp48_t e0_row, e1_row, e2_row;

    // Interpolated attributes at current pixel
    fp32_t cur_z, cur_w;
    fp32_t cur_uw, cur_vw;
    fp32_t cur_rw, cur_gw, cur_bw;
    fp32_t cur_aw;

    // Attribute row start values
    fp32_t z_row, w_row;
    fp32_t uw_row, vw_row;
    fp32_t rw_row, gw_row, bw_row;
    fp32_t aw_row;

    // Triangle winding (determines inside test polarity)
    logic ccw;

    // Pre-computed values (registered to break combinational paths)
    fp32_t init_px_r, init_py_r;    // Pixel center at bounding box min
    fp32_t init_dx_r, init_dy_r;    // Delta from reference point

    // Check if pixel is inside all three edges
    logic inside_e0, inside_e1, inside_e2, inside_all;

    // Combinational init values (only used during IDLE->INIT transition)
    fp32_t init_px, init_py, init_dx, init_dy;
    always_comb begin
        init_px = int_to_fp(tri_in.min_x) + FP_HALF;
        init_py = int_to_fp(tri_in.min_y) + FP_HALF;
        init_dx = init_px - tri_in.x0;
        init_dy = init_py - tri_in.y0;
    end

    always_comb begin
        if (ccw) begin
            // CCW: inside when all edges >= 0
            inside_e0 = (e0_val > 0) || (e0_val == 0 && tri_in.e0.top_left);
            inside_e1 = (e1_val > 0) || (e1_val == 0 && tri_in.e1.top_left);
            inside_e2 = (e2_val > 0) || (e2_val == 0 && tri_in.e2.top_left);
        end else begin
            // CW: inside when all edges <= 0
            inside_e0 = (e0_val < 0) || (e0_val == 0 && !tri_in.e0.top_left);
            inside_e1 = (e1_val < 0) || (e1_val == 0 && !tri_in.e1.top_left);
            inside_e2 = (e2_val < 0) || (e2_val == 0 && !tri_in.e2.top_left);
        end
        inside_all = inside_e0 && inside_e1 && inside_e2;
    end

    // State machine transitions
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
            IDLE: begin
                if (start && tri_in.valid)
                    next_state = INIT_EDGES;
            end

            INIT_EDGES: begin
                next_state = INIT_ATTR;
            end

            INIT_ATTR: begin
                next_state = RASTERIZE;
            end

            RASTERIZE: begin
                // If we're outputting a fragment and downstream isn't ready, stall
                if (inside_all && !frag_ready) begin
                    next_state = RASTERIZE;  // Stall
                end else if (cur_x >= tri_in.max_x) begin
                    // End of row
                    if (cur_y >= tri_in.max_y)
                        next_state = DONE_STATE;
                    else
                        next_state = NEXT_ROW;
                end
                // else stay in RASTERIZE
            end

            NEXT_ROW: begin
                next_state = RASTERIZE;
            end

            DONE_STATE: begin
                next_state = IDLE;
            end
        endcase
    end

    // Main rasterization logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cur_x <= '0;
            cur_y <= '0;
            e0_val <= FP48_ZERO;
            e1_val <= FP48_ZERO;
            e2_val <= FP48_ZERO;
            e0_row <= FP48_ZERO;
            e1_row <= FP48_ZERO;
            e2_row <= FP48_ZERO;
            e0_a <= FP48_ZERO;
            e1_a <= FP48_ZERO;
            e2_a <= FP48_ZERO;
            e0_b <= FP48_ZERO;
            e1_b <= FP48_ZERO;
            e2_b <= FP48_ZERO;
            ccw <= 1'b1;
            cur_z <= FP_ZERO;
            cur_w <= FP_ZERO;
            cur_uw <= FP_ZERO;
            cur_vw <= FP_ZERO;
            cur_rw <= FP_ZERO;
            cur_gw <= FP_ZERO;
            cur_bw <= FP_ZERO;
            cur_aw <= FP_ZERO;
            z_row <= FP_ZERO;
            w_row <= FP_ZERO;
            uw_row <= FP_ZERO;
            vw_row <= FP_ZERO;
            rw_row <= FP_ZERO;
            gw_row <= FP_ZERO;
            bw_row <= FP_ZERO;
            aw_row <= FP_ZERO;
            init_px_r <= FP_ZERO;
            init_py_r <= FP_ZERO;
            init_dx_r <= FP_ZERO;
            init_dy_r <= FP_ZERO;
        end else begin
            case (state)
                IDLE: begin
                    if (start && tri_in.valid) begin
                        // Cache edge coefficients
                        e0_a <= tri_in.e0.a;
                        e1_a <= tri_in.e1.a;
                        e2_a <= tri_in.e2.a;
                        e0_b <= tri_in.e0.b;
                        e1_b <= tri_in.e1.b;
                        e2_b <= tri_in.e2.b;
                        ccw <= tri_in.ccw;

                        // Start position
                        cur_x <= tri_in.min_x;
                        cur_y <= tri_in.min_y;

                        // Register init values for use in next states
                        init_px_r <= init_px;
                        init_py_r <= init_py;
                        init_dx_r <= init_dx;
                        init_dy_r <= init_dy;
                    end
                end

                INIT_EDGES: begin
                    // Evaluate edge equations at (min_x + 0.5, min_y + 0.5)
                    // Uses registered init values
                    // E(x,y) = A*x + B*y + C (using wide arithmetic)
                    e0_val <= fp48_mul_fp32(tri_in.e0.a, init_px_r) +
                              fp48_mul_fp32(tri_in.e0.b, init_py_r) + tri_in.e0.c;
                    e1_val <= fp48_mul_fp32(tri_in.e1.a, init_px_r) +
                              fp48_mul_fp32(tri_in.e1.b, init_py_r) + tri_in.e1.c;
                    e2_val <= fp48_mul_fp32(tri_in.e2.a, init_px_r) +
                              fp48_mul_fp32(tri_in.e2.b, init_py_r) + tri_in.e2.c;

                    // Also compute row start values
                    e0_row <= fp48_mul_fp32(tri_in.e0.a, init_px_r) +
                              fp48_mul_fp32(tri_in.e0.b, init_py_r) + tri_in.e0.c;
                    e1_row <= fp48_mul_fp32(tri_in.e1.a, init_px_r) +
                              fp48_mul_fp32(tri_in.e1.b, init_py_r) + tri_in.e1.c;
                    e2_row <= fp48_mul_fp32(tri_in.e2.a, init_px_r) +
                              fp48_mul_fp32(tri_in.e2.b, init_py_r) + tri_in.e2.c;
                end

                INIT_ATTR: begin
                    // Initialize attributes at starting position
                    // Uses registered init_dx_r, init_dy_r
                    cur_z <= tri_in.z0 + fp_mul(tri_in.dzdx, init_dx_r) + fp_mul(tri_in.dzdy, init_dy_r);
                    cur_w <= tri_in.w0 + fp_mul(tri_in.dwdx, init_dx_r) + fp_mul(tri_in.dwdy, init_dy_r);
                    cur_uw <= tri_in.uw0 + fp_mul(tri_in.dudx, init_dx_r) + fp_mul(tri_in.dudy, init_dy_r);
                    cur_vw <= tri_in.vw0 + fp_mul(tri_in.dvdx, init_dx_r) + fp_mul(tri_in.dvdy, init_dy_r);
                    cur_rw <= tri_in.rw0 + fp_mul(tri_in.drdx, init_dx_r) + fp_mul(tri_in.drdy, init_dy_r);
                    cur_gw <= tri_in.gw0 + fp_mul(tri_in.dgdx, init_dx_r) + fp_mul(tri_in.dgdy, init_dy_r);
                    cur_bw <= tri_in.bw0 + fp_mul(tri_in.dbdx, init_dx_r) + fp_mul(tri_in.dbdy, init_dy_r);
                    cur_aw <= tri_in.aw0 + fp_mul(tri_in.dadx, init_dx_r) + fp_mul(tri_in.dady, init_dy_r);

                    z_row <= tri_in.z0 + fp_mul(tri_in.dzdx, init_dx_r) + fp_mul(tri_in.dzdy, init_dy_r);
                    w_row <= tri_in.w0 + fp_mul(tri_in.dwdx, init_dx_r) + fp_mul(tri_in.dwdy, init_dy_r);
                    uw_row <= tri_in.uw0 + fp_mul(tri_in.dudx, init_dx_r) + fp_mul(tri_in.dudy, init_dy_r);
                    vw_row <= tri_in.vw0 + fp_mul(tri_in.dvdx, init_dx_r) + fp_mul(tri_in.dvdy, init_dy_r);
                    rw_row <= tri_in.rw0 + fp_mul(tri_in.drdx, init_dx_r) + fp_mul(tri_in.drdy, init_dy_r);
                    gw_row <= tri_in.gw0 + fp_mul(tri_in.dgdx, init_dx_r) + fp_mul(tri_in.dgdy, init_dy_r);
                    bw_row <= tri_in.bw0 + fp_mul(tri_in.dbdx, init_dx_r) + fp_mul(tri_in.dbdy, init_dy_r);
                    aw_row <= tri_in.aw0 + fp_mul(tri_in.dadx, init_dx_r) + fp_mul(tri_in.dady, init_dy_r);
                end

                RASTERIZE: begin
                    // Don't advance if stalled
                    if (!inside_all || frag_ready) begin
                        if (cur_x < tri_in.max_x) begin
                            // Move to next pixel in row
                            cur_x <= cur_x + 1;

                            // Incremental edge update: E(x+1) = E(x) + A
                            e0_val <= e0_val + e0_a;
                            e1_val <= e1_val + e1_a;
                            e2_val <= e2_val + e2_a;

                            // Incremental attribute update (just additions - very fast)
                            cur_z <= cur_z + tri_in.dzdx;
                            cur_w <= cur_w + tri_in.dwdx;
                            cur_uw <= cur_uw + tri_in.dudx;
                            cur_vw <= cur_vw + tri_in.dvdx;
                            cur_rw <= cur_rw + tri_in.drdx;
                            cur_gw <= cur_gw + tri_in.dgdx;
                            cur_bw <= cur_bw + tri_in.dbdx;
                            cur_aw <= cur_aw + tri_in.dadx;
                        end
                    end
                end

                NEXT_ROW: begin
                    // Move to start of next row
                    cur_x <= tri_in.min_x;
                    cur_y <= cur_y + 1;

                    // Update row start values: E_row(y+1) = E_row(y) + B (just additions)
                    e0_row <= e0_row + e0_b;
                    e1_row <= e1_row + e1_b;
                    e2_row <= e2_row + e2_b;
                    e0_val <= e0_row + e0_b;
                    e1_val <= e1_row + e1_b;
                    e2_val <= e2_row + e2_b;

                    // Update attribute row values (just additions - very fast)
                    z_row <= z_row + tri_in.dzdy;
                    w_row <= w_row + tri_in.dwdy;
                    uw_row <= uw_row + tri_in.dudy;
                    vw_row <= vw_row + tri_in.dvdy;
                    rw_row <= rw_row + tri_in.drdy;
                    gw_row <= gw_row + tri_in.dgdy;
                    bw_row <= bw_row + tri_in.dbdy;
                    aw_row <= aw_row + tri_in.dady;

                    cur_z <= z_row + tri_in.dzdy;
                    cur_w <= w_row + tri_in.dwdy;
                    cur_uw <= uw_row + tri_in.dudy;
                    cur_vw <= vw_row + tri_in.dvdy;
                    cur_rw <= rw_row + tri_in.drdy;
                    cur_gw <= gw_row + tri_in.dgdy;
                    cur_bw <= bw_row + tri_in.dbdy;
                    cur_aw <= aw_row + tri_in.dady;
                end

                DONE_STATE: begin
                    // Nothing to do
                end
            endcase
        end
    end

    // Output fragment (perspective-incorrect attributes, corrected downstream)
    always_comb begin
        frag_out.x = cur_x;
        frag_out.y = cur_y;
        frag_out.z = cur_z;

        // Output perspective-incorrect values (attr * w)
        // These will be divided by w in the perspective_correct module
        frag_out.u = cur_uw;
        frag_out.v = cur_vw;
        frag_out.r = cur_rw;
        frag_out.g = cur_gw;
        frag_out.b = cur_bw;
        frag_out.a = cur_aw;

        frag_out.valid = (state == RASTERIZE) && inside_all;
    end

    assign w_out = cur_w;  // Output interpolated w for perspective correction
    assign frag_valid = frag_out.valid;
    assign done = (state == DONE_STATE);
    assign busy = (state != IDLE);

endmodule
