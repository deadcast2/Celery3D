// Celery3D GPU - Texture Mapping Unit
// Nearest-neighbor sampling with Gouraud color modulation
// 3-stage pipeline: UV wrap/address → BRAM read → color modulate
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
    parameter ADDR_BITS  = TEX_WIDTH_LOG2 + TEX_HEIGHT_LOG2
)(
    input  logic        clk,
    input  logic        rst_n,

    // Configuration
    input  logic        tex_enable,       // Enable texture sampling
    input  logic        modulate_enable,  // Enable Gouraud modulation

    // Input fragment (from perspective_correct)
    input  fragment_t   frag_in,
    input  logic        frag_in_valid,
    output logic        frag_in_ready,

    // Output fragment (textured/modulated)
    output fragment_t   frag_out,
    output rgb565_t     color_out,        // Final RGB565 color
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
    assign stall = p3_valid && !frag_out_ready;
    assign frag_in_ready = !stall;

    // =========================================================================
    // Texture BRAM
    // =========================================================================

    rgb565_t tex_mem [0:TEX_SIZE-1];
    rgb565_t tex_read_data;
    logic [ADDR_BITS-1:0] tex_rd_addr;

    // Write port (for loading textures)
    always_ff @(posedge clk) begin
        if (tex_wr_en) begin
            tex_mem[tex_wr_addr] <= tex_wr_data;
        end
    end

    // Read port (synchronous, 1-cycle latency for BRAM)
    always_ff @(posedge clk) begin
        if (!stall) begin
            tex_read_data <= tex_mem[tex_rd_addr];
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
            // Example: UV = -0.25, frac = 0x4000, we want 0xC000 (0.75)
            if (uv[31] && frac != 0) begin
                temp = 17'h10000 - {1'b0, frac};  // 1.0 - frac (17-bit intermediate)
                frac = temp[15:0];  // Result is always < 1.0 when frac != 0
            end

            return frac;
        end
    endfunction

    // =========================================================================
    // Stage 1: UV Wrapping and Address Calculation
    // =========================================================================

    fragment_t p1_frag;
    logic p1_valid;
    logic [ADDR_BITS-1:0] p1_tex_addr;
    logic p1_tex_enable;
    logic p1_modulate_enable;

    logic [15:0] u_wrapped, v_wrapped;
    logic [TEX_WIDTH_LOG2-1:0]  u_texel;
    logic [TEX_HEIGHT_LOG2-1:0] v_texel;

    always_comb begin
        // Wrap UV coordinates
        u_wrapped = wrap_uv(frag_in.u);
        v_wrapped = wrap_uv(frag_in.v);

        // Extract texel indices from top bits of fractional part
        // frac[15:0] represents [0, 1), so frac * TEX_SIZE = frac[15 -: LOG2]
        u_texel = u_wrapped[15 -: TEX_WIDTH_LOG2];
        v_texel = v_wrapped[15 -: TEX_HEIGHT_LOG2];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p1_frag <= '0;
            p1_valid <= 1'b0;
            p1_tex_addr <= '0;
            p1_tex_enable <= 1'b0;
            p1_modulate_enable <= 1'b0;
        end else if (!stall) begin
            p1_valid <= frag_in_valid && frag_in.valid;
            p1_frag <= frag_in;
            p1_tex_addr <= {v_texel, u_texel};
            p1_tex_enable <= tex_enable;
            p1_modulate_enable <= modulate_enable;
        end
    end

    // Feed address to BRAM read port - use combinatorial address so BRAM
    // reads the correct texel on this clock edge, data available next cycle
    assign tex_rd_addr = {v_texel, u_texel};

    // =========================================================================
    // Stage 2: BRAM Read (data arrives this cycle)
    // =========================================================================

    fragment_t p2_frag;
    logic p2_valid;
    logic p2_tex_enable;
    logic p2_modulate_enable;
    rgb565_t p2_tex_data;  // Registered texture data aligned with p2_frag

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p2_frag <= '0;
            p2_valid <= 1'b0;
            p2_tex_enable <= 1'b0;
            p2_modulate_enable <= 1'b0;
            p2_tex_data <= 16'h0000;
        end else if (!stall) begin
            p2_valid <= p1_valid;
            p2_frag <= p1_frag;
            p2_tex_enable <= p1_tex_enable;
            p2_modulate_enable <= p1_modulate_enable;
            p2_tex_data <= tex_read_data;  // Capture texture data for this fragment
        end
    end

    // =========================================================================
    // Stage 3: Color Modulation and Output
    // =========================================================================

    fragment_t p3_frag;
    logic p3_valid;
    rgb565_t p3_color;

    // Unpack RGB565 texture color (use registered p2_tex_data, not tex_read_data)
    red_t   tex_r;
    green_t tex_g;
    blue_t  tex_b;

    assign tex_r = unpack_red(p2_tex_data);
    assign tex_g = unpack_green(p2_tex_data);
    assign tex_b = unpack_blue(p2_tex_data);

    // Expand to 8-bit for better precision during multiply
    // R: 5-bit -> 8-bit: replicate top bits
    // G: 6-bit -> 8-bit: replicate top bits
    // B: 5-bit -> 8-bit: replicate top bits
    logic [7:0] tex_r8, tex_g8, tex_b8;
    assign tex_r8 = {tex_r, tex_r[4:2]};
    assign tex_g8 = {tex_g, tex_g[5:4]};
    assign tex_b8 = {tex_b, tex_b[4:2]};

    // Clamp vertex color to [0, 1] and extract 16-bit fractional part
    logic [15:0] vert_r16, vert_g16, vert_b16;

    always_comb begin
        // Clamp and extract fractional part for multiplication
        // If negative, clamp to 0
        // If >= 1.0, use full scale (0xFFFF)
        // Otherwise, use fractional bits

        if (p2_frag.r[31]) begin
            vert_r16 = 16'h0000;
        end else if (p2_frag.r >= FP_ONE) begin
            vert_r16 = 16'hFFFF;
        end else begin
            vert_r16 = p2_frag.r[15:0];
        end

        if (p2_frag.g[31]) begin
            vert_g16 = 16'h0000;
        end else if (p2_frag.g >= FP_ONE) begin
            vert_g16 = 16'hFFFF;
        end else begin
            vert_g16 = p2_frag.g[15:0];
        end

        if (p2_frag.b[31]) begin
            vert_b16 = 16'h0000;
        end else if (p2_frag.b >= FP_ONE) begin
            vert_b16 = 16'hFFFF;
        end else begin
            vert_b16 = p2_frag.b[15:0];
        end
    end

    // Multiply texture color by vertex color
    // tex8 * vert16 = 24-bit result, take bits [23:16] as 8-bit output
    logic [23:0] mod_r, mod_g, mod_b;
    logic [7:0] out_r8, out_g8, out_b8;

    always_comb begin
        mod_r = tex_r8 * vert_r16;
        mod_g = tex_g8 * vert_g16;
        mod_b = tex_b8 * vert_b16;

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
        if (p2_frag.r[31]) begin
            pass_r8 = 8'h00;
        end else if (p2_frag.r >= FP_ONE) begin
            pass_r8 = 8'hFF;
        end else begin
            pass_r8 = p2_frag.r[15:8];
        end

        if (p2_frag.g[31]) begin
            pass_g8 = 8'h00;
        end else if (p2_frag.g >= FP_ONE) begin
            pass_g8 = 8'hFF;
        end else begin
            pass_g8 = p2_frag.g[15:8];
        end

        if (p2_frag.b[31]) begin
            pass_b8 = 8'h00;
        end else if (p2_frag.b >= FP_ONE) begin
            pass_b8 = 8'hFF;
        end else begin
            pass_b8 = p2_frag.b[15:8];
        end

        passthrough_color = {pass_r8[7:3], pass_g8[7:2], pass_b8[7:3]};
    end

    // Final color selection
    rgb565_t final_color;

    always_comb begin
        if (!p2_tex_enable) begin
            // Passthrough: use vertex color directly
            final_color = passthrough_color;
        end else if (!p2_modulate_enable) begin
            // Texture only, no modulation
            final_color = p2_tex_data;
        end else begin
            // Full texture + modulation
            final_color = modulated_color;
        end
    end

    // Stage 3 output register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p3_frag <= '0;
            p3_valid <= 1'b0;
            p3_color <= 16'h0000;
        end else if (!stall) begin
            p3_valid <= p2_valid;
            p3_frag <= p2_frag;
            p3_color <= final_color;
        end
    end

    // =========================================================================
    // Output Assignments
    // =========================================================================

    assign frag_out = p3_frag;
    assign color_out = p3_color;
    assign frag_out_valid = p3_valid;

endmodule
