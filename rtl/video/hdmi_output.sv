//-----------------------------------------------------------------------------
// hdmi_output.sv
// HDMI output interface for ADV7511
// Registers outputs and generates pixel clock output
//-----------------------------------------------------------------------------

module hdmi_output (
    input  wire        clk_pixel,
    input  wire        rst_n,

    // Video input (from color converter)
    input  wire [15:0] ycbcr_data,      // YCbCr 4:2:2 data
    input  wire        data_enable,
    input  wire        hsync,
    input  wire        vsync,

    // HDMI output pins
    output wire        hdmi_clk,        // Pixel clock to ADV7511
    output reg  [15:0] hdmi_data,       // 16-bit video data
    output reg         hdmi_de,         // Data enable
    output reg         hdmi_hsync,      // Horizontal sync
    output reg         hdmi_vsync       // Vertical sync
);

    //-------------------------------------------------------------------------
    // Output clock generation using ODDR
    // This ensures clean clock output with proper timing
    //-------------------------------------------------------------------------
    ODDR #(
        .DDR_CLK_EDGE ("OPPOSITE_EDGE"),
        .INIT         (1'b0),
        .SRTYPE       ("SYNC")
    ) oddr_clk (
        .Q  (hdmi_clk),
        .C  (clk_pixel),
        .CE (1'b1),
        .D1 (1'b1),
        .D2 (1'b0),
        .R  (1'b0),
        .S  (1'b0)
    );

    //-------------------------------------------------------------------------
    // Register all outputs for timing closure
    // ADV7511 samples on rising edge of hdmi_clk
    //-------------------------------------------------------------------------
    always_ff @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            hdmi_data <= 16'd0;
            hdmi_de <= 1'b0;
            hdmi_hsync <= 1'b0;
            hdmi_vsync <= 1'b0;
        end else begin
            hdmi_data <= ycbcr_data;
            hdmi_de <= data_enable;
            hdmi_hsync <= hsync;
            hdmi_vsync <= vsync;
        end
    end

endmodule
