// Celery3D GPU - Rasterizer Top Level
// Combines triangle setup, rasterizer core, perspective correction, and texture mapping
// Pipeline: vertices → setup → rasterize → perspective correct → texture → fragments

module rasterizer_top
    import celery_pkg::*;
#(
    parameter TEX_WIDTH_LOG2  = 6,  // 64 texels
    parameter TEX_HEIGHT_LOG2 = 6,
    parameter TEX_ADDR_BITS   = TEX_WIDTH_LOG2 + TEX_HEIGHT_LOG2,
    // Reduced resolution for synthesis testing (fits in BRAM)
    // Full 640x480 requires DDR3 framebuffer
    parameter DB_WIDTH        = 64,
    parameter DB_HEIGHT       = 64,
    parameter FB_WIDTH        = 64,
    parameter FB_HEIGHT       = 64
)(
    input  logic        clk,
    input  logic        rst_n,

    // Vertex input interface
    input  vertex_t     v0, v1, v2,
    input  logic        tri_valid,
    output logic        tri_ready,

    // Fragment output interface (perspective-corrected and textured)
    output fragment_t   frag_out,
    output rgb565_t     color_out,       // Final RGB565 color
    output logic        frag_valid,
    input  logic        frag_ready,

    // Texture configuration
    input  logic        tex_enable,
    input  logic        modulate_enable,
    input  logic        tex_filter_bilinear,  // 0=nearest, 1=bilinear
    input  logic        tex_format_rgba4444,  // 0=RGB565, 1=RGBA4444

    // Texture memory write interface
    input  logic [TEX_ADDR_BITS-1:0] tex_wr_addr,
    input  rgb565_t                  tex_wr_data,
    input  logic                     tex_wr_en,

    // Depth buffer configuration
    input  logic        depth_test_enable,
    input  logic        depth_write_enable,
    input  depth_func_t depth_func,
    input  logic        depth_clear,
    input  logic [15:0] depth_clear_value,
    output logic        depth_clearing,

    // Alpha blend configuration
    input  logic          blend_enable,
    input  blend_factor_t blend_src_factor,
    input  blend_factor_t blend_dst_factor,
    input  alpha_source_t blend_alpha_source,
    input  alpha_t        blend_constant_alpha,

    // Framebuffer configuration
    input  logic        fb_clear,
    input  rgb565_t     fb_clear_color,
    output logic        fb_clearing,

    // Framebuffer read interface (for video output)
    input  logic [$clog2(FB_WIDTH)-1:0]  fb_read_x,
    input  logic [$clog2(FB_HEIGHT)-1:0] fb_read_y,
    input  logic                          fb_read_en,
    output rgb565_t                       fb_read_data,
    output logic                          fb_read_valid,

    // Status
    output logic        busy
);

    // Internal signals
    triangle_setup_t setup;
    logic setup_done;
    logic setup_busy;
    logic rast_start;
    logic rast_done;
    logic rast_busy;

    // Rasterizer to perspective correction interface
    fragment_t rast_frag;
    fp32_t rast_w;
    logic rast_frag_valid;
    logic rast_frag_ready;

    // Perspective correction to texture unit interface
    fragment_t pc_frag;
    logic pc_frag_valid;
    logic pc_frag_ready;

    // Texture unit to depth buffer interface
    fragment_t tex_frag;
    rgb565_t tex_color;
    alpha_t tex_alpha;
    logic tex_frag_valid;
    logic tex_frag_ready;

    // Depth buffer to alpha blend interface
    fragment_t db_frag;
    rgb565_t db_color;
    alpha_t db_alpha;
    logic db_frag_valid;
    logic db_frag_ready;

    // Alpha blend to framebuffer interface
    fragment_t ab_frag;
    rgb565_t ab_color;
    logic ab_frag_valid;
    logic ab_frag_ready;

    // Framebuffer blend read interface
    logic [$clog2(FB_WIDTH)-1:0]  fb_blend_read_x;
    logic [$clog2(FB_HEIGHT)-1:0] fb_blend_read_y;
    logic                          fb_blend_read_en;
    rgb565_t                       fb_blend_read_data;
    logic                          fb_blend_read_valid;

    // State for coordinating setup and rasterizer
    typedef enum logic [1:0] {
        IDLE,
        SETUP,
        RASTERIZE
    } state_t;

    state_t state;

    // Triangle setup unit
    triangle_setup u_setup (
        .clk        (clk),
        .rst_n      (rst_n),
        .v0         (v0),
        .v1         (v1),
        .v2         (v2),
        .start      (tri_valid && state == IDLE),
        .setup      (setup),
        .done       (setup_done),
        .busy       (setup_busy)
    );

    // Rasterizer core
    rasterizer u_rast (
        .clk        (clk),
        .rst_n      (rst_n),
        .tri_in     (setup),
        .start      (rast_start),
        .frag_out   (rast_frag),
        .w_out      (rast_w),
        .frag_valid (rast_frag_valid),
        .frag_ready (rast_frag_ready),
        .done       (rast_done),
        .busy       (rast_busy)
    );

    // Perspective correction unit (8-stage pipeline)
    // BYPASS=0 enables perspective correction, BYPASS=1 for debugging
    perspective_correct #(.BYPASS(0)) u_persp (
        .clk            (clk),
        .rst_n          (rst_n),
        .frag_in        (rast_frag),
        .frag_in_valid  (rast_frag_valid),
        .frag_in_ready  (rast_frag_ready),
        .w_in           (rast_w),
        .frag_out       (pc_frag),
        .frag_out_valid (pc_frag_valid),
        .frag_out_ready (pc_frag_ready)
    );

    // Texture mapping unit (5-stage pipeline with bilinear filtering)
    texture_unit #(
        .TEX_WIDTH_LOG2 (TEX_WIDTH_LOG2),
        .TEX_HEIGHT_LOG2(TEX_HEIGHT_LOG2)
    ) u_texture (
        .clk               (clk),
        .rst_n             (rst_n),
        .tex_enable        (tex_enable),
        .modulate_enable   (modulate_enable),
        .filter_bilinear   (tex_filter_bilinear),
        .tex_format_rgba4444(tex_format_rgba4444),
        .frag_in           (pc_frag),
        .frag_in_valid     (pc_frag_valid),
        .frag_in_ready     (pc_frag_ready),
        .frag_out          (tex_frag),
        .color_out         (tex_color),
        .tex_alpha_out     (tex_alpha),
        .frag_out_valid    (tex_frag_valid),
        .frag_out_ready    (tex_frag_ready),
        .tex_wr_addr       (tex_wr_addr),
        .tex_wr_data       (tex_wr_data),
        .tex_wr_en         (tex_wr_en)
    );

    // Depth buffer unit (3-stage pipeline)
    depth_buffer #(
        .DB_WIDTH (DB_WIDTH),
        .DB_HEIGHT(DB_HEIGHT)
    ) u_depth_buffer (
        .clk               (clk),
        .rst_n             (rst_n),
        .depth_test_enable (depth_test_enable),
        .depth_write_enable(depth_write_enable),
        .depth_func        (depth_func),
        .depth_clear       (depth_clear),
        .depth_clear_value (depth_clear_value),
        .depth_clearing    (depth_clearing),
        .frag_in           (tex_frag),
        .color_in          (tex_color),
        .tex_alpha_in      (tex_alpha),
        .frag_in_valid     (tex_frag_valid),
        .frag_in_ready     (tex_frag_ready),
        .frag_out          (db_frag),
        .color_out         (db_color),
        .tex_alpha_out     (db_alpha),
        .frag_out_valid    (db_frag_valid),
        .frag_out_ready    (db_frag_ready)
    );

    // Alpha blending unit (4-stage pipeline)
    alpha_blend #(
        .FB_WIDTH (FB_WIDTH),
        .FB_HEIGHT(FB_HEIGHT)
    ) u_alpha_blend (
        .clk               (clk),
        .rst_n             (rst_n),
        .blend_enable      (blend_enable),
        .src_factor        (blend_src_factor),
        .dst_factor        (blend_dst_factor),
        .alpha_source      (blend_alpha_source),
        .constant_alpha    (blend_constant_alpha),
        .frag_in           (db_frag),
        .color_in          (db_color),
        .tex_alpha_in      (db_alpha),
        .frag_in_valid     (db_frag_valid),
        .frag_in_ready     (db_frag_ready),
        .frag_out          (ab_frag),
        .color_out         (ab_color),
        .frag_out_valid    (ab_frag_valid),
        .frag_out_ready    (ab_frag_ready),
        .blend_read_x      (fb_blend_read_x),
        .blend_read_y      (fb_blend_read_y),
        .blend_read_en     (fb_blend_read_en),
        .blend_read_data   (fb_blend_read_data),
        .blend_read_valid  (fb_blend_read_valid)
    );

    // Framebuffer (stores rendered pixels)
    logic fb_busy;
    framebuffer #(
        .FB_WIDTH (FB_WIDTH),
        .FB_HEIGHT(FB_HEIGHT)
    ) u_framebuffer (
        .clk             (clk),
        .rst_n           (rst_n),
        .frag_in         (ab_frag),
        .color_in        (ab_color),
        .frag_in_valid   (ab_frag_valid),
        .frag_in_ready   (ab_frag_ready),
        .read_x          (fb_read_x),
        .read_y          (fb_read_y),
        .read_en         (fb_read_en),
        .read_data       (fb_read_data),
        .read_valid      (fb_read_valid),
        .blend_read_x    (fb_blend_read_x),
        .blend_read_y    (fb_blend_read_y),
        .blend_read_en   (fb_blend_read_en),
        .blend_read_data (fb_blend_read_data),
        .blend_read_valid(fb_blend_read_valid),
        .clear           (fb_clear),
        .clear_color     (fb_clear_color),
        .clearing        (fb_clearing),
        .busy            (fb_busy)
    );

    // Output fragment info (for testbench visibility - shows post-blending)
    assign frag_out = ab_frag;
    assign color_out = ab_color;
    assign frag_valid = ab_frag_valid;

    // State machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            rast_start <= 1'b0;
        end else begin
            rast_start <= 1'b0;

            case (state)
                IDLE: begin
                    if (tri_valid) begin
                        state <= SETUP;
                    end
                end

                SETUP: begin
                    if (setup_done) begin
                        if (setup.valid) begin
                            rast_start <= 1'b1;
                            state <= RASTERIZE;
                        end else begin
                            // Degenerate triangle, skip
                            state <= IDLE;
                        end
                    end
                end

                RASTERIZE: begin
                    if (rast_done) begin
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

    assign tri_ready = (state == IDLE);
    assign busy = (state != IDLE);

endmodule
