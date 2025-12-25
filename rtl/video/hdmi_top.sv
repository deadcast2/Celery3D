// Celery3D GPU - HDMI Output Top Level
// Integrates video timing, test pattern, color conversion, and ADV7511 init
// Target: KC705 with ADV7511 HDMI transmitter

module hdmi_top
    import video_pkg::*;
    import celery_pkg::rgb565_t;
#(
    // Framebuffer dimensions (for coordinate scaling)
    // 640/64 = 10x horizontal scale, 480/64 = 7.5 (use 7, with 32 black lines at bottom)
    parameter FB_WIDTH  = 64,
    parameter FB_HEIGHT = 64,
    parameter H_SCALE   = 10,    // 640 / 64 = 10
    parameter V_SCALE   = 7      // 448 / 64 = 7 (480 - 32 = 448)
)(
    input  logic        clk_50mhz,    // 50 MHz system clock (for I2C)
    input  logic        clk_25mhz,    // 25 MHz pixel clock (from parent MMCM)
    input  logic        rst_n,        // Active-low reset

    // HDMI output pins (directly to ADV7511)
    output logic [15:0] hdmi_d,       // YCbCr 4:2:2 data
    output logic        hdmi_clk,     // Pixel clock to ADV7511
    output logic        hdmi_de,      // Data enable
    output logic        hdmi_hsync,   // Horizontal sync
    output logic        hdmi_vsync,   // Vertical sync

    // I2C for ADV7511 configuration
    output logic        i2c_scl_o,
    output logic        i2c_scl_oen,
    input  logic        i2c_scl_i,
    output logic        i2c_sda_o,
    output logic        i2c_sda_oen,
    input  logic        i2c_sda_i,

    // Optional: Framebuffer interface (directly from rasterizer)
    // Note: Coordinates are scaled down from 640x480 to FB_WIDTH x FB_HEIGHT
    output logic [$clog2(FB_WIDTH)-1:0]  fb_read_x,
    output logic [$clog2(FB_HEIGHT)-1:0] fb_read_y,
    output logic        fb_read_en,
    input  rgb565_t     fb_read_data,
    input  logic        fb_read_valid,

    // Control
    input  logic [1:0]  pattern_sel,      // Test pattern selection
    input  logic        use_framebuffer,  // 0=test pattern, 1=framebuffer

    // Status
    output logic        hdmi_init_done,
    output logic        hdmi_init_error
);

    // =========================================================================
    // Internal Signals
    // =========================================================================

    // Clocks and reset
    logic pixel_clk;
    logic rst_pixel_n;

    // Video timing signals
    logic        timing_hsync;
    logic        timing_vsync;
    logic        timing_de;
    logic [9:0]  timing_x;
    logic [9:0]  timing_y;
    logic        frame_start;
    logic        line_start;

    // Test pattern output
    rgb565_t     pattern_rgb;
    logic        pattern_de;

    // Selected RGB source
    rgb565_t     selected_rgb;
    logic        selected_de;
    logic        selected_hsync;
    logic        selected_vsync;

    // YCbCr converter output
    logic [15:0] ycbcr_data;
    logic        ycbcr_de;
    logic        ycbcr_hsync;
    logic        ycbcr_vsync;

    // I2C signals
    logic [6:0]  i2c_slave_addr;
    logic [7:0]  i2c_reg_addr;
    logic [7:0]  i2c_write_data;
    logic        i2c_write_req;
    logic        i2c_single_byte;
    logic        i2c_busy;
    logic        i2c_done;
    logic        i2c_ack_error;

    // =========================================================================
    // Pixel Clock - use 25 MHz from parent MMCM directly
    // =========================================================================

    assign pixel_clk = clk_25mhz;

    // Synchronize reset to pixel clock domain
    logic [2:0] rst_sync_reg;

    always_ff @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            rst_sync_reg <= 3'b000;
        end else begin
            rst_sync_reg <= {rst_sync_reg[1:0], 1'b1};  // Lock always true when clk present
        end
    end

    assign rst_pixel_n = rst_sync_reg[2];

    // =========================================================================
    // Video Timing Generator
    // =========================================================================

    video_timing_gen u_timing_gen (
        .pixel_clk    (pixel_clk),
        .rst_n        (rst_pixel_n),
        .hsync        (timing_hsync),
        .vsync        (timing_vsync),
        .de           (timing_de),
        .pixel_x      (timing_x),
        .pixel_y      (timing_y),
        .frame_start  (frame_start),
        .line_start   (line_start)
    );

    // =========================================================================
    // Test Pattern Generator
    // =========================================================================

    test_pattern_gen u_test_pattern (
        .pixel_clk    (pixel_clk),
        .rst_n        (rst_pixel_n),
        .de           (timing_de),
        .pixel_x      (timing_x),
        .pixel_y      (timing_y),
        .pattern_sel  (pattern_sel),
        .rgb565_out   (pattern_rgb),
        .de_out       (pattern_de)
    );

    // =========================================================================
    // Source Selection (Test Pattern vs Framebuffer)
    // =========================================================================

    // Framebuffer read interface with coordinate scaling
    // Scale 640x480 display coordinates to 64x64 framebuffer
    // Each framebuffer pixel maps to a H_SCALE x V_SCALE block on screen
    localparam V_ACTIVE = FB_HEIGHT * V_SCALE;  // 64 * 7 = 448 active lines

    // Scaled coordinates (integer division for nearest-neighbor upscaling)
    logic [$clog2(FB_WIDTH)-1:0]  scaled_x;
    logic [$clog2(FB_HEIGHT)-1:0] scaled_y;
    logic in_active_region;

    always_comb begin
        scaled_x = timing_x / H_SCALE;  // 0-639 -> 0-63
        scaled_y = timing_y / V_SCALE;  // 0-447 -> 0-63 (448-479 = black)
        in_active_region = (timing_y < V_ACTIVE);
    end

    assign fb_read_x = scaled_x;
    assign fb_read_y = scaled_y;
    assign fb_read_en = timing_de && use_framebuffer && in_active_region;

    // Pipeline register to match test pattern timing
    logic        fb_de_r;
    logic        fb_hsync_r;
    logic        fb_vsync_r;
    logic        fb_in_active_r;  // Track if we're in the active framebuffer region

    always_ff @(posedge pixel_clk or negedge rst_pixel_n) begin
        if (!rst_pixel_n) begin
            fb_de_r <= 1'b0;
            fb_hsync_r <= 1'b1;
            fb_vsync_r <= 1'b1;
            fb_in_active_r <= 1'b0;
        end else begin
            fb_de_r <= timing_de;
            fb_hsync_r <= timing_hsync;
            fb_vsync_r <= timing_vsync;
            fb_in_active_r <= in_active_region;
        end
    end

    // Select between test pattern and framebuffer
    // When in framebuffer mode but outside active region (y >= 448), output black
    always_comb begin
        if (use_framebuffer) begin
            if (fb_in_active_r && fb_read_valid) begin
                selected_rgb = fb_read_data;
            end else begin
                selected_rgb = 16'h0000;  // Black for inactive region
            end
            selected_de = fb_de_r;
        end else begin
            selected_rgb = pattern_rgb;
            selected_de = pattern_de;
        end
    end

    // Sync signals follow same pipeline as DE
    always_ff @(posedge pixel_clk or negedge rst_pixel_n) begin
        if (!rst_pixel_n) begin
            selected_hsync <= 1'b1;
            selected_vsync <= 1'b1;
        end else begin
            selected_hsync <= timing_hsync;
            selected_vsync <= timing_vsync;
        end
    end

    // =========================================================================
    // RGB to YCbCr Converter
    // =========================================================================

    rgb_to_ycbcr u_rgb_to_ycbcr (
        .pixel_clk    (pixel_clk),
        .rst_n        (rst_pixel_n),
        .rgb565_in    (selected_rgb),
        .de_in        (selected_de),
        .hsync_in     (selected_hsync),
        .vsync_in     (selected_vsync),
        .ycbcr_out    (ycbcr_data),
        .de_out       (ycbcr_de),
        .hsync_out    (ycbcr_hsync),
        .vsync_out    (ycbcr_vsync)
    );

    // =========================================================================
    // HDMI Output Registers
    // =========================================================================

    // Register outputs for timing closure
    always_ff @(posedge pixel_clk or negedge rst_pixel_n) begin
        if (!rst_pixel_n) begin
            hdmi_d     <= 16'h8010;  // Black in YCbCr
            hdmi_de    <= 1'b0;
            hdmi_hsync <= 1'b1;
            hdmi_vsync <= 1'b1;
        end else begin
            hdmi_d     <= ycbcr_data;
            hdmi_de    <= ycbcr_de;
            hdmi_hsync <= ycbcr_hsync;
            hdmi_vsync <= ycbcr_vsync;
        end
    end

    // Pixel clock output (directly from MMCM, or buffered)
    assign hdmi_clk = pixel_clk;

    // =========================================================================
    // ADV7511 I2C Initialization
    // =========================================================================

    // Start initialization after a brief startup delay
    // No need to wait for pixel_clk_locked since we use parent MMCM
    logic init_start;
    logic init_started;
    logic [15:0] init_delay;

    always_ff @(posedge clk_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            init_start <= 1'b0;
            init_started <= 1'b0;
            init_delay <= '0;
        end else begin
            init_start <= 1'b0;
            if (!init_started) begin
                if (init_delay == 16'hFFFF) begin
                    init_start <= 1'b1;
                    init_started <= 1'b1;
                end else begin
                    init_delay <= init_delay + 1'b1;
                end
            end
        end
    end

    adv7511_init u_adv7511_init (
        .clk            (clk_50mhz),
        .rst_n          (rst_n),
        .start          (init_start),
        .done           (hdmi_init_done),
        .error          (hdmi_init_error),
        .i2c_slave_addr (i2c_slave_addr),
        .i2c_reg_addr   (i2c_reg_addr),
        .i2c_write_data (i2c_write_data),
        .i2c_write_req  (i2c_write_req),
        .i2c_single_byte(i2c_single_byte),
        .i2c_busy       (i2c_busy),
        .i2c_done       (i2c_done),
        .i2c_ack_error  (i2c_ack_error)
    );

    i2c_master #(
        .CLK_DIV (125)  // 50 MHz / 125 / 4 = 100 kHz
    ) u_i2c_master (
        .clk            (clk_50mhz),
        .rst_n          (rst_n),
        .slave_addr     (i2c_slave_addr),
        .reg_addr       (i2c_reg_addr),
        .write_data     (i2c_write_data),
        .write_req      (i2c_write_req),
        .single_byte    (i2c_single_byte),
        .busy           (i2c_busy),
        .done           (i2c_done),
        .ack_error      (i2c_ack_error),
        .scl_o          (i2c_scl_o),
        .scl_oen        (i2c_scl_oen),
        .scl_i          (i2c_scl_i),
        .sda_o          (i2c_sda_o),
        .sda_oen        (i2c_sda_oen),
        .sda_i          (i2c_sda_i)
    );

endmodule
