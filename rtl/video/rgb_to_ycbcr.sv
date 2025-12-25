// Celery3D GPU - RGB to YCbCr 4:2:2 Converter
// Converts RGB565 to 16-bit YCbCr 4:2:2 for ADV7511
// Uses BT.601 coefficients (standard definition)
//
// Output format (4:2:2) - ADV7511 Style 1:
//   Even pixels: {Cb, Y0} - Cb on high byte, Y on low byte
//   Odd pixels:  {Cr, Y1} - Cr on high byte, Y on low byte

module rgb_to_ycbcr
    import video_pkg::*;
    import celery_pkg::rgb565_t;
(
    input  logic        pixel_clk,
    input  logic        rst_n,

    // RGB565 input with timing
    input  rgb565_t     rgb565_in,
    input  logic        de_in,
    input  logic        hsync_in,
    input  logic        vsync_in,

    // YCbCr 4:2:2 output (16-bit)
    output logic [15:0] ycbcr_out,    // {Cb/Cr, Y}
    output logic        de_out,
    output logic        hsync_out,
    output logic        vsync_out
);

    // =========================================================================
    // Stage 1: Expand RGB565 to RGB888
    // =========================================================================

    // Extract RGB565 components
    logic [4:0] r5;
    logic [5:0] g6;
    logic [4:0] b5;

    assign r5 = rgb565_in[15:11];
    assign g6 = rgb565_in[10:5];
    assign b5 = rgb565_in[4:0];

    // Expand to 8 bits by replicating high bits
    // R: 5 bits -> 8 bits: {R5, R5[4:2]}
    // G: 6 bits -> 8 bits: {G6, G6[5:4]}
    // B: 5 bits -> 8 bits: {B5, B5[4:2]}
    logic [7:0] r8, g8, b8;

    assign r8 = {r5, r5[4:2]};
    assign g8 = {g6, g6[5:4]};
    assign b8 = {b5, b5[4:2]};

    // =========================================================================
    // Stage 1 Pipeline Register
    // =========================================================================
    logic [7:0] r8_p1, g8_p1, b8_p1;
    logic       de_p1, hsync_p1, vsync_p1;
    logic       pixel_phase_p1;  // 0=even, 1=odd

    // Track even/odd pixel phase within each line
    logic pixel_phase;

    always_ff @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_phase <= 1'b0;
        end else if (!de_in) begin
            // Reset phase at start of each line
            pixel_phase <= 1'b0;
        end else begin
            pixel_phase <= ~pixel_phase;
        end
    end

    always_ff @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            r8_p1 <= 8'd0;
            g8_p1 <= 8'd0;
            b8_p1 <= 8'd0;
            de_p1 <= 1'b0;
            hsync_p1 <= 1'b1;
            vsync_p1 <= 1'b1;
            pixel_phase_p1 <= 1'b0;
        end else begin
            r8_p1 <= r8;
            g8_p1 <= g8;
            b8_p1 <= b8;
            de_p1 <= de_in;
            hsync_p1 <= hsync_in;
            vsync_p1 <= vsync_in;
            pixel_phase_p1 <= pixel_phase;
        end
    end

    // =========================================================================
    // Stage 2: RGB to YCbCr Conversion (BT.601 Limited Range)
    // =========================================================================
    //
    // BT.601 equations (full range input, limited range output):
    //   Y  =  16 + (65.481*R + 128.553*G + 24.966*B) / 256
    //   Cb = 128 + (-37.797*R - 74.203*G + 112.0*B) / 256
    //   Cr = 128 + (112.0*R - 93.786*G - 18.214*B) / 256
    //
    // Fixed-point coefficients (multiply by 256):
    //   Y  = 16 + (66*R + 129*G + 25*B) >> 8
    //   Cb = 128 + ((-38*R - 74*G + 112*B) + 128) >> 8
    //   Cr = 128 + ((112*R - 94*G - 18*B) + 128) >> 8

    // Intermediate products (need 16 bits for 8x8 multiply)
    logic signed [15:0] y_prod, cb_prod, cr_prod;

    // Use signed arithmetic for Cb/Cr (can go negative before offset)
    logic signed [9:0] r_signed, g_signed, b_signed;

    assign r_signed = {2'b00, r8_p1};
    assign g_signed = {2'b00, g8_p1};
    assign b_signed = {2'b00, b8_p1};

    always_comb begin
        // Y = 66*R + 129*G + 25*B
        y_prod = 16'(66 * r8_p1) + 16'(129 * g8_p1) + 16'(25 * b8_p1);

        // Cb = -38*R - 74*G + 112*B
        cb_prod = -16'sd38 * r_signed - 16'sd74 * g_signed + 16'sd112 * b_signed;

        // Cr = 112*R - 94*G - 18*B
        cr_prod = 16'sd112 * r_signed - 16'sd94 * g_signed - 16'sd18 * b_signed;
    end

    // Final Y, Cb, Cr with offset and rounding
    logic [7:0] y_val, cb_val, cr_val;

    always_comb begin
        // Y = 16 + (y_prod + 128) >> 8, range [16, 235]
        y_val = 8'd16 + y_prod[15:8];

        // Cb = 128 + (cb_prod + 128) >> 8, range [16, 240]
        // Add 128*256 = 32768 before shifting
        cb_val = 8'((cb_prod + 16'sd128 + 16'sd32768) >>> 8);

        // Cr = 128 + (cr_prod + 128) >> 8, range [16, 240]
        cr_val = 8'((cr_prod + 16'sd128 + 16'sd32768) >>> 8);
    end

    // =========================================================================
    // Stage 2 Pipeline Register + 4:2:2 Subsampling
    // =========================================================================

    // Store Cb from even pixel to pair with odd pixel
    logic [7:0] cb_saved;

    always_ff @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            cb_saved <= 8'd128;
        end else if (de_p1 && !pixel_phase_p1) begin
            // Save Cb from even pixel
            cb_saved <= cb_val;
        end
    end

    // Output: even pixels get {Cb, Y}, odd pixels get {Cr, Y}
    always_ff @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            ycbcr_out <= 16'h8010;  // Black in YCbCr (Cb/Cr=128, Y=16)
            de_out    <= 1'b0;
            hsync_out <= 1'b1;
            vsync_out <= 1'b1;
        end else begin
            de_out    <= de_p1;
            hsync_out <= hsync_p1;
            vsync_out <= vsync_p1;

            if (de_p1) begin
                if (!pixel_phase_p1) begin
                    // Even pixel: output {Cb, Y}
                    ycbcr_out <= {cb_val, y_val};
                end else begin
                    // Odd pixel: output {Cr, Y}
                    ycbcr_out <= {cr_val, y_val};
                end
            end else begin
                // Blanking: output black
                ycbcr_out <= 16'h8010;  // Cb/Cr=128, Y=16
            end
        end
    end

endmodule
