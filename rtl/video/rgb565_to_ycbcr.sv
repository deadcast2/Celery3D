//-----------------------------------------------------------------------------
// rgb565_to_ycbcr.sv
// RGB565 to YCbCr 4:2:2 Converter for ADV7511
// Uses BT.601 coefficients (limited range output)
//
// Output format (4:2:2) - ADV7511 Style 1:
//   Even pixels: {Cb, Y} - Cb on high byte, Y on low byte
//   Odd pixels:  {Cr, Y} - Cr on high byte, Y on low byte
//-----------------------------------------------------------------------------

module rgb565_to_ycbcr (
    input  wire        clk_pixel,
    input  wire        rst_n,

    // RGB565 input
    input  wire [15:0] rgb565_in,       // [15:11]=R5, [10:5]=G6, [4:0]=B5
    input  wire        data_enable_in,
    input  wire        hsync_in,
    input  wire        vsync_in,

    // YCbCr 4:2:2 output (16-bit)
    output reg  [15:0] ycbcr_out,       // {Cb/Cr, Y}
    output reg         data_enable_out,
    output reg         hsync_out,
    output reg         vsync_out
);

    //=========================================================================
    // Stage 1: Expand RGB565 to RGB888
    //=========================================================================

    // Extract RGB565 components
    wire [4:0] r5 = rgb565_in[15:11];
    wire [5:0] g6 = rgb565_in[10:5];
    wire [4:0] b5 = rgb565_in[4:0];

    // Expand to 8 bits by replicating high bits
    wire [7:0] r8 = {r5, r5[4:2]};
    wire [7:0] g8 = {g6, g6[5:4]};
    wire [7:0] b8 = {b5, b5[4:2]};

    //=========================================================================
    // Stage 1 Pipeline Register
    //=========================================================================
    reg [7:0] r8_p1, g8_p1, b8_p1;
    reg de_p1, hsync_p1, vsync_p1;
    reg pixel_phase_p1;  // 0=even, 1=odd

    // Track even/odd pixel phase within each line
    reg pixel_phase;

    always_ff @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            pixel_phase <= 1'b0;
        end else if (!data_enable_in) begin
            // Reset phase at start of each line
            pixel_phase <= 1'b0;
        end else begin
            pixel_phase <= ~pixel_phase;
        end
    end

    always_ff @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            r8_p1 <= 8'd0;
            g8_p1 <= 8'd0;
            b8_p1 <= 8'd0;
            de_p1 <= 1'b0;
            hsync_p1 <= 1'b0;
            vsync_p1 <= 1'b0;
            pixel_phase_p1 <= 1'b0;
        end else begin
            r8_p1 <= r8;
            g8_p1 <= g8;
            b8_p1 <= b8;
            de_p1 <= data_enable_in;
            hsync_p1 <= hsync_in;
            vsync_p1 <= vsync_in;
            pixel_phase_p1 <= pixel_phase;
        end
    end

    //=========================================================================
    // Stage 2: RGB to YCbCr Conversion (BT.601 Limited Range)
    //=========================================================================
    //
    // BT.601 equations:
    //   Y  = 16 + (66*R + 129*G + 25*B) >> 8
    //   Cb = 128 + (-38*R - 74*G + 112*B + 128) >> 8
    //   Cr = 128 + (112*R - 94*G - 18*B + 128) >> 8

    // Intermediate products
    reg signed [15:0] y_prod, cb_prod, cr_prod;

    // Use signed arithmetic for Cb/Cr
    wire signed [9:0] r_signed = {2'b00, r8_p1};
    wire signed [9:0] g_signed = {2'b00, g8_p1};
    wire signed [9:0] b_signed = {2'b00, b8_p1};

    always_comb begin
        // Y = 66*R + 129*G + 25*B
        y_prod = 16'(66 * r8_p1) + 16'(129 * g8_p1) + 16'(25 * b8_p1);

        // Cb = -38*R - 74*G + 112*B
        cb_prod = -16'sd38 * r_signed - 16'sd74 * g_signed + 16'sd112 * b_signed;

        // Cr = 112*R - 94*G - 18*B
        cr_prod = 16'sd112 * r_signed - 16'sd94 * g_signed - 16'sd18 * b_signed;
    end

    // Final Y, Cb, Cr with offset and rounding
    wire [7:0] y_val, cb_val, cr_val;

    // Y = 16 + (y_prod + 128) >> 8, range [16, 235]
    assign y_val = 8'd16 + y_prod[15:8];

    // Cb = 128 + (cb_prod + 128) >> 8, range [16, 240]
    // Add 128*256 = 32768 before shifting to add 128 offset
    assign cb_val = 8'((cb_prod + 16'sd128 + 16'sd32768) >>> 8);

    // Cr = 128 + (cr_prod + 128) >> 8, range [16, 240]
    assign cr_val = 8'((cr_prod + 16'sd128 + 16'sd32768) >>> 8);

    //=========================================================================
    // Stage 2 Pipeline Register + 4:2:2 Output
    //=========================================================================

    // Output: even pixels get {Cb, Y}, odd pixels get {Cr, Y}
    always_ff @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            ycbcr_out <= 16'h8010;      // Black in YCbCr (Cb/Cr=128, Y=16)
            data_enable_out <= 1'b0;
            hsync_out <= 1'b0;
            vsync_out <= 1'b0;
        end else begin
            data_enable_out <= de_p1;
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
