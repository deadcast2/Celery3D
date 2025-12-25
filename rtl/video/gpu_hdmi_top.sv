// Celery3D GPU - Integrated GPU + HDMI Top Level
// Combines rasterization pipeline with HDMI output
// UART command interface for triangle submission from host

module gpu_hdmi_top
    import celery_pkg::*;
#(
    parameter FB_WIDTH  = 64,
    parameter FB_HEIGHT = 64
)(
    // Clocks
    input  logic        clk_50mhz,    // System clock (rasterizer, I2C)
    input  logic        clk_25mhz,    // Pixel clock (video timing)
    input  logic        rst_n,        // Active-low reset

    // UART input
    input  logic        uart_rx,      // UART receive pin (directly from FPGA GPIO or USB-UART)

    // HDMI output pins (directly to ADV7511)
    output logic [15:0] hdmi_d,
    output logic        hdmi_clk,
    output logic        hdmi_de,
    output logic        hdmi_hsync,
    output logic        hdmi_vsync,

    // I2C for ADV7511 configuration
    output logic        i2c_scl_o,
    output logic        i2c_scl_oen,
    input  logic        i2c_scl_i,
    output logic        i2c_sda_o,
    output logic        i2c_sda_oen,
    input  logic        i2c_sda_i,

    // Status outputs
    output logic        hdmi_init_done,
    output logic        hdmi_init_error,
    output logic        rast_busy,        // Rasterizer busy status
    output logic        uart_byte_valid   // Pulses when UART byte received (debug)
);

    // =========================================================================
    // Internal Signals
    // =========================================================================

    // UART signals
    logic [7:0] uart_data;
    logic uart_valid;

    // Rasterizer control (from cmd_parser)
    vertex_t v0, v1, v2;
    logic tri_valid;
    logic tri_ready;
    logic rast_busy_int;

    // Framebuffer control
    logic fb_clear;
    rgb565_t fb_clear_color;
    logic fb_clearing;

    // Depth buffer control
    logic depth_clear;
    logic depth_clearing;

    // Render configuration (from cmd_parser)
    logic tex_enable;
    logic depth_test_enable;
    logic depth_write_enable;
    logic blend_enable;

    // Framebuffer read interface (from HDMI, on video_clk domain)
    logic [$clog2(FB_WIDTH)-1:0]  fb_read_x;
    logic [$clog2(FB_HEIGHT)-1:0] fb_read_y;
    logic fb_read_en;
    rgb565_t fb_read_data;
    logic fb_read_valid;

    // Fragment output (unused - just for visibility)
    fragment_t frag_out;
    rgb565_t color_out;
    logic frag_valid;

    // Export busy status
    assign rast_busy = rast_busy_int;

    // Export UART valid for debug LED
    assign uart_byte_valid = uart_valid;

    // Pixel clock domain reset
    logic rst_pixel_n;
    logic [2:0] rst_pixel_sync;

    always_ff @(posedge clk_25mhz or negedge rst_n) begin
        if (!rst_n) begin
            rst_pixel_sync <= 3'b000;
        end else begin
            rst_pixel_sync <= {rst_pixel_sync[1:0], 1'b1};
        end
    end
    assign rst_pixel_n = rst_pixel_sync[2];

    // =========================================================================
    // Rasterizer Pipeline
    // =========================================================================

    rasterizer_top #(
        .FB_WIDTH  (FB_WIDTH),
        .FB_HEIGHT (FB_HEIGHT),
        .DB_WIDTH  (FB_WIDTH),
        .DB_HEIGHT (FB_HEIGHT)
    ) u_rasterizer (
        .clk               (clk_50mhz),
        .rst_n             (rst_n),

        // Vertex input (from cmd_parser)
        .v0                (v0),
        .v1                (v1),
        .v2                (v2),
        .tri_valid         (tri_valid),
        .tri_ready         (tri_ready),

        // Fragment output (unused externally)
        .frag_out          (frag_out),
        .color_out         (color_out),
        .frag_valid        (frag_valid),
        .frag_ready        (1'b1),  // Always accept

        // Texture config (controlled via cmd_parser)
        .tex_enable        (tex_enable),
        .modulate_enable   (tex_enable),       // Modulate when texturing
        .tex_filter_bilinear(1'b1),            // Always use bilinear
        .tex_format_rgba4444(1'b0),            // RGB565 format
        .tex_wr_addr       ('0),
        .tex_wr_data       ('0),
        .tex_wr_en         (1'b0),

        // Depth buffer config (controlled via cmd_parser)
        .depth_test_enable (depth_test_enable),
        .depth_write_enable(depth_write_enable),
        .depth_func        (GR_CMP_LESS),      // Standard depth test
        .depth_clear       (depth_clear),
        .depth_clear_value (16'hFFFF),         // Clear to far plane
        .depth_clearing    (depth_clearing),

        // Alpha blend config (controlled via cmd_parser)
        .blend_enable      (blend_enable),
        .blend_src_factor  (GR_BLEND_SRC_ALPHA),
        .blend_dst_factor  (GR_BLEND_ONE_MINUS_SRC_ALPHA),
        .blend_alpha_source(ALPHA_SRC_TEXTURE),
        .blend_constant_alpha(8'hFF),

        // Framebuffer control (from cmd_parser)
        .fb_clear          (fb_clear),
        .fb_clear_color    (fb_clear_color),
        .fb_clearing       (fb_clearing),

        // Framebuffer read (for video output, on video_clk domain)
        .video_clk         (clk_25mhz),
        .video_rst_n       (rst_pixel_n),
        .fb_read_x         (fb_read_x),
        .fb_read_y         (fb_read_y),
        .fb_read_en        (fb_read_en),
        .fb_read_data      (fb_read_data),
        .fb_read_valid     (fb_read_valid),

        // Status
        .busy              (rast_busy_int)
    );

    // =========================================================================
    // HDMI Output
    // =========================================================================

    hdmi_top #(
        .FB_WIDTH  (FB_WIDTH),
        .FB_HEIGHT (FB_HEIGHT)
    ) u_hdmi (
        .clk_50mhz      (clk_50mhz),
        .clk_25mhz      (clk_25mhz),
        .rst_n          (rst_n),

        // HDMI outputs
        .hdmi_d         (hdmi_d),
        .hdmi_clk       (hdmi_clk),
        .hdmi_de        (hdmi_de),
        .hdmi_hsync     (hdmi_hsync),
        .hdmi_vsync     (hdmi_vsync),

        // I2C
        .i2c_scl_o      (i2c_scl_o),
        .i2c_scl_oen    (i2c_scl_oen),
        .i2c_scl_i      (i2c_scl_i),
        .i2c_sda_o      (i2c_sda_o),
        .i2c_sda_oen    (i2c_sda_oen),
        .i2c_sda_i      (i2c_sda_i),

        // Framebuffer interface
        .fb_read_x      (fb_read_x),
        .fb_read_y      (fb_read_y),
        .fb_read_en     (fb_read_en),
        .fb_read_data   (fb_read_data),
        .fb_read_valid  (fb_read_valid),

        // Control - use framebuffer mode
        .pattern_sel    (2'b00),
        .use_framebuffer(1'b1),

        // Status
        .hdmi_init_done (hdmi_init_done),
        .hdmi_init_error(hdmi_init_error)
    );

    // =========================================================================
    // UART Receiver
    // =========================================================================

    uart_rx #(
        .CLK_FREQ  (50_000_000),
        .BAUD_RATE (115200)
    ) u_uart_rx (
        .clk   (clk_50mhz),
        .rst_n (rst_n),
        .rx    (uart_rx),
        .data  (uart_data),
        .valid (uart_valid)
    );

    // =========================================================================
    // Command Parser
    // =========================================================================

    cmd_parser u_cmd_parser (
        .clk               (clk_50mhz),
        .rst_n             (rst_n),

        // UART interface
        .uart_data         (uart_data),
        .uart_valid        (uart_valid),

        // Triangle output (to rasterizer)
        .v0                (v0),
        .v1                (v1),
        .v2                (v2),
        .tri_valid         (tri_valid),
        .tri_ready         (tri_ready),

        // Framebuffer control
        .fb_clear          (fb_clear),
        .fb_clear_color    (fb_clear_color),
        .fb_clearing       (fb_clearing),

        // Depth buffer control
        .depth_clear       (depth_clear),
        .depth_clearing    (depth_clearing),

        // Render configuration
        .tex_enable        (tex_enable),
        .depth_test_enable (depth_test_enable),
        .depth_write_enable(depth_write_enable),
        .blend_enable      (blend_enable)
    );

endmodule
