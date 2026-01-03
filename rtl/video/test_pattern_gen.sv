//-----------------------------------------------------------------------------
// test_pattern_gen.sv
// Test pattern generator for display validation
// Outputs RGB565 color bars and other patterns
//-----------------------------------------------------------------------------

module test_pattern_gen (
    input  wire        clk_pixel,
    input  wire        rst_n,

    // Timing inputs from video_timing_gen
    input  wire [9:0]  pixel_x,
    input  wire [9:0]  pixel_y,
    input  wire        data_enable,

    // Pattern select (directly active high for ADV7511 can be tied to DIP switches)
    input  wire [2:0]  pattern_sel,

    // RGB565 output [15:11]=R, [10:5]=G, [4:0]=B
    output reg  [15:0] rgb565,
    output reg         rgb565_valid
);

    //-------------------------------------------------------------------------
    // RGB565 color definitions
    //-------------------------------------------------------------------------
    localparam [15:0] COLOR_WHITE   = 16'hFFFF;  // R=31, G=63, B=31
    localparam [15:0] COLOR_YELLOW  = 16'hFFE0;  // R=31, G=63, B=0
    localparam [15:0] COLOR_CYAN    = 16'h07FF;  // R=0,  G=63, B=31
    localparam [15:0] COLOR_GREEN   = 16'h07E0;  // R=0,  G=63, B=0
    localparam [15:0] COLOR_MAGENTA = 16'hF81F;  // R=31, G=0,  B=31
    localparam [15:0] COLOR_RED     = 16'hF800;  // R=31, G=0,  B=0
    localparam [15:0] COLOR_BLUE    = 16'h001F;  // R=0,  G=0,  B=31
    localparam [15:0] COLOR_BLACK   = 16'h0000;  // R=0,  G=0,  B=0

    //-------------------------------------------------------------------------
    // Pattern generation
    //-------------------------------------------------------------------------
    reg [2:0] bar_index;
    reg [15:0] pattern_color;

    // 640 pixels / 8 bars = 80 pixels per bar
    // Use scaled comparison since 80 isn't a power of 2
    wire [5:0] scaled_x = pixel_x[9:4];  // Divide by 16, gives 0-39
    always_comb begin
        if (scaled_x < 6'd5)       bar_index = 3'd0;  // 0-79
        else if (scaled_x < 6'd10) bar_index = 3'd1;  // 80-159
        else if (scaled_x < 6'd15) bar_index = 3'd2;  // 160-239
        else if (scaled_x < 6'd20) bar_index = 3'd3;  // 240-319
        else if (scaled_x < 6'd25) bar_index = 3'd4;  // 320-399
        else if (scaled_x < 6'd30) bar_index = 3'd5;  // 400-479
        else if (scaled_x < 6'd35) bar_index = 3'd6;  // 480-559
        else                       bar_index = 3'd7;  // 560-639
    end

    // Color bar pattern
    reg [15:0] colorbar_color;
    always_comb begin
        case (bar_index)
            3'd0: colorbar_color = COLOR_WHITE;
            3'd1: colorbar_color = COLOR_YELLOW;
            3'd2: colorbar_color = COLOR_CYAN;
            3'd3: colorbar_color = COLOR_GREEN;
            3'd4: colorbar_color = COLOR_MAGENTA;
            3'd5: colorbar_color = COLOR_RED;
            3'd6: colorbar_color = COLOR_BLUE;
            3'd7: colorbar_color = COLOR_BLACK;
            default: colorbar_color = COLOR_BLACK;
        endcase
    end

    // Horizontal gradient (red intensity varies with x)
    wire [15:0] h_gradient;
    wire [4:0] red_grad = pixel_x[9:5];     // 0-31 over 640 pixels
    assign h_gradient = {red_grad, 6'd0, 5'd0};

    // Vertical gradient (green intensity varies with y)
    wire [15:0] v_gradient;
    wire [5:0] green_grad = {pixel_y[8:4], 1'b0};  // 0-62 over 480 pixels
    assign v_gradient = {5'd0, green_grad, 5'd0};

    // Grid pattern (white lines on black)
    wire [15:0] grid_color;
    wire grid_line = (pixel_x[4:0] == 5'd0) || (pixel_y[4:0] == 5'd0);
    assign grid_color = grid_line ? COLOR_WHITE : COLOR_BLACK;

    // Checkerboard pattern
    wire [15:0] checkerboard_color;
    wire checkerboard_sel = pixel_x[5] ^ pixel_y[5];
    assign checkerboard_color = checkerboard_sel ? COLOR_WHITE : COLOR_BLACK;

    // Solid colors (cycle through primaries based on lower pattern bits)
    reg [15:0] solid_color;
    always_comb begin
        case (pixel_y[8:7])  // Change color in vertical bands
            2'd0: solid_color = COLOR_RED;
            2'd1: solid_color = COLOR_GREEN;
            2'd2: solid_color = COLOR_BLUE;
            2'd3: solid_color = COLOR_WHITE;
            default: solid_color = COLOR_BLACK;
        endcase
    end

    //-------------------------------------------------------------------------
    // Pattern selection
    //-------------------------------------------------------------------------
    always_comb begin
        case (pattern_sel)
            3'd0: pattern_color = colorbar_color;   // Color bars (default)
            3'd1: pattern_color = h_gradient;       // Horizontal red gradient
            3'd2: pattern_color = v_gradient;       // Vertical green gradient
            3'd3: pattern_color = grid_color;       // Grid pattern
            3'd4: pattern_color = checkerboard_color; // Checkerboard
            3'd5: pattern_color = solid_color;      // Solid color bands
            3'd6: pattern_color = COLOR_WHITE;      // Full white
            3'd7: pattern_color = COLOR_BLACK;      // Full black
            default: pattern_color = colorbar_color;
        endcase
    end

    //-------------------------------------------------------------------------
    // Output registration
    //-------------------------------------------------------------------------
    always_ff @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            rgb565 <= 16'd0;
            rgb565_valid <= 1'b0;
        end else begin
            rgb565_valid <= data_enable;
            if (data_enable)
                rgb565 <= pattern_color;
            else
                rgb565 <= 16'd0;
        end
    end

endmodule
