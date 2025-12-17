// Celery3D GPU - Alpha Blending Unit
// 4-stage pipeline: Issue FB read -> FB latency + expand/select alpha -> blend MAC -> clamp/pack
// Implements Glide-compatible blend factors and alpha sources
//
// SPDX-License-Identifier: CERN-OHL-P-2.0

module alpha_blend
    import celery_pkg::*;
#(
    parameter FB_WIDTH  = 640,
    parameter FB_HEIGHT = 480
)(
    input  logic        clk,
    input  logic        rst_n,

    // Configuration
    input  logic          blend_enable,      // Enable alpha blending
    input  blend_factor_t src_factor,        // Source blend factor
    input  blend_factor_t dst_factor,        // Destination blend factor
    input  alpha_source_t alpha_source,      // Alpha source selection
    input  alpha_t        constant_alpha,    // Constant alpha value

    // Input from depth_buffer
    input  fragment_t     frag_in,
    input  rgb565_t       color_in,          // Source color (RGB565)
    input  alpha_t        tex_alpha_in,      // Texture alpha
    input  logic          frag_in_valid,
    output logic          frag_in_ready,

    // Output to framebuffer
    output fragment_t     frag_out,
    output rgb565_t       color_out,         // Blended color (RGB565)
    output logic          frag_out_valid,
    input  logic          frag_out_ready,

    // Framebuffer blend read port
    output logic [$clog2(FB_WIDTH)-1:0]  blend_read_x,
    output logic [$clog2(FB_HEIGHT)-1:0] blend_read_y,
    output logic                          blend_read_en,
    input  rgb565_t                       blend_read_data,
    input  logic                          blend_read_valid
);

    // =========================================================================
    // Pipeline Control
    // =========================================================================

    logic stall;
    assign stall = p5_valid && !frag_out_ready;
    assign frag_in_ready = !stall;

    // =========================================================================
    // RGB565 to RGB888 Expansion Functions
    // =========================================================================

    function automatic logic [7:0] expand_r5(input logic [4:0] r);
        return {r, r[4:2]};  // Replicate top 3 bits
    endfunction

    function automatic logic [7:0] expand_g6(input logic [5:0] g);
        return {g, g[5:4]};  // Replicate top 2 bits
    endfunction

    function automatic logic [7:0] expand_b5(input logic [4:0] b);
        return {b, b[4:2]};  // Replicate top 3 bits
    endfunction

    // =========================================================================
    // Blend Factor Computation Function
    // =========================================================================

    // Returns 8-bit blend factor (0-255) based on factor type and colors
    function automatic logic [8:0] get_blend_factor(
        input blend_factor_t factor,
        input logic [7:0] src_r, input logic [7:0] src_g, input logic [7:0] src_b, input logic [7:0] src_a,
        input logic [7:0] dst_r, input logic [7:0] dst_g, input logic [7:0] dst_b, input logic [7:0] dst_a
    );
        logic [8:0] result;
        logic [8:0] one_minus_src_a;
        logic [8:0] one_minus_dst_a;
        logic [8:0] alpha_sat;

        one_minus_src_a = 9'd255 - {1'b0, src_a};
        one_minus_dst_a = 9'd255 - {1'b0, dst_a};

        // Alpha saturate: min(src_a, 1-dst_a)
        alpha_sat = ({1'b0, src_a} < one_minus_dst_a) ? {1'b0, src_a} : one_minus_dst_a;

        case (factor)
            GR_BLEND_ZERO:                result = 9'd0;
            GR_BLEND_ONE:                 result = 9'd255;
            GR_BLEND_SRC_ALPHA:           result = {1'b0, src_a};
            GR_BLEND_ONE_MINUS_SRC_ALPHA: result = one_minus_src_a;
            GR_BLEND_DST_ALPHA:           result = {1'b0, dst_a};
            GR_BLEND_ONE_MINUS_DST_ALPHA: result = one_minus_dst_a;
            GR_BLEND_SRC_COLOR:           result = {1'b0, src_r};  // Use red channel as factor
            GR_BLEND_ONE_MINUS_SRC_COLOR: result = 9'd255 - {1'b0, src_r};
            GR_BLEND_DST_COLOR:           result = {1'b0, dst_r};
            GR_BLEND_ONE_MINUS_DST_COLOR: result = 9'd255 - {1'b0, dst_r};
            GR_BLEND_ALPHA_SATURATE:      result = alpha_sat;
            GR_BLEND_PREFOG_COLOR:        result = {1'b0, src_a};  // Reserved, use src_a
            default:                      result = 9'd255;
        endcase

        return result;
    endfunction

    // =========================================================================
    // Stage 1: Issue Framebuffer Read
    // =========================================================================

    fragment_t p1_frag;
    rgb565_t p1_color;
    alpha_t p1_tex_alpha;
    logic p1_valid;
    logic p1_blend_enable;
    blend_factor_t p1_src_factor;
    blend_factor_t p1_dst_factor;
    alpha_source_t p1_alpha_source;
    alpha_t p1_constant_alpha;

    // Issue framebuffer read at fragment coordinates
    assign blend_read_x = frag_in.x[$clog2(FB_WIDTH)-1:0];
    assign blend_read_y = frag_in.y[$clog2(FB_HEIGHT)-1:0];
    assign blend_read_en = frag_in_valid && frag_in.valid && blend_enable && !stall;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p1_frag <= '0;
            p1_color <= 16'h0000;
            p1_tex_alpha <= 8'h00;
            p1_valid <= 1'b0;
            p1_blend_enable <= 1'b0;
            p1_src_factor <= GR_BLEND_ONE;
            p1_dst_factor <= GR_BLEND_ZERO;
            p1_alpha_source <= ALPHA_SRC_ONE;
            p1_constant_alpha <= 8'hFF;
        end else if (!stall) begin
            p1_valid <= frag_in_valid && frag_in.valid;
            p1_frag <= frag_in;
            p1_color <= color_in;
            p1_tex_alpha <= tex_alpha_in;
            p1_blend_enable <= blend_enable;
            p1_src_factor <= src_factor;
            p1_dst_factor <= dst_factor;
            p1_alpha_source <= alpha_source;
            p1_constant_alpha <= constant_alpha;
        end
    end

    // =========================================================================
    // Stage 2: FB Latency Wait - Pass through source data while FB read completes
    // =========================================================================
    // Framebuffer has 2-cycle read latency:
    //   Cycle N: blend_read_en asserted
    //   Cycle N+1: address registered
    //   Cycle N+2: blend_read_data valid
    // So we need to wait one extra cycle before capturing FB data.

    fragment_t p2_frag;
    logic p2_valid;
    logic p2_blend_enable;
    blend_factor_t p2_src_factor;
    blend_factor_t p2_dst_factor;
    alpha_source_t p2_alpha_source;
    alpha_t p2_tex_alpha;
    alpha_t p2_constant_alpha;
    rgb565_t p2_color;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p2_frag <= '0;
            p2_valid <= 1'b0;
            p2_blend_enable <= 1'b0;
            p2_src_factor <= GR_BLEND_ONE;
            p2_dst_factor <= GR_BLEND_ZERO;
            p2_alpha_source <= ALPHA_SRC_ONE;
            p2_tex_alpha <= 8'h00;
            p2_constant_alpha <= 8'hFF;
            p2_color <= 16'h0000;
        end else if (!stall) begin
            p2_valid <= p1_valid;
            p2_frag <= p1_frag;
            p2_blend_enable <= p1_blend_enable;
            p2_src_factor <= p1_src_factor;
            p2_dst_factor <= p1_dst_factor;
            p2_alpha_source <= p1_alpha_source;
            p2_tex_alpha <= p1_tex_alpha;
            p2_constant_alpha <= p1_constant_alpha;
            p2_color <= p1_color;
        end
    end

    // =========================================================================
    // Stage 3: Capture FB Data + Expand RGB565 to RGB888 + Select Alpha
    // =========================================================================
    // Now blend_read_data is valid (2 cycles after read was issued in stage 1)

    fragment_t p3_frag;
    logic p3_valid;
    logic p3_blend_enable;
    blend_factor_t p3_src_factor;
    blend_factor_t p3_dst_factor;

    // Source color (expanded to 8-bit)
    logic [7:0] p3_src_r, p3_src_g, p3_src_b, p3_src_a;

    // Destination color (expanded to 8-bit)
    logic [7:0] p3_dst_r, p3_dst_g, p3_dst_b, p3_dst_a;

    // Pass-through color for non-blending case
    rgb565_t p3_passthrough_color;

    // Alpha selection combinational logic
    logic [7:0] selected_alpha;

    always_comb begin
        case (p2_alpha_source)
            ALPHA_SRC_TEXTURE:  selected_alpha = p2_tex_alpha;
            ALPHA_SRC_VERTEX: begin
                // Extract vertex alpha from fragment (clamp to 0-255)
                if (p2_frag.a[31]) begin
                    selected_alpha = 8'h00;
                end else if (p2_frag.a >= FP_ONE) begin
                    selected_alpha = 8'hFF;
                end else begin
                    selected_alpha = p2_frag.a[15:8];
                end
            end
            ALPHA_SRC_CONSTANT: selected_alpha = p2_constant_alpha;
            ALPHA_SRC_ONE:      selected_alpha = 8'hFF;
            default:            selected_alpha = 8'hFF;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p3_frag <= '0;
            p3_valid <= 1'b0;
            p3_blend_enable <= 1'b0;
            p3_src_factor <= GR_BLEND_ONE;
            p3_dst_factor <= GR_BLEND_ZERO;
            p3_src_r <= 8'd0;
            p3_src_g <= 8'd0;
            p3_src_b <= 8'd0;
            p3_src_a <= 8'd0;
            p3_dst_r <= 8'd0;
            p3_dst_g <= 8'd0;
            p3_dst_b <= 8'd0;
            p3_dst_a <= 8'd0;
            p3_passthrough_color <= 16'h0000;
        end else if (!stall) begin
            p3_valid <= p2_valid;
            p3_frag <= p2_frag;
            p3_blend_enable <= p2_blend_enable;
            p3_src_factor <= p2_src_factor;
            p3_dst_factor <= p2_dst_factor;
            p3_passthrough_color <= p2_color;

            // Expand source color (from input RGB565)
            p3_src_r <= expand_r5(p2_color[15:11]);
            p3_src_g <= expand_g6(p2_color[10:5]);
            p3_src_b <= expand_b5(p2_color[4:0]);
            p3_src_a <= selected_alpha;

            // Expand destination color (from framebuffer read)
            // blend_read_data is now valid (2 cycles after stage 1)
            p3_dst_r <= expand_r5(blend_read_data[15:11]);
            p3_dst_g <= expand_g6(blend_read_data[10:5]);
            p3_dst_b <= expand_b5(blend_read_data[4:0]);
            p3_dst_a <= 8'hFF;  // Framebuffer has no alpha, assume opaque
        end
    end

    // =========================================================================
    // Stage 4: Blend Multiply-Accumulate
    // =========================================================================

    fragment_t p4_frag;
    logic p4_valid;
    logic p4_blend_enable;
    rgb565_t p4_passthrough_color;

    // Blended color (9-bit to handle overflow before clamping)
    logic [8:0] p4_blend_r, p4_blend_g, p4_blend_b;

    // Blend factor calculation (combinational)
    logic [8:0] src_factor_val, dst_factor_val;
    logic [16:0] blend_r_prod, blend_g_prod, blend_b_prod;
    logic [17:0] blend_r_sum, blend_g_sum, blend_b_sum;
    logic [8:0] blend_r_result, blend_g_result, blend_b_result;

    always_comb begin
        // Get blend factors
        src_factor_val = get_blend_factor(
            p3_src_factor,
            p3_src_r, p3_src_g, p3_src_b, p3_src_a,
            p3_dst_r, p3_dst_g, p3_dst_b, p3_dst_a
        );
        dst_factor_val = get_blend_factor(
            p3_dst_factor,
            p3_src_r, p3_src_g, p3_src_b, p3_src_a,
            p3_dst_r, p3_dst_g, p3_dst_b, p3_dst_a
        );

        // Blend equation: result = (src * src_factor + dst * dst_factor) / 255
        // Using approximation: (val + 128) >> 8

        // Red channel
        blend_r_prod = ({1'b0, p3_src_r} * src_factor_val) + ({1'b0, p3_dst_r} * dst_factor_val);
        blend_r_sum = {1'b0, blend_r_prod} + 18'd128;
        blend_r_result = blend_r_sum[16:8];

        // Green channel
        blend_g_prod = ({1'b0, p3_src_g} * src_factor_val) + ({1'b0, p3_dst_g} * dst_factor_val);
        blend_g_sum = {1'b0, blend_g_prod} + 18'd128;
        blend_g_result = blend_g_sum[16:8];

        // Blue channel
        blend_b_prod = ({1'b0, p3_src_b} * src_factor_val) + ({1'b0, p3_dst_b} * dst_factor_val);
        blend_b_sum = {1'b0, blend_b_prod} + 18'd128;
        blend_b_result = blend_b_sum[16:8];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p4_frag <= '0;
            p4_valid <= 1'b0;
            p4_blend_enable <= 1'b0;
            p4_passthrough_color <= 16'h0000;
            p4_blend_r <= 9'd0;
            p4_blend_g <= 9'd0;
            p4_blend_b <= 9'd0;
        end else if (!stall) begin
            p4_valid <= p3_valid;
            p4_frag <= p3_frag;
            p4_blend_enable <= p3_blend_enable;
            p4_passthrough_color <= p3_passthrough_color;
            p4_blend_r <= blend_r_result;
            p4_blend_g <= blend_g_result;
            p4_blend_b <= blend_b_result;
        end
    end

    // =========================================================================
    // Stage 5: Clamp and Pack RGB888 to RGB565
    // =========================================================================

    fragment_t p5_frag;
    logic p5_valid;
    rgb565_t p5_color;

    // Clamping logic
    logic [7:0] clamped_r, clamped_g, clamped_b;

    always_comb begin
        // Clamp to 0-255 range
        clamped_r = (p4_blend_r > 9'd255) ? 8'd255 : p4_blend_r[7:0];
        clamped_g = (p4_blend_g > 9'd255) ? 8'd255 : p4_blend_g[7:0];
        clamped_b = (p4_blend_b > 9'd255) ? 8'd255 : p4_blend_b[7:0];
    end

    // Pack to RGB565
    rgb565_t blended_color;
    assign blended_color = {clamped_r[7:3], clamped_g[7:2], clamped_b[7:3]};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p5_frag <= '0;
            p5_valid <= 1'b0;
            p5_color <= 16'h0000;
        end else if (!stall) begin
            p5_valid <= p4_valid;
            p5_frag <= p4_frag;
            // Select between blended and passthrough color
            p5_color <= p4_blend_enable ? blended_color : p4_passthrough_color;
        end
    end

    // =========================================================================
    // Output Assignments
    // =========================================================================

    assign frag_out = p5_frag;
    assign color_out = p5_color;
    assign frag_out_valid = p5_valid;

endmodule
