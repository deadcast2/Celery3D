// Celery3D GPU - Perspective Correction Unit
// Pipelined division: computes attr/w for u, v, r, g, b
// Uses leading-one detector + 3 Newton-Raphson iterations for 1/w
// 8-stage pipeline: 1 fragment/clock throughput after initial latency
//
// Pipeline: init_estimate -> NR1a -> NR1b -> NR2a -> NR2b -> NR3a -> NR3b -> multiply
//
// Fixed-point format: S15.16
// W values are typically in range [0.5, 8.0] for normal viewing
// (w = 1/z where z is depth in [0.125, 2.0])

module perspective_correct
    import celery_pkg::*;
#(
    // Set to 1 to bypass perspective correction (for debugging)
    parameter BYPASS = 0
)(
    input  logic        clk,
    input  logic        rst_n,

    // Input fragment (perspective-incorrect attributes: u*w, v*w, r*w, g*w, b*w)
    input  fragment_t   frag_in,
    input  logic        frag_in_valid,
    output logic        frag_in_ready,

    // W value for this fragment (interpolated 1/z from rasterizer)
    input  fp32_t       w_in,

    // Output fragment (perspective-correct attributes)
    output fragment_t   frag_out,
    output logic        frag_out_valid,
    input  logic        frag_out_ready
);

    // =========================================================================
    // Pipeline control
    // =========================================================================

    logic stall;

    // =========================================================================
    // BYPASS MODE - Simple passthrough
    // =========================================================================

    generate
    if (BYPASS) begin : gen_bypass

        fragment_t bypass_frag_r;
        logic bypass_valid_r;

        assign stall = bypass_valid_r && !frag_out_ready;
        assign frag_in_ready = !stall;

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                bypass_frag_r <= '0;
                bypass_valid_r <= 1'b0;
            end else if (!stall) begin
                bypass_valid_r <= frag_in_valid && frag_in.valid;
                bypass_frag_r <= frag_in;
            end
        end

        assign frag_out = bypass_frag_r;
        assign frag_out_valid = bypass_valid_r;

    end else begin : gen_persp

    // =========================================================================
    // NORMAL MODE - Full perspective correction
    // =========================================================================

    // Common data structure for pipeline stages
    typedef struct packed {
        screen_coord_t x, y;
        fp32_t z;
        fp32_t uw, vw, rw, gw, bw, aw;
        logic valid;
    } pipe_data_t;

    // Pipeline registers (8 stages: init + 3 NR iterations + multiply)
    pipe_data_t p1, p2, p3, p4, p5, p6, p7;
    logic p1_valid, p2_valid, p3_valid, p4_valid, p5_valid, p6_valid, p7_valid, p8_valid;

    // Reciprocal computation state
    fp32_t p1_w, p2_w, p3_w, p4_w, p5_w, p6_w;
    fp32_t p2_recip, p3_recip, p4_recip, p5_recip, p6_recip, p7_recip;

    // Output fragment
    fragment_t p8_frag;

    assign stall = p8_valid && !frag_out_ready;
    assign frag_in_ready = !stall;

    // =========================================================================
    // Stage 1: Capture inputs and compute initial reciprocal estimate
    // Using simple reciprocal approximation: 1/w ≈ (3 - w) / 2 for w near 1
    // But since w can be 0.5-8.0, we use a different approach:
    // Scale w to reasonable range then iterate
    // =========================================================================

    // Initial estimate: use leading-one detector to get magnitude
    // Then provide rough 1/x estimate

    logic [31:0] p1_abs_w_comb;
    fp32_t p1_init_recip_comb;
    fp32_t p1_recip;  // Registered initial estimate

    // Count leading zeros for magnitude estimation (combinational on inputs)
    // Find position of leading 1 bit to estimate magnitude of w
    logic [4:0] p1_bit_pos;  // Position of leading 1
    logic signed [5:0] p1_shift_amt;  // Signed shift amount

    always_comb begin
        p1_abs_w_comb = w_in[31] ? (~w_in + 1) : w_in;

        // Find leading one position
        p1_bit_pos = 5'd0;
        for (int i = 31; i >= 0; i--) begin
            if (p1_abs_w_comb[i]) begin
                p1_bit_pos = 5'(i);
                break;
            end
        end

        // Initial reciprocal estimate based on magnitude
        // In S15.16 format: w = 2^(bit_pos - 16) in floating-point terms
        // So 1/w ≈ 2^(16 - bit_pos)
        //
        // IMPORTANT: The estimate can be up to 2x off at power-of-2 boundaries,
        // which causes Newton-Raphson to diverge. To fix this, we shift right
        // by one extra bit to ensure the estimate is always UNDER the true value.
        // This guarantees convergence (at cost of needing one more iteration).
        //
        // shift = bit_pos - 15 (not -16) to make estimate conservatively small
        //
        p1_shift_amt = 6'(p1_bit_pos) - 6'd15;  // One extra right shift for safety

        if (p1_shift_amt >= 0)
            p1_init_recip_comb = FP_ONE >>> p1_shift_amt[4:0];
        else
            p1_init_recip_comb = FP_ONE <<< (~p1_shift_amt[4:0] + 1);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p1 <= '0;
            p1_valid <= 1'b0;
            p1_w <= FP_ZERO;
            p1_recip <= FP_ZERO;
        end else if (!stall) begin
            p1_valid <= frag_in_valid;

            p1.x <= frag_in.x;
            p1.y <= frag_in.y;
            p1.z <= frag_in.z;
            p1.uw <= frag_in.u;
            p1.vw <= frag_in.v;
            p1.rw <= frag_in.r;
            p1.gw <= frag_in.g;
            p1.bw <= frag_in.b;
            p1.aw <= frag_in.a;
            p1.valid <= frag_in.valid;

            p1_w <= w_in;
            p1_recip <= p1_init_recip_comb;  // Register the initial estimate
        end
    end

    // =========================================================================
    // Stage 2: Newton-Raphson iteration 1, part A
    // Compute: w * x_est (using REGISTERED values from stage 1)
    // =========================================================================

    logic signed [63:0] p2_wx_comb;
    fp32_t p2_wx;  // Registered product

    always_comb begin
        // w * initial_estimate (using registered p1 values)
        p2_wx_comb = (64'(signed'(p1_w)) * 64'(signed'(p1_recip))) >>> FP_FRAC_BITS;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p2 <= '0;
            p2_valid <= 1'b0;
            p2_w <= FP_ZERO;
            p2_recip <= FP_ZERO;
            p2_wx <= FP_ZERO;
        end else if (!stall) begin
            p2_valid <= p1_valid;
            p2 <= p1;
            p2_w <= p1_w;
            p2_recip <= p1_recip;
            p2_wx <= fp32_t'(p2_wx_comb);  // Register the product
        end
    end

    // =========================================================================
    // Stage 3: Newton-Raphson iteration 1, part B
    // Compute: x' = x * (2 - w*x) using registered p2_wx
    // =========================================================================

    logic signed [31:0] p3_two_minus_wx_comb;
    logic signed [63:0] p3_new_recip_comb;

    always_comb begin
        // 2.0 - (w * x) using registered product
        p3_two_minus_wx_comb = (FP_ONE <<< 1) - p2_wx;
        // x * (2 - w*x)
        p3_new_recip_comb = (64'(signed'(p2_recip)) * 64'(p3_two_minus_wx_comb)) >>> FP_FRAC_BITS;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p3 <= '0;
            p3_valid <= 1'b0;
            p3_w <= FP_ZERO;
            p3_recip <= FP_ZERO;
        end else if (!stall) begin
            p3_valid <= p2_valid;
            p3 <= p2;
            p3_w <= p2_w;
            p3_recip <= fp32_t'(p3_new_recip_comb);
        end
    end

    // =========================================================================
    // Stage 4: Newton-Raphson iteration 2, part A
    // Compute: w * x (using registered p3 values)
    // =========================================================================

    logic signed [63:0] p4_wx_comb;
    fp32_t p4_wx;  // Registered product

    always_comb begin
        p4_wx_comb = (64'(signed'(p3_w)) * 64'(signed'(p3_recip))) >>> FP_FRAC_BITS;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p4 <= '0;
            p4_valid <= 1'b0;
            p4_w <= FP_ZERO;
            p4_recip <= FP_ZERO;
            p4_wx <= FP_ZERO;
        end else if (!stall) begin
            p4_valid <= p3_valid;
            p4 <= p3;
            p4_w <= p3_w;
            p4_recip <= p3_recip;
            p4_wx <= fp32_t'(p4_wx_comb);
        end
    end

    // =========================================================================
    // Stage 5: Newton-Raphson iteration 2, part B
    // =========================================================================

    logic signed [31:0] p5_two_minus_wx_comb;
    logic signed [63:0] p5_new_recip_comb;

    always_comb begin
        p5_two_minus_wx_comb = (FP_ONE <<< 1) - p4_wx;
        p5_new_recip_comb = (64'(signed'(p4_recip)) * 64'(p5_two_minus_wx_comb)) >>> FP_FRAC_BITS;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p5 <= '0;
            p5_valid <= 1'b0;
            p5_w <= FP_ZERO;
            p5_recip <= FP_ZERO;
        end else if (!stall) begin
            p5_valid <= p4_valid;
            p5 <= p4;
            p5_w <= p4_w;
            p5_recip <= fp32_t'(p5_new_recip_comb);
        end
    end

    // =========================================================================
    // Stage 6: Newton-Raphson iteration 3, part A
    // Compute: w * x (third iteration for better convergence)
    // =========================================================================

    logic signed [63:0] p6_wx_comb;
    fp32_t p6_wx;

    always_comb begin
        p6_wx_comb = (64'(signed'(p5_w)) * 64'(signed'(p5_recip))) >>> FP_FRAC_BITS;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p6 <= '0;
            p6_valid <= 1'b0;
            p6_w <= FP_ZERO;
            p6_recip <= FP_ZERO;
            p6_wx <= FP_ZERO;
        end else if (!stall) begin
            p6_valid <= p5_valid;
            p6 <= p5;
            p6_w <= p5_w;
            p6_recip <= p5_recip;
            p6_wx <= fp32_t'(p6_wx_comb);
        end
    end

    // =========================================================================
    // Stage 7: Newton-Raphson iteration 3, part B - final 1/w
    // =========================================================================

    logic signed [31:0] p7_two_minus_wx_comb;
    logic signed [63:0] p7_final_recip_comb;

    always_comb begin
        p7_two_minus_wx_comb = (FP_ONE <<< 1) - p6_wx;
        p7_final_recip_comb = (64'(signed'(p6_recip)) * 64'(p7_two_minus_wx_comb)) >>> FP_FRAC_BITS;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p7 <= '0;
            p7_valid <= 1'b0;
            p7_recip <= FP_ZERO;
        end else if (!stall) begin
            p7_valid <= p6_valid;
            p7 <= p6;
            p7_recip <= fp32_t'(p7_final_recip_comb);
        end
    end

    // =========================================================================
    // Stage 8: Multiply attributes by 1/w (6 parallel multipliers)
    // =========================================================================

    logic signed [63:0] p8_u, p8_v, p8_r, p8_g, p8_b, p8_a;

    always_comb begin
        p8_u = (64'(signed'(p7.uw)) * 64'(signed'(p7_recip))) >>> FP_FRAC_BITS;
        p8_v = (64'(signed'(p7.vw)) * 64'(signed'(p7_recip))) >>> FP_FRAC_BITS;
        p8_r = (64'(signed'(p7.rw)) * 64'(signed'(p7_recip))) >>> FP_FRAC_BITS;
        p8_g = (64'(signed'(p7.gw)) * 64'(signed'(p7_recip))) >>> FP_FRAC_BITS;
        p8_b = (64'(signed'(p7.bw)) * 64'(signed'(p7_recip))) >>> FP_FRAC_BITS;
        p8_a = (64'(signed'(p7.aw)) * 64'(signed'(p7_recip))) >>> FP_FRAC_BITS;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p8_frag <= '0;
            p8_valid <= 1'b0;
        end else if (!stall) begin
            p8_valid <= p7_valid && p7.valid;

            p8_frag.x <= p7.x;
            p8_frag.y <= p7.y;
            p8_frag.z <= p7.z;
            p8_frag.u <= fp32_t'(p8_u);
            p8_frag.v <= fp32_t'(p8_v);
            p8_frag.r <= fp32_t'(p8_r);
            p8_frag.g <= fp32_t'(p8_g);
            p8_frag.b <= fp32_t'(p8_b);
            p8_frag.a <= fp32_t'(p8_a);
            p8_frag.valid <= p7.valid;
        end
    end

    // Output
    assign frag_out = p8_frag;
    assign frag_out_valid = p8_valid;

    end  // gen_persp
    endgenerate

endmodule
