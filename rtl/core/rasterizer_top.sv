// Celery3D GPU - Rasterizer Top Level
// Combines triangle setup, rasterizer core, perspective correction, and texture mapping
// Pipeline: vertices → setup → rasterize → perspective correct → texture → fragments

module rasterizer_top
    import celery_pkg::*;
#(
    parameter TEX_WIDTH_LOG2  = 6,  // 64 texels
    parameter TEX_HEIGHT_LOG2 = 6,
    parameter TEX_ADDR_BITS   = TEX_WIDTH_LOG2 + TEX_HEIGHT_LOG2,
    parameter DB_WIDTH_LOG2   = 7,  // 128 pixels (depth buffer)
    parameter DB_HEIGHT_LOG2  = 7
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
    logic tex_frag_valid;
    logic tex_frag_ready;

    // Depth buffer to output interface
    fragment_t db_frag;
    rgb565_t db_color;
    logic db_frag_valid;

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
        .clk            (clk),
        .rst_n          (rst_n),
        .tex_enable     (tex_enable),
        .modulate_enable(modulate_enable),
        .filter_bilinear(tex_filter_bilinear),
        .frag_in        (pc_frag),
        .frag_in_valid  (pc_frag_valid),
        .frag_in_ready  (pc_frag_ready),
        .frag_out       (tex_frag),
        .color_out      (tex_color),
        .frag_out_valid (tex_frag_valid),
        .frag_out_ready (tex_frag_ready),
        .tex_wr_addr    (tex_wr_addr),
        .tex_wr_data    (tex_wr_data),
        .tex_wr_en      (tex_wr_en)
    );

    // Depth buffer unit (3-stage pipeline)
    depth_buffer #(
        .DB_WIDTH_LOG2 (DB_WIDTH_LOG2),
        .DB_HEIGHT_LOG2(DB_HEIGHT_LOG2)
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
        .frag_in_valid     (tex_frag_valid),
        .frag_in_ready     (tex_frag_ready),
        .frag_out          (db_frag),
        .color_out         (db_color),
        .frag_out_valid    (db_frag_valid),
        .frag_out_ready    (frag_ready)
    );

    // Output from depth buffer
    assign frag_out = db_frag;
    assign color_out = db_color;
    assign frag_valid = db_frag_valid;

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
