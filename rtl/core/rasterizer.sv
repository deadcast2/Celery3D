// Celery3D GPU - Rasterizer Core
// Iterates over triangle bounding box, tests pixels against edge equations,
// interpolates attributes, and outputs fragments

module rasterizer
    import celery_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // Triangle setup input
    input  triangle_setup_t tri_in,
    input  logic        start,

    // Fragment output (directly to framebuffer or pixel ops)
    output fragment_t   frag_out,
    output logic        frag_valid,
    input  logic        frag_ready,     // Backpressure from downstream

    // Status
    output logic        done,
    output logic        busy
);

    // State machine
    typedef enum logic [2:0] {
        IDLE,
        INIT_ROW,
        RASTERIZE,
        NEXT_ROW,
        DONE_STATE
    } state_t;

    state_t state, next_state;

    // Current pixel position
    screen_coord_t cur_x, cur_y;

    // Edge equation values at current pixel
    fp32_t e0_val, e1_val, e2_val;

    // Edge equation increments (cached from triangle setup)
    fp32_t e0_a, e1_a, e2_a;  // X increments
    fp32_t e0_b, e1_b, e2_b;  // Y increments

    // Row start values (for Y stepping)
    fp32_t e0_row, e1_row, e2_row;

    // Interpolated attributes at current pixel
    fp32_t cur_z, cur_w;
    fp32_t cur_uw, cur_vw;
    fp32_t cur_rw, cur_gw, cur_bw;

    // Attribute row start values
    fp32_t z_row, w_row;
    fp32_t uw_row, vw_row;
    fp32_t rw_row, gw_row, bw_row;

    // Triangle winding (determines inside test polarity)
    logic ccw;

    // Intermediate calculations (for avoiding automatic in always_ff)
    fp32_t init_px, init_py, init_dx, init_dy;

    // Check if pixel is inside all three edges
    logic inside_e0, inside_e1, inside_e2, inside_all;

    // Compute init values combinationally
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
                    next_state = INIT_ROW;
            end

            INIT_ROW: begin
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
            e0_val <= FP_ZERO;
            e1_val <= FP_ZERO;
            e2_val <= FP_ZERO;
            e0_row <= FP_ZERO;
            e1_row <= FP_ZERO;
            e2_row <= FP_ZERO;
            e0_a <= FP_ZERO;
            e1_a <= FP_ZERO;
            e2_a <= FP_ZERO;
            e0_b <= FP_ZERO;
            e1_b <= FP_ZERO;
            e2_b <= FP_ZERO;
            ccw <= 1'b1;
            cur_z <= FP_ZERO;
            cur_w <= FP_ZERO;
            cur_uw <= FP_ZERO;
            cur_vw <= FP_ZERO;
            cur_rw <= FP_ZERO;
            cur_gw <= FP_ZERO;
            cur_bw <= FP_ZERO;
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
                    end
                end

                INIT_ROW: begin
                    // Evaluate edge equations at (min_x + 0.5, min_y + 0.5)
                    // For pixel centers (init_px, init_py computed combinationally)

                    // E(x,y) = A*x + B*y + C
                    e0_val <= fp_mul(tri_in.e0.a, init_px) + fp_mul(tri_in.e0.b, init_py) + tri_in.e0.c;
                    e1_val <= fp_mul(tri_in.e1.a, init_px) + fp_mul(tri_in.e1.b, init_py) + tri_in.e1.c;
                    e2_val <= fp_mul(tri_in.e2.a, init_px) + fp_mul(tri_in.e2.b, init_py) + tri_in.e2.c;

                    // Also compute row start values
                    e0_row <= fp_mul(tri_in.e0.a, init_px) + fp_mul(tri_in.e0.b, init_py) + tri_in.e0.c;
                    e1_row <= fp_mul(tri_in.e1.a, init_px) + fp_mul(tri_in.e1.b, init_py) + tri_in.e1.c;
                    e2_row <= fp_mul(tri_in.e2.a, init_px) + fp_mul(tri_in.e2.b, init_py) + tri_in.e2.c;

                    // Initialize attributes at starting position
                    // (init_dx, init_dy computed combinationally)
                    cur_z <= tri_in.z0 + fp_mul(tri_in.dzdx, init_dx) + fp_mul(tri_in.dzdy, init_dy);
                    cur_w <= tri_in.w0 + fp_mul(tri_in.dwdx, init_dx) + fp_mul(tri_in.dwdy, init_dy);
                    cur_uw <= tri_in.uw0 + fp_mul(tri_in.dudx, init_dx) + fp_mul(tri_in.dudy, init_dy);
                    cur_vw <= tri_in.vw0 + fp_mul(tri_in.dvdx, init_dx) + fp_mul(tri_in.dvdy, init_dy);
                    cur_rw <= tri_in.rw0 + fp_mul(tri_in.drdx, init_dx) + fp_mul(tri_in.drdy, init_dy);
                    cur_gw <= tri_in.gw0 + fp_mul(tri_in.dgdx, init_dx) + fp_mul(tri_in.dgdy, init_dy);
                    cur_bw <= tri_in.bw0 + fp_mul(tri_in.dbdx, init_dx) + fp_mul(tri_in.dbdy, init_dy);

                    z_row <= tri_in.z0 + fp_mul(tri_in.dzdx, init_dx) + fp_mul(tri_in.dzdy, init_dy);
                    w_row <= tri_in.w0 + fp_mul(tri_in.dwdx, init_dx) + fp_mul(tri_in.dwdy, init_dy);
                    uw_row <= tri_in.uw0 + fp_mul(tri_in.dudx, init_dx) + fp_mul(tri_in.dudy, init_dy);
                    vw_row <= tri_in.vw0 + fp_mul(tri_in.dvdx, init_dx) + fp_mul(tri_in.dvdy, init_dy);
                    rw_row <= tri_in.rw0 + fp_mul(tri_in.drdx, init_dx) + fp_mul(tri_in.drdy, init_dy);
                    gw_row <= tri_in.gw0 + fp_mul(tri_in.dgdx, init_dx) + fp_mul(tri_in.dgdy, init_dy);
                    bw_row <= tri_in.bw0 + fp_mul(tri_in.dbdx, init_dx) + fp_mul(tri_in.dbdy, init_dy);
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

                            // Incremental attribute update
                            cur_z <= cur_z + tri_in.dzdx;
                            cur_w <= cur_w + tri_in.dwdx;
                            cur_uw <= cur_uw + tri_in.dudx;
                            cur_vw <= cur_vw + tri_in.dvdx;
                            cur_rw <= cur_rw + tri_in.drdx;
                            cur_gw <= cur_gw + tri_in.dgdx;
                            cur_bw <= cur_bw + tri_in.dbdx;
                        end
                    end
                end

                NEXT_ROW: begin
                    // Move to start of next row
                    cur_x <= tri_in.min_x;
                    cur_y <= cur_y + 1;

                    // Update row start values: E_row(y+1) = E_row(y) + B
                    e0_row <= e0_row + e0_b;
                    e1_row <= e1_row + e1_b;
                    e2_row <= e2_row + e2_b;
                    e0_val <= e0_row + e0_b;
                    e1_val <= e1_row + e1_b;
                    e2_val <= e2_row + e2_b;

                    // Update attribute row values
                    z_row <= z_row + tri_in.dzdy;
                    w_row <= w_row + tri_in.dwdy;
                    uw_row <= uw_row + tri_in.dudy;
                    vw_row <= vw_row + tri_in.dvdy;
                    rw_row <= rw_row + tri_in.drdy;
                    gw_row <= gw_row + tri_in.dgdy;
                    bw_row <= bw_row + tri_in.dbdy;

                    cur_z <= z_row + tri_in.dzdy;
                    cur_w <= w_row + tri_in.dwdy;
                    cur_uw <= uw_row + tri_in.dudy;
                    cur_vw <= vw_row + tri_in.dvdy;
                    cur_rw <= rw_row + tri_in.drdy;
                    cur_gw <= gw_row + tri_in.dgdy;
                    cur_bw <= bw_row + tri_in.dbdy;
                end

                DONE_STATE: begin
                    // Nothing to do
                end
            endcase
        end
    end

    // Output fragment (perspective-correct attributes)
    always_comb begin
        frag_out.x = cur_x;
        frag_out.y = cur_y;
        frag_out.z = cur_z;

        // Perspective correction: attr = attr_w / w
        // For now, output perspective-incorrect values (will add division later)
        frag_out.u = cur_uw;  // Should be cur_uw / cur_w
        frag_out.v = cur_vw;
        frag_out.r = cur_rw;
        frag_out.g = cur_gw;
        frag_out.b = cur_bw;

        frag_out.valid = (state == RASTERIZE) && inside_all;
    end

    assign frag_valid = frag_out.valid;
    assign done = (state == DONE_STATE);
    assign busy = (state != IDLE);

endmodule
