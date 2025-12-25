// Celery3D GPU - Test Pattern Generator
// Generates color bar test pattern in RGB565 format
// 8 vertical bars: White, Yellow, Cyan, Green, Magenta, Red, Blue, Black

module test_pattern_gen
    import video_pkg::*;
    import celery_pkg::rgb565_t;
(
    input  logic        pixel_clk,
    input  logic        rst_n,

    // Timing inputs (from video_timing_gen)
    input  logic        de,
    input  logic [9:0]  pixel_x,
    input  logic [9:0]  pixel_y,

    // Pattern selection
    input  logic [1:0]  pattern_sel,  // 0=color bars, 1=gradient, 2=grid, 3=solid

    // RGB565 output
    output rgb565_t     rgb565_out,
    output logic        de_out
);

    // Color bar RGB565 values (SMPTE-style color bars)
    // Each bar is 80 pixels wide (640 / 8 = 80)
    localparam rgb565_t COLOR_WHITE   = 16'hFFFF;  // R=31, G=63, B=31
    localparam rgb565_t COLOR_YELLOW  = 16'hFFE0;  // R=31, G=63, B=0
    localparam rgb565_t COLOR_CYAN    = 16'h07FF;  // R=0,  G=63, B=31
    localparam rgb565_t COLOR_GREEN   = 16'h07E0;  // R=0,  G=63, B=0
    localparam rgb565_t COLOR_MAGENTA = 16'hF81F;  // R=31, G=0,  B=31
    localparam rgb565_t COLOR_RED     = 16'hF800;  // R=31, G=0,  B=0
    localparam rgb565_t COLOR_BLUE    = 16'h001F;  // R=0,  G=0,  B=31
    localparam rgb565_t COLOR_BLACK   = 16'h0000;  // R=0,  G=0,  B=0

    // Bar width (640 pixels / 8 bars = 80 pixels each)
    localparam BAR_WIDTH = 80;

    // Internal signals
    logic [2:0] bar_index;
    rgb565_t color_bars;
    rgb565_t color_gradient;
    rgb565_t color_grid;
    rgb565_t color_selected;

    // Calculate which bar we're in (divide x by 80)
    // Using shifts for efficiency: 80 = 64 + 16 is awkward
    // Instead use a simple comparison chain
    always_comb begin
        if (pixel_x < 80)
            bar_index = 3'd0;
        else if (pixel_x < 160)
            bar_index = 3'd1;
        else if (pixel_x < 240)
            bar_index = 3'd2;
        else if (pixel_x < 320)
            bar_index = 3'd3;
        else if (pixel_x < 400)
            bar_index = 3'd4;
        else if (pixel_x < 480)
            bar_index = 3'd5;
        else if (pixel_x < 560)
            bar_index = 3'd6;
        else
            bar_index = 3'd7;
    end

    // Color bar pattern
    always_comb begin
        case (bar_index)
            3'd0: color_bars = COLOR_WHITE;
            3'd1: color_bars = COLOR_YELLOW;
            3'd2: color_bars = COLOR_CYAN;
            3'd3: color_bars = COLOR_GREEN;
            3'd4: color_bars = COLOR_MAGENTA;
            3'd5: color_bars = COLOR_RED;
            3'd6: color_bars = COLOR_BLUE;
            3'd7: color_bars = COLOR_BLACK;
        endcase
    end

    // Gradient pattern: Red increases left-to-right, Green increases top-to-bottom
    logic [4:0] red_grad;
    logic [5:0] green_grad;
    logic [4:0] blue_grad;

    assign red_grad   = pixel_x[9:5];     // 0-31 across 640 pixels (div by 20)
    assign green_grad = pixel_y[8:3];     // 0-63 across 480 pixels (div by 7.5)
    assign blue_grad  = 5'd0;
    assign color_gradient = {red_grad, green_grad, blue_grad};

    // Grid pattern: 32x32 pixel grid with white lines on black
    logic grid_line;
    assign grid_line = (pixel_x[4:0] == 5'd0) || (pixel_y[4:0] == 5'd0);
    assign color_grid = grid_line ? COLOR_WHITE : COLOR_BLACK;

    // Pattern selection mux
    always_comb begin
        case (pattern_sel)
            2'd0: color_selected = color_bars;
            2'd1: color_selected = color_gradient;
            2'd2: color_selected = color_grid;
            2'd3: color_selected = COLOR_WHITE;  // Solid white for testing
        endcase
    end

    // Register output (align with DE timing)
    always_ff @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            rgb565_out <= 16'h0000;
            de_out     <= 1'b0;
        end else begin
            rgb565_out <= color_selected;
            de_out     <= de;
        end
    end

endmodule
