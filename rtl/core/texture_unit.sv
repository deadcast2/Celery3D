// Celery3D GPU - Texture Mapping Unit
// Supports nearest-neighbor and bilinear filtering with Gouraud color modulation
// 5-stage pipeline: UV wrap/address → BRAM read → unpack → interpolate → modulate
// Uses dual-port BRAMs (even/odd column split) for 4-texel parallel fetch
//
// SPDX-License-Identifier: Apache-2.0

module texture_unit
    import celery_pkg::*;
#(
    // Texture dimensions (must be power of 2)
    parameter TEX_WIDTH_LOG2  = 6,  // 64 texels wide
    parameter TEX_HEIGHT_LOG2 = 6,  // 64 texels tall
    parameter TEX_WIDTH  = 1 << TEX_WIDTH_LOG2,
    parameter TEX_HEIGHT = 1 << TEX_HEIGHT_LOG2,
    parameter TEX_SIZE   = TEX_WIDTH * TEX_HEIGHT,
    parameter ADDR_BITS  = TEX_WIDTH_LOG2 + TEX_HEIGHT_LOG2,
    parameter HALF_ADDR_BITS = TEX_WIDTH_LOG2 + TEX_HEIGHT_LOG2 - 1  // For split BRAMs
)(
    input  logic        clk,
    input  logic        rst_n,

    // Configuration
    input  logic        tex_enable,        // Enable texture sampling
    input  logic        modulate_enable,   // Enable Gouraud modulation
    input  logic        filter_bilinear,   // 0=nearest, 1=bilinear

    // Input fragment (from perspective_correct)
    input  fragment_t   frag_in,
    input  logic        frag_in_valid,
    output logic        frag_in_ready,

    // Output fragment (textured/modulated)
    output fragment_t   frag_out,
    output rgb565_t     color_out,         // Final RGB565 color
    output logic        frag_out_valid,
    input  logic        frag_out_ready,

    // Texture memory write interface (for loading textures)
    input  logic [ADDR_BITS-1:0] tex_wr_addr,
    input  rgb565_t              tex_wr_data,
    input  logic                 tex_wr_en
);

    // =========================================================================
    // Pipeline Control
    // =========================================================================

    logic stall;
    assign stall = p5_valid && !frag_out_ready;
    assign frag_in_ready = !stall;

    // =========================================================================
    // Texture BRAMs (Even/Odd Column Split)
    // =========================================================================
    // BRAM_A stores even columns (x[0]==0), BRAM_B stores odd columns (x[0]==1)
    // Each BRAM is dual-port: port1 for row y0, port2 for row y1

    rgb565_t tex_mem_a [0:(TEX_SIZE/2)-1];  // Even columns
    rgb565_t tex_mem_b [0:(TEX_SIZE/2)-1];  // Odd columns

    // Read addresses for 4 texels
    logic [HALF_ADDR_BITS-1:0] bram_a_addr_p1, bram_a_addr_p2;
    logic [HALF_ADDR_BITS-1:0] bram_b_addr_p1, bram_b_addr_p2;

    // Read data from BRAMs
    rgb565_t bram_a_data_p1, bram_a_data_p2;
    rgb565_t bram_b_data_p1, bram_b_data_p2;

    // Write interface: route to correct BRAM based on x[0]
    logic tex_wr_x_odd;
    logic [HALF_ADDR_BITS-1:0] tex_wr_addr_half;

    assign tex_wr_x_odd = tex_wr_addr[0];
    // Half address: {y, x[width-1:1]} - drop the LSB of x
    assign tex_wr_addr_half = {tex_wr_addr[ADDR_BITS-1:TEX_WIDTH_LOG2],
                               tex_wr_addr[TEX_WIDTH_LOG2-1:1]};

    // BRAM_A: Even columns (dual-port read, single-port write)
    always_ff @(posedge clk) begin
        if (tex_wr_en && !tex_wr_x_odd) begin
            tex_mem_a[tex_wr_addr_half] <= tex_wr_data;
        end
    end

    always_ff @(posedge clk) begin
        if (!stall) begin
            bram_a_data_p1 <= tex_mem_a[bram_a_addr_p1];
            bram_a_data_p2 <= tex_mem_a[bram_a_addr_p2];
        end
    end

    // BRAM_B: Odd columns (dual-port read, single-port write)
    always_ff @(posedge clk) begin
        if (tex_wr_en && tex_wr_x_odd) begin
            tex_mem_b[tex_wr_addr_half] <= tex_wr_data;
        end
    end

    always_ff @(posedge clk) begin
        if (!stall) begin
            bram_b_data_p1 <= tex_mem_b[bram_b_addr_p1];
            bram_b_data_p2 <= tex_mem_b[bram_b_addr_p2];
        end
    end

    // =========================================================================
    // UV Wrapping Function
    // =========================================================================

    // Wrap UV to [0, 1) range (repeat mode)
    // For S15.16 format: integer in [31:16], fraction in [15:0]
    // Returns 16-bit fractional value in 0.16 format
    function automatic logic [15:0] wrap_uv(input fp32_t uv);
        logic [15:0] frac;
        logic [16:0] temp;
        begin
            // Get fractional part
            frac = uv[15:0];

            // If original UV was negative, wrap properly
            // For negative: frac part represents -(1-frac), so we need 1-|frac|
            if (uv[31] && frac != 0) begin
                temp = 17'h10000 - {1'b0, frac};
                frac = temp[15:0];
            end

            return frac;
        end
    endfunction

    // =========================================================================
    // Stage 1: UV Wrapping, Address Calculation, and Weight Extraction
    // =========================================================================

    fragment_t p1_frag;
    logic p1_valid;
    logic p1_tex_enable;
    logic p1_modulate_enable;
    logic p1_filter_bilinear;
    logic p1_x0_is_odd;
    logic [7:0] p1_weight_u, p1_weight_v;

    logic [15:0] u_wrapped, v_wrapped;
    logic [15:0] u_bilinear, v_bilinear;
    logic [TEX_WIDTH_LOG2-1:0]  x0, x1;
    logic [TEX_HEIGHT_LOG2-1:0] y0, y1;
    logic [TEX_WIDTH_LOG2-2:0]  x_even_half, x_odd_half;

    always_comb begin
        // Wrap UV coordinates
        u_wrapped = wrap_uv(frag_in.u);
        v_wrapped = wrap_uv(frag_in.v);

        // For bilinear: offset by -0.5 texel to center the filter kernel
        // 0.5 texel in 0.16 format = 0x8000 >> LOG2
        // For 64 texels: 0x8000 >> 6 = 0x0200
        // For nearest: use raw wrapped coordinates (no offset)
        if (filter_bilinear) begin
            u_bilinear = u_wrapped - (16'h8000 >> TEX_WIDTH_LOG2);
            v_bilinear = v_wrapped - (16'h8000 >> TEX_HEIGHT_LOG2);
        end else begin
            u_bilinear = u_wrapped;
            v_bilinear = v_wrapped;
        end

        // Extract texel indices (floor of UV * dimension)
        x0 = u_bilinear[15 -: TEX_WIDTH_LOG2];
        y0 = v_bilinear[15 -: TEX_HEIGHT_LOG2];

        // Neighbor coordinates (wraps automatically due to bit width truncation)
        x1 = x0 + 1'b1;
        y1 = y0 + 1'b1;

        // Determine which BRAM has which texel based on x0[0]
        // If x0 is even: BRAM_A has x0, BRAM_B has x1
        // If x0 is odd:  BRAM_B has x0, BRAM_A has x1
        if (x0[0]) begin
            // x0 is odd
            x_even_half = x1[TEX_WIDTH_LOG2-1:1];  // x1 is even
            x_odd_half  = x0[TEX_WIDTH_LOG2-1:1];  // x0 is odd
        end else begin
            // x0 is even
            x_even_half = x0[TEX_WIDTH_LOG2-1:1];  // x0 is even
            x_odd_half  = x1[TEX_WIDTH_LOG2-1:1];  // x1 is odd
        end
    end

    // Compute BRAM addresses
    // BRAM address = {y, x_half} where x_half is x >> 1
    assign bram_a_addr_p1 = {y0, x_even_half};  // Even column, row y0
    assign bram_a_addr_p2 = {y1, x_even_half};  // Even column, row y1
    assign bram_b_addr_p1 = {y0, x_odd_half};   // Odd column, row y0
    assign bram_b_addr_p2 = {y1, x_odd_half};   // Odd column, row y1

    // Extract fractional weights for bilinear interpolation (8-bit precision)
    // Weight is the fractional position within the texel
    logic [15:0] frac_u_full, frac_v_full;
    assign frac_u_full = u_bilinear << TEX_WIDTH_LOG2;   // Shift to get sub-texel fraction
    assign frac_v_full = v_bilinear << TEX_HEIGHT_LOG2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p1_frag <= '0;
            p1_valid <= 1'b0;
            p1_tex_enable <= 1'b0;
            p1_modulate_enable <= 1'b0;
            p1_filter_bilinear <= 1'b0;
            p1_x0_is_odd <= 1'b0;
            p1_weight_u <= 8'd0;
            p1_weight_v <= 8'd0;
        end else if (!stall) begin
            p1_valid <= frag_in_valid && frag_in.valid;
            p1_frag <= frag_in;
            p1_tex_enable <= tex_enable;
            p1_modulate_enable <= modulate_enable;
            p1_filter_bilinear <= filter_bilinear;
            p1_x0_is_odd <= x0[0];
            p1_weight_u <= frac_u_full[15:8];  // Top 8 bits of sub-texel fraction
            p1_weight_v <= frac_v_full[15:8];
        end
    end

    // =========================================================================
    // Stage 2: BRAM Read (data arrives this cycle)
    // =========================================================================
    // Capture BRAM outputs to align with fragment data (like original p2_tex_data)

    fragment_t p2_frag;
    logic p2_valid;
    logic p2_tex_enable;
    logic p2_modulate_enable;
    logic p2_filter_bilinear;
    logic p2_x0_is_odd;
    logic [7:0] p2_weight_u, p2_weight_v;

    // Captured BRAM data aligned with p2_frag
    rgb565_t p2_bram_a_p1, p2_bram_a_p2;
    rgb565_t p2_bram_b_p1, p2_bram_b_p2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p2_frag <= '0;
            p2_valid <= 1'b0;
            p2_tex_enable <= 1'b0;
            p2_modulate_enable <= 1'b0;
            p2_filter_bilinear <= 1'b0;
            p2_x0_is_odd <= 1'b0;
            p2_weight_u <= 8'd0;
            p2_weight_v <= 8'd0;
            p2_bram_a_p1 <= 16'h0000;
            p2_bram_a_p2 <= 16'h0000;
            p2_bram_b_p1 <= 16'h0000;
            p2_bram_b_p2 <= 16'h0000;
        end else if (!stall) begin
            p2_valid <= p1_valid;
            p2_frag <= p1_frag;
            p2_tex_enable <= p1_tex_enable;
            p2_modulate_enable <= p1_modulate_enable;
            p2_filter_bilinear <= p1_filter_bilinear;
            p2_x0_is_odd <= p1_x0_is_odd;
            p2_weight_u <= p1_weight_u;
            p2_weight_v <= p1_weight_v;
            // Capture BRAM outputs to keep them aligned with fragment
            p2_bram_a_p1 <= bram_a_data_p1;
            p2_bram_a_p2 <= bram_a_data_p2;
            p2_bram_b_p1 <= bram_b_data_p1;
            p2_bram_b_p2 <= bram_b_data_p2;
        end
    end

    // =========================================================================
    // Stage 3: Unpack and Arrange Texels
    // =========================================================================

    fragment_t p3_frag;
    logic p3_valid;
    logic p3_tex_enable;
    logic p3_modulate_enable;
    logic p3_filter_bilinear;
    logic [7:0] p3_weight_u, p3_weight_v;

    // Unpacked 8-bit colors for all 4 texels
    logic [7:0] p3_r00, p3_g00, p3_b00;  // (x0, y0)
    logic [7:0] p3_r10, p3_g10, p3_b10;  // (x1, y0)
    logic [7:0] p3_r01, p3_g01, p3_b01;  // (x0, y1)
    logic [7:0] p3_r11, p3_g11, p3_b11;  // (x1, y1)

    // Arrange texels based on x0_is_odd flag (use captured p2_bram_* data)
    rgb565_t c00, c10, c01, c11;

    always_comb begin
        if (p2_x0_is_odd) begin
            // x0 is odd: BRAM_B has x0 (odd), BRAM_A has x1 (even)
            c00 = p2_bram_b_p1;  // (x0, y0) - odd column
            c10 = p2_bram_a_p1;  // (x1, y0) - even column
            c01 = p2_bram_b_p2;  // (x0, y1) - odd column
            c11 = p2_bram_a_p2;  // (x1, y1) - even column
        end else begin
            // x0 is even: BRAM_A has x0 (even), BRAM_B has x1 (odd)
            c00 = p2_bram_a_p1;  // (x0, y0) - even column
            c10 = p2_bram_b_p1;  // (x1, y0) - odd column
            c01 = p2_bram_a_p2;  // (x0, y1) - even column
            c11 = p2_bram_b_p2;  // (x1, y1) - odd column
        end
    end

    // Unpack RGB565 to 8-bit per channel (replicate top bits to fill)
    function automatic logic [7:0] expand_red(input rgb565_t color);
        logic [4:0] r5;
        begin
            r5 = color[15:11];
            return {r5, r5[4:2]};
        end
    endfunction

    function automatic logic [7:0] expand_green(input rgb565_t color);
        logic [5:0] g6;
        begin
            g6 = color[10:5];
            return {g6, g6[5:4]};
        end
    endfunction

    function automatic logic [7:0] expand_blue(input rgb565_t color);
        logic [4:0] b5;
        begin
            b5 = color[4:0];
            return {b5, b5[4:2]};
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p3_frag <= '0;
            p3_valid <= 1'b0;
            p3_tex_enable <= 1'b0;
            p3_modulate_enable <= 1'b0;
            p3_filter_bilinear <= 1'b0;
            p3_weight_u <= 8'd0;
            p3_weight_v <= 8'd0;
            p3_r00 <= 8'd0; p3_g00 <= 8'd0; p3_b00 <= 8'd0;
            p3_r10 <= 8'd0; p3_g10 <= 8'd0; p3_b10 <= 8'd0;
            p3_r01 <= 8'd0; p3_g01 <= 8'd0; p3_b01 <= 8'd0;
            p3_r11 <= 8'd0; p3_g11 <= 8'd0; p3_b11 <= 8'd0;
        end else if (!stall) begin
            p3_valid <= p2_valid;
            p3_frag <= p2_frag;
            p3_tex_enable <= p2_tex_enable;
            p3_modulate_enable <= p2_modulate_enable;
            p3_filter_bilinear <= p2_filter_bilinear;
            p3_weight_u <= p2_weight_u;
            p3_weight_v <= p2_weight_v;

            // Unpack all 4 texels to 8-bit RGB
            p3_r00 <= expand_red(c00);   p3_g00 <= expand_green(c00);   p3_b00 <= expand_blue(c00);
            p3_r10 <= expand_red(c10);   p3_g10 <= expand_green(c10);   p3_b10 <= expand_blue(c10);
            p3_r01 <= expand_red(c01);   p3_g01 <= expand_green(c01);   p3_b01 <= expand_blue(c01);
            p3_r11 <= expand_red(c11);   p3_g11 <= expand_green(c11);   p3_b11 <= expand_blue(c11);
        end
    end

    // =========================================================================
    // Stage 4: Bilinear Interpolation
    // =========================================================================

    fragment_t p4_frag;
    logic p4_valid;
    logic p4_tex_enable;
    logic p4_modulate_enable;
    logic [7:0] p4_tex_r8, p4_tex_g8, p4_tex_b8;

    // Bilinear weights
    logic [7:0] inv_fx, inv_fy;
    logic [15:0] w00, w10, w01, w11;

    // Weighted sums (8-bit color * 16-bit weight * 4 terms = up to 26 bits)
    logic [25:0] sum_r, sum_g, sum_b;

    always_comb begin
        // Inverse weights: 255 - weight (approximates 1.0 - fraction)
        inv_fx = 8'd255 - p3_weight_u;
        inv_fy = 8'd255 - p3_weight_v;

        // Bilinear weights (16-bit each)
        // w00 = (1-fx) * (1-fy), w10 = fx * (1-fy), w01 = (1-fx) * fy, w11 = fx * fy
        w00 = inv_fx * inv_fy;
        w10 = p3_weight_u * inv_fy;
        w01 = inv_fx * p3_weight_v;
        w11 = p3_weight_u * p3_weight_v;

        // Weighted sum for each channel
        // result = (c00*w00 + c10*w10 + c01*w01 + c11*w11) >> 16
        sum_r = (p3_r00 * w00) + (p3_r10 * w10) + (p3_r01 * w01) + (p3_r11 * w11);
        sum_g = (p3_g00 * w00) + (p3_g10 * w10) + (p3_g01 * w01) + (p3_g11 * w11);
        sum_b = (p3_b00 * w00) + (p3_b10 * w10) + (p3_b01 * w01) + (p3_b11 * w11);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p4_frag <= '0;
            p4_valid <= 1'b0;
            p4_tex_enable <= 1'b0;
            p4_modulate_enable <= 1'b0;
            p4_tex_r8 <= 8'd0;
            p4_tex_g8 <= 8'd0;
            p4_tex_b8 <= 8'd0;
        end else if (!stall) begin
            p4_valid <= p3_valid;
            p4_frag <= p3_frag;
            p4_tex_enable <= p3_tex_enable;
            p4_modulate_enable <= p3_modulate_enable;

            if (p3_filter_bilinear) begin
                // Bilinear: extract 8-bit result from weighted sum
                // Shift right by 16 to normalize (weights sum to ~65025 ≈ 255*255)
                p4_tex_r8 <= sum_r[23:16];
                p4_tex_g8 <= sum_g[23:16];
                p4_tex_b8 <= sum_b[23:16];
            end else begin
                // Nearest: use c00 directly
                p4_tex_r8 <= p3_r00;
                p4_tex_g8 <= p3_g00;
                p4_tex_b8 <= p3_b00;
            end
        end
    end

    // =========================================================================
    // Stage 5: Color Modulation and Output
    // =========================================================================

    fragment_t p5_frag;
    logic p5_valid;
    rgb565_t p5_color;

    // Clamp vertex color to [0, 1] and extract 16-bit fractional part
    logic [15:0] vert_r16, vert_g16, vert_b16;

    always_comb begin
        // Clamp and extract fractional part for multiplication
        if (p4_frag.r[31]) begin
            vert_r16 = 16'h0000;
        end else if (p4_frag.r >= FP_ONE) begin
            vert_r16 = 16'hFFFF;
        end else begin
            vert_r16 = p4_frag.r[15:0];
        end

        if (p4_frag.g[31]) begin
            vert_g16 = 16'h0000;
        end else if (p4_frag.g >= FP_ONE) begin
            vert_g16 = 16'hFFFF;
        end else begin
            vert_g16 = p4_frag.g[15:0];
        end

        if (p4_frag.b[31]) begin
            vert_b16 = 16'h0000;
        end else if (p4_frag.b >= FP_ONE) begin
            vert_b16 = 16'hFFFF;
        end else begin
            vert_b16 = p4_frag.b[15:0];
        end
    end

    // Multiply texture color by vertex color
    // tex8 * vert16 = 24-bit result, take bits [23:16] as 8-bit output
    logic [23:0] mod_r, mod_g, mod_b;
    logic [7:0] out_r8, out_g8, out_b8;

    always_comb begin
        mod_r = p4_tex_r8 * vert_r16;
        mod_g = p4_tex_g8 * vert_g16;
        mod_b = p4_tex_b8 * vert_b16;

        out_r8 = mod_r[23:16];
        out_g8 = mod_g[23:16];
        out_b8 = mod_b[23:16];
    end

    // Modulated color packed to RGB565
    rgb565_t modulated_color;
    assign modulated_color = {out_r8[7:3], out_g8[7:2], out_b8[7:3]};

    // Passthrough color: convert vertex color to RGB565
    rgb565_t passthrough_color;

    always_comb begin
        logic [7:0] pass_r8, pass_g8, pass_b8;

        // Clamp and scale vertex colors to 8-bit
        if (p4_frag.r[31]) begin
            pass_r8 = 8'h00;
        end else if (p4_frag.r >= FP_ONE) begin
            pass_r8 = 8'hFF;
        end else begin
            pass_r8 = p4_frag.r[15:8];
        end

        if (p4_frag.g[31]) begin
            pass_g8 = 8'h00;
        end else if (p4_frag.g >= FP_ONE) begin
            pass_g8 = 8'hFF;
        end else begin
            pass_g8 = p4_frag.g[15:8];
        end

        if (p4_frag.b[31]) begin
            pass_b8 = 8'h00;
        end else if (p4_frag.b >= FP_ONE) begin
            pass_b8 = 8'hFF;
        end else begin
            pass_b8 = p4_frag.b[15:8];
        end

        passthrough_color = {pass_r8[7:3], pass_g8[7:2], pass_b8[7:3]};
    end

    // Texture-only color (no modulation)
    rgb565_t texture_only_color;
    assign texture_only_color = {p4_tex_r8[7:3], p4_tex_g8[7:2], p4_tex_b8[7:3]};

    // Final color selection
    rgb565_t final_color;

    always_comb begin
        if (!p4_tex_enable) begin
            // Passthrough: use vertex color directly
            final_color = passthrough_color;
        end else if (!p4_modulate_enable) begin
            // Texture only, no modulation
            final_color = texture_only_color;
        end else begin
            // Full texture + modulation
            final_color = modulated_color;
        end
    end

    // Stage 5 output register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p5_frag <= '0;
            p5_valid <= 1'b0;
            p5_color <= 16'h0000;
        end else if (!stall) begin
            p5_valid <= p4_valid;
            p5_frag <= p4_frag;
            p5_color <= final_color;
        end
    end

    // =========================================================================
    // Output Assignments
    // =========================================================================

    assign frag_out = p5_frag;
    assign color_out = p5_color;
    assign frag_out_valid = p5_valid;

endmodule
