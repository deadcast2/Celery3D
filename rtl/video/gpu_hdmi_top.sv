// Celery3D GPU - Integrated GPU + HDMI Top Level
// Combines rasterization pipeline with HDMI output
// Includes startup controller to render a test triangle on power-up

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
    output logic        render_done       // Triangle rendering complete
);

    // =========================================================================
    // Internal Signals
    // =========================================================================

    // Rasterizer control
    vertex_t v0, v1, v2;
    logic tri_valid;
    logic tri_ready;
    logic rast_busy;

    // Framebuffer control
    logic fb_clear;
    rgb565_t fb_clear_color;
    logic fb_clearing;

    // Framebuffer read interface (from HDMI, on video_clk domain)
    logic [$clog2(FB_WIDTH)-1:0]  fb_read_x;
    logic [$clog2(FB_HEIGHT)-1:0] fb_read_y;
    logic fb_read_en;
    rgb565_t fb_read_data;
    logic fb_read_valid;

    // Depth buffer control (not used for simple test, but need to tie off)
    logic depth_clearing;

    // Fragment output (unused - just for visibility)
    fragment_t frag_out;
    rgb565_t color_out;
    logic frag_valid;

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

        // Vertex input
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

        // Texture config (disabled for simple test)
        .tex_enable        (1'b0),
        .modulate_enable   (1'b0),
        .tex_filter_bilinear(1'b0),
        .tex_format_rgba4444(1'b0),
        .tex_wr_addr       ('0),
        .tex_wr_data       ('0),
        .tex_wr_en         (1'b0),

        // Depth buffer config (disabled for simple test)
        .depth_test_enable (1'b0),
        .depth_write_enable(1'b0),
        .depth_func        (GR_CMP_ALWAYS),
        .depth_clear       (1'b0),
        .depth_clear_value (16'hFFFF),
        .depth_clearing    (depth_clearing),

        // Alpha blend config (disabled for simple test)
        .blend_enable      (1'b0),
        .blend_src_factor  (GR_BLEND_ONE),
        .blend_dst_factor  (GR_BLEND_ZERO),
        .blend_alpha_source(ALPHA_SRC_ONE),
        .blend_constant_alpha(8'hFF),

        // Framebuffer control
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
        .busy              (rast_busy)
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
    // Startup Controller - Renders test triangle on power-up
    // =========================================================================

    typedef enum logic [2:0] {
        ST_WAIT_INIT,    // Wait for HDMI init complete
        ST_CLEAR_FB,     // Start framebuffer clear
        ST_WAIT_CLEAR,   // Wait for clear to complete
        ST_RENDER_TRI,   // Submit triangle vertices
        ST_WAIT_RENDER,  // Wait for rasterizer to complete
        ST_DONE          // Display continuously
    } startup_state_t;

    startup_state_t state;
    logic [15:0] init_delay;

    // Define test triangle vertices (Gouraud-shaded RGB)
    // Triangle covers most of the 64x64 framebuffer
    // v0: top center (red), v1: bottom left (green), v2: bottom right (blue)

    function automatic vertex_t make_vertex(
        input int x, input int y,
        input int r, input int g, input int b
    );
        vertex_t v;
        v.x = int_to_fp(x);
        v.y = int_to_fp(y);
        v.z = FP_HALF;           // Middle depth
        v.w = FP_ONE;            // No perspective (w=1)
        v.u = FP_ZERO;           // No texture
        v.v = FP_ZERO;
        v.r = r == 255 ? FP_ONE : (r == 0 ? FP_ZERO : int_to_fp(r) >>> 8);
        v.g = g == 255 ? FP_ONE : (g == 0 ? FP_ZERO : int_to_fp(g) >>> 8);
        v.b = b == 255 ? FP_ONE : (b == 0 ? FP_ZERO : int_to_fp(b) >>> 8);
        v.a = FP_ONE;            // Fully opaque
        return v;
    endfunction

    always_ff @(posedge clk_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_WAIT_INIT;
            init_delay <= '0;
            tri_valid <= 1'b0;
            fb_clear <= 1'b0;
            fb_clear_color <= 16'h001F;  // Blue background (RGB565)
            render_done <= 1'b0;

            // Initialize vertices (will be set properly in state machine)
            v0 <= '0;
            v1 <= '0;
            v2 <= '0;

        end else begin
            // Default: deassert one-shot signals
            tri_valid <= 1'b0;
            fb_clear <= 1'b0;

            case (state)
                ST_WAIT_INIT: begin
                    // Wait for HDMI init and a brief delay
                    if (hdmi_init_done && !hdmi_init_error) begin
                        if (init_delay == 16'hFFFF) begin
                            state <= ST_CLEAR_FB;
                        end else begin
                            init_delay <= init_delay + 1'b1;
                        end
                    end
                end

                ST_CLEAR_FB: begin
                    // Start framebuffer clear to blue
                    fb_clear <= 1'b1;
                    state <= ST_WAIT_CLEAR;
                end

                ST_WAIT_CLEAR: begin
                    // Wait for clear to complete
                    if (!fb_clearing) begin
                        state <= ST_RENDER_TRI;
                    end
                end

                ST_RENDER_TRI: begin
                    // Set up triangle vertices and submit
                    // v0: top center (RED)
                    v0 <= make_vertex(32, 5, 255, 0, 0);
                    // v1: bottom left (GREEN)
                    v1 <= make_vertex(5, 58, 0, 255, 0);
                    // v2: bottom right (BLUE)
                    v2 <= make_vertex(58, 58, 0, 0, 255);

                    if (tri_ready) begin
                        tri_valid <= 1'b1;
                        state <= ST_WAIT_RENDER;
                    end
                end

                ST_WAIT_RENDER: begin
                    // Wait for rasterizer to finish
                    if (!rast_busy && tri_ready) begin
                        state <= ST_DONE;
                        render_done <= 1'b1;
                    end
                end

                ST_DONE: begin
                    // Triangle rendered, display continuously
                    render_done <= 1'b1;
                end
            endcase
        end
    end

endmodule
