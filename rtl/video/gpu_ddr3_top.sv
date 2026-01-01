// Celery3D GPU - DDR3 Framebuffer Top Level for KC705
// Full GPU pipeline with DDR3 framebuffer and HDMI output
//
// Architecture:
//   UART → cmd_parser → rasterizer_top → pixel_fifo → pixel_write_master → DDR3
//                                                                            ↓
//                                              HDMI ← line_buffer ← DDR3 ←───┘

module gpu_ddr3_top (
    // 200 MHz differential system clock (to MIG)
    input  logic        sys_clk_p,
    input  logic        sys_clk_n,

    // System reset button (active-low from KC705 SW4 South)
    input  logic        sys_rst_n,

    // DDR3 SDRAM interface
    inout  [63:0]       ddr3_dq,
    inout  [7:0]        ddr3_dqs_n,
    inout  [7:0]        ddr3_dqs_p,
    output [13:0]       ddr3_addr,
    output [2:0]        ddr3_ba,
    output              ddr3_ras_n,
    output              ddr3_cas_n,
    output              ddr3_we_n,
    output              ddr3_reset_n,
    output [0:0]        ddr3_ck_p,
    output [0:0]        ddr3_ck_n,
    output [0:0]        ddr3_cke,
    output [0:0]        ddr3_cs_n,
    output [7:0]        ddr3_dm,
    output [0:0]        ddr3_odt,

    // UART interface
    input  logic        uart_rxd,

    // HDMI output pins (directly to ADV7511)
    output logic [15:0] hdmi_d,
    output logic        hdmi_clk,
    output logic        hdmi_de,
    output logic        hdmi_hsync,
    output logic        hdmi_vsync,

    // I2C bidirectional pins (for ADV7511)
    inout  wire         i2c_scl,
    inout  wire         i2c_sda,
    output logic        i2c_mux_reset_n,

    // Status LEDs
    output logic [7:0]  gpio_led
);

    import video_pkg::*;
    import celery_pkg::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam FB_WIDTH = 640;
    localparam FB_HEIGHT = 480;
    localparam FB_BASE_ADDR = 30'h0000_0000;

    // =========================================================================
    // MIG Signals
    // =========================================================================
    logic        ui_clk;
    logic        ui_clk_sync_rst;
    logic        mmcm_locked;
    logic        init_calib_complete;
    logic [11:0] device_temp;

    // AXI4 Write Address Channel
    logic [3:0]   s_axi_awid;
    logic [29:0]  s_axi_awaddr;
    logic [7:0]   s_axi_awlen;
    logic [2:0]   s_axi_awsize;
    logic [1:0]   s_axi_awburst;
    logic [0:0]   s_axi_awlock;
    logic [3:0]   s_axi_awcache;
    logic [2:0]   s_axi_awprot;
    logic [3:0]   s_axi_awqos;
    logic         s_axi_awvalid;
    logic         s_axi_awready;

    // AXI4 Write Data Channel
    logic [255:0] s_axi_wdata;
    logic [31:0]  s_axi_wstrb;
    logic         s_axi_wlast;
    logic         s_axi_wvalid;
    logic         s_axi_wready;

    // AXI4 Write Response Channel
    logic [3:0]   s_axi_bid;
    logic [1:0]   s_axi_bresp;
    logic         s_axi_bvalid;
    logic         s_axi_bready;

    // AXI4 Read Address Channel
    logic [3:0]   s_axi_arid;
    logic [29:0]  s_axi_araddr;
    logic [7:0]   s_axi_arlen;
    logic [2:0]   s_axi_arsize;
    logic [1:0]   s_axi_arburst;
    logic [0:0]   s_axi_arlock;
    logic [3:0]   s_axi_arcache;
    logic [2:0]   s_axi_arprot;
    logic [3:0]   s_axi_arqos;
    logic         s_axi_arvalid;
    logic         s_axi_arready;

    // AXI4 Read Data Channel
    logic [3:0]   s_axi_rid;
    logic [255:0] s_axi_rdata;
    logic [1:0]   s_axi_rresp;
    logic         s_axi_rlast;
    logic         s_axi_rvalid;
    logic         s_axi_rready;

    // =========================================================================
    // MIG Instantiation
    // =========================================================================
    mig_7series_0 u_mig (
        // DDR3 interface
        .ddr3_dq            (ddr3_dq),
        .ddr3_dqs_n         (ddr3_dqs_n),
        .ddr3_dqs_p         (ddr3_dqs_p),
        .ddr3_addr          (ddr3_addr),
        .ddr3_ba            (ddr3_ba),
        .ddr3_ras_n         (ddr3_ras_n),
        .ddr3_cas_n         (ddr3_cas_n),
        .ddr3_we_n          (ddr3_we_n),
        .ddr3_reset_n       (ddr3_reset_n),
        .ddr3_ck_p          (ddr3_ck_p),
        .ddr3_ck_n          (ddr3_ck_n),
        .ddr3_cke           (ddr3_cke),
        .ddr3_cs_n          (ddr3_cs_n),
        .ddr3_dm            (ddr3_dm),
        .ddr3_odt           (ddr3_odt),

        // System clock
        .sys_clk_p          (sys_clk_p),
        .sys_clk_n          (sys_clk_n),

        // User interface clock and reset
        .ui_clk             (ui_clk),
        .ui_clk_sync_rst    (ui_clk_sync_rst),
        .mmcm_locked        (mmcm_locked),

        // Reset and calibration
        .aresetn            (~ui_clk_sync_rst),
        .sys_rst            (~sys_rst_n),
        .init_calib_complete(init_calib_complete),
        .device_temp        (device_temp),

        // Self-refresh, refresh, ZQ calibration requests (unused)
        .app_sr_req         (1'b0),
        .app_ref_req        (1'b0),
        .app_zq_req         (1'b0),
        .app_sr_active      (),
        .app_ref_ack        (),
        .app_zq_ack         (),

        // AXI4 Write Address Channel
        .s_axi_awid         (s_axi_awid),
        .s_axi_awaddr       (s_axi_awaddr),
        .s_axi_awlen        (s_axi_awlen),
        .s_axi_awsize       (s_axi_awsize),
        .s_axi_awburst      (s_axi_awburst),
        .s_axi_awlock       (s_axi_awlock),
        .s_axi_awcache      (s_axi_awcache),
        .s_axi_awprot       (s_axi_awprot),
        .s_axi_awqos        (s_axi_awqos),
        .s_axi_awvalid      (s_axi_awvalid),
        .s_axi_awready      (s_axi_awready),

        // AXI4 Write Data Channel
        .s_axi_wdata        (s_axi_wdata),
        .s_axi_wstrb        (s_axi_wstrb),
        .s_axi_wlast        (s_axi_wlast),
        .s_axi_wvalid       (s_axi_wvalid),
        .s_axi_wready       (s_axi_wready),

        // AXI4 Write Response Channel
        .s_axi_bid          (s_axi_bid),
        .s_axi_bresp        (s_axi_bresp),
        .s_axi_bvalid       (s_axi_bvalid),
        .s_axi_bready       (s_axi_bready),

        // AXI4 Read Address Channel
        .s_axi_arid         (s_axi_arid),
        .s_axi_araddr       (s_axi_araddr),
        .s_axi_arlen        (s_axi_arlen),
        .s_axi_arsize       (s_axi_arsize),
        .s_axi_arburst      (s_axi_arburst),
        .s_axi_arlock       (s_axi_arlock),
        .s_axi_arcache      (s_axi_arcache),
        .s_axi_arprot       (s_axi_arprot),
        .s_axi_arqos        (s_axi_arqos),
        .s_axi_arvalid      (s_axi_arvalid),
        .s_axi_arready      (s_axi_arready),

        // AXI4 Read Data Channel
        .s_axi_rid          (s_axi_rid),
        .s_axi_rdata        (s_axi_rdata),
        .s_axi_rresp        (s_axi_rresp),
        .s_axi_rlast        (s_axi_rlast),
        .s_axi_rvalid       (s_axi_rvalid),
        .s_axi_rready       (s_axi_rready)
    );

    // =========================================================================
    // Video Clock Generation (from MIG ui_clk)
    // =========================================================================
    logic clk_50mhz;
    logic clk_25mhz;
    logic video_clk_locked;

    video_clk_from_mig u_video_clk (
        .ui_clk     (ui_clk),
        .ui_rst     (ui_clk_sync_rst),
        .clk_50mhz  (clk_50mhz),
        .clk_25mhz  (clk_25mhz),
        .locked     (video_clk_locked)
    );

    // Combined reset for video domain
    logic video_rst_n;
    logic [7:0] video_rst_cnt;

    always_ff @(posedge clk_50mhz or negedge video_clk_locked) begin
        if (!video_clk_locked) begin
            video_rst_cnt <= '0;
            video_rst_n <= 1'b0;
        end else if (video_rst_cnt != 8'hFF) begin
            video_rst_cnt <= video_rst_cnt + 1'b1;
            video_rst_n <= 1'b0;
        end else begin
            video_rst_n <= 1'b1;
        end
    end

    // I2C mux reset (active low)
    assign i2c_mux_reset_n = video_rst_n;

    // =========================================================================
    // UART Receiver
    // =========================================================================
    logic [7:0] uart_data;
    logic uart_valid;

    uart_rx #(
        .CLK_FREQ  (50_000_000),
        .BAUD_RATE (115200)
    ) u_uart_rx (
        .clk   (clk_50mhz),
        .rst_n (video_rst_n),
        .rx    (uart_rxd),
        .data  (uart_data),
        .valid (uart_valid)
    );

    // =========================================================================
    // Command Parser
    // =========================================================================
    vertex_t v0, v1, v2;
    logic tri_valid;
    logic tri_ready;
    logic fb_clear_cmd;
    rgb565_t fb_clear_color;
    logic depth_clear_cmd;
    logic tex_enable;
    logic depth_test_enable;
    logic depth_write_enable;
    logic blend_enable;

    // Clearing status from rasterizer (unused for DDR3 clear, but needed for cmd_parser)
    logic fb_clearing_rast;
    logic depth_clearing;

    cmd_parser u_cmd_parser (
        .clk               (clk_50mhz),
        .rst_n             (video_rst_n),

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
        .fb_clear          (fb_clear_cmd),
        .fb_clear_color    (fb_clear_color),
        .fb_clearing       (fb_clearing_rast),

        // Depth buffer control
        .depth_clear       (depth_clear_cmd),
        .depth_clearing    (depth_clearing),

        // Render configuration
        .tex_enable        (tex_enable),
        .depth_test_enable (depth_test_enable),
        .depth_write_enable(depth_write_enable),
        .blend_enable      (blend_enable)
    );

    // =========================================================================
    // Rasterizer Pipeline
    // =========================================================================
    // Note: Internal framebuffer is kept small (64x64) but not used for display
    // Actual output goes through pixel_fifo to DDR3

    fragment_t frag_out;
    rgb565_t color_out;
    logic frag_valid;
    logic frag_ready;
    logic rast_busy;

    rasterizer_top #(
        .FB_WIDTH  (64),   // Small internal FB (not used for display)
        .FB_HEIGHT (64),
        .DB_WIDTH  (64),   // Depth buffer also small for synthesis
        .DB_HEIGHT (64)
    ) u_rasterizer (
        .clk               (clk_50mhz),
        .rst_n             (video_rst_n),

        // Vertex input (from cmd_parser)
        .v0                (v0),
        .v1                (v1),
        .v2                (v2),
        .tri_valid         (tri_valid),
        .tri_ready         (tri_ready),

        // Fragment output (to pixel_fifo)
        .frag_out          (frag_out),
        .color_out         (color_out),
        .frag_valid        (frag_valid),
        .frag_ready        (frag_ready),

        // Texture config
        .tex_enable        (tex_enable),
        .modulate_enable   (tex_enable),
        .tex_filter_bilinear(1'b1),
        .tex_format_rgba4444(1'b0),
        .tex_wr_addr       ('0),
        .tex_wr_data       ('0),
        .tex_wr_en         (1'b0),

        // Depth buffer config
        .depth_test_enable (depth_test_enable),
        .depth_write_enable(depth_write_enable),
        .depth_func        (GR_CMP_LESS),
        .depth_clear       (depth_clear_cmd),
        .depth_clear_value (16'hFFFF),
        .depth_clearing    (depth_clearing),

        // Alpha blend config - DISABLED for DDR3 (can't read destination)
        .blend_enable      (1'b0),  // Disable blending
        .blend_src_factor  (GR_BLEND_ONE),
        .blend_dst_factor  (GR_BLEND_ZERO),
        .blend_alpha_source(ALPHA_SRC_TEXTURE),
        .blend_constant_alpha(8'hFF),

        // Framebuffer control (internal FB, not DDR3)
        .fb_clear          (1'b0),  // Don't use internal FB clear
        .fb_clear_color    (16'h0000),
        .fb_clearing       (fb_clearing_rast),

        // Framebuffer read (unused - we read from DDR3)
        .video_clk         (clk_25mhz),
        .video_rst_n       (video_rst_n),
        .fb_read_x         ('0),
        .fb_read_y         ('0),
        .fb_read_en        (1'b0),
        .fb_read_data      (),
        .fb_read_valid     (),

        // Status
        .busy              (rast_busy)
    );

    // =========================================================================
    // Pixel FIFO (CDC: 50 MHz rasterizer -> ~100 MHz DDR)
    // =========================================================================
    logic [9:0] fifo_rd_x;
    logic [9:0] fifo_rd_y;
    logic [15:0] fifo_rd_color;
    logic fifo_rd_valid;
    logic fifo_rd_ready;
    logic [8:0] fifo_fill_level;

    pixel_fifo #(
        .DEPTH (256)
    ) u_pixel_fifo (
        // Write side (rasterizer clock)
        .wr_clk    (clk_50mhz),
        .wr_rst_n  (video_rst_n),
        .wr_x      (frag_out.x[9:0]),
        .wr_y      (frag_out.y[9:0]),
        .wr_color  (color_out),
        .wr_valid  (frag_valid),
        .wr_ready  (frag_ready),

        // Read side (DDR clock)
        .rd_clk    (ui_clk),
        .rd_rst_n  (~ui_clk_sync_rst),
        .rd_x      (fifo_rd_x),
        .rd_y      (fifo_rd_y),
        .rd_color  (fifo_rd_color),
        .rd_valid  (fifo_rd_valid),
        .rd_ready  (fifo_rd_ready),

        // Status
        .fill_level(fifo_fill_level)
    );

    // =========================================================================
    // Pixel Write Master
    // =========================================================================
    logic [3:0]   px_axi_awid;
    logic [29:0]  px_axi_awaddr;
    logic [7:0]   px_axi_awlen;
    logic [2:0]   px_axi_awsize;
    logic [1:0]   px_axi_awburst;
    logic [0:0]   px_axi_awlock;
    logic [3:0]   px_axi_awcache;
    logic [2:0]   px_axi_awprot;
    logic [3:0]   px_axi_awqos;
    logic         px_axi_awvalid;
    logic         px_axi_awready;
    logic [255:0] px_axi_wdata;
    logic [31:0]  px_axi_wstrb;
    logic         px_axi_wlast;
    logic         px_axi_wvalid;
    logic         px_axi_wready;
    logic         px_axi_bready;
    logic         px_busy;

    pixel_write_master #(
        .FB_WIDTH     (FB_WIDTH),
        .FB_HEIGHT    (FB_HEIGHT),
        .FB_BASE_ADDR (FB_BASE_ADDR)
    ) u_pixel_write (
        .clk           (ui_clk),
        .rst_n         (~ui_clk_sync_rst),

        // Pixel interface (from FIFO)
        .pixel_x       (fifo_rd_x),
        .pixel_y       (fifo_rd_y),
        .pixel_color   (fifo_rd_color),
        .pixel_valid   (fifo_rd_valid),
        .pixel_ready   (fifo_rd_ready),

        // AXI Write Address
        .m_axi_awid    (px_axi_awid),
        .m_axi_awaddr  (px_axi_awaddr),
        .m_axi_awlen   (px_axi_awlen),
        .m_axi_awsize  (px_axi_awsize),
        .m_axi_awburst (px_axi_awburst),
        .m_axi_awlock  (px_axi_awlock),
        .m_axi_awcache (px_axi_awcache),
        .m_axi_awprot  (px_axi_awprot),
        .m_axi_awqos   (px_axi_awqos),
        .m_axi_awvalid (px_axi_awvalid),
        .m_axi_awready (px_axi_awready),

        // AXI Write Data
        .m_axi_wdata   (px_axi_wdata),
        .m_axi_wstrb   (px_axi_wstrb),
        .m_axi_wlast   (px_axi_wlast),
        .m_axi_wvalid  (px_axi_wvalid),
        .m_axi_wready  (px_axi_wready),

        // AXI Write Response
        .m_axi_bid     (s_axi_bid),
        .m_axi_bresp   (s_axi_bresp),
        .m_axi_bvalid  (s_axi_bvalid),
        .m_axi_bready  (px_axi_bready),

        // Status
        .busy          (px_busy)
    );

    // =========================================================================
    // DDR3 Framebuffer Clear
    // =========================================================================
    // Clears framebuffer when fb_clear_cmd is received
    // Uses burst writes for efficiency

    typedef enum logic [3:0] {
        CLR_IDLE,
        CLR_SYNC_CMD,
        CLR_ADDR,
        CLR_DATA,
        CLR_RESP,
        CLR_NEXT,
        CLR_DONE
    } clr_state_t;

    clr_state_t clr_state;
    logic [29:0] clr_addr;
    logic [9:0]  clr_line;
    logic [5:0]  clr_beat;
    logic        fb_clearing;
    rgb565_t     clr_color_sync;

    // Sync clear command from 50 MHz to ui_clk domain
    logic fb_clear_cmd_sync1, fb_clear_cmd_sync2, fb_clear_cmd_sync3;
    logic fb_clear_pulse;

    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst) begin
            fb_clear_cmd_sync1 <= 1'b0;
            fb_clear_cmd_sync2 <= 1'b0;
            fb_clear_cmd_sync3 <= 1'b0;
        end else begin
            fb_clear_cmd_sync1 <= fb_clear_cmd;
            fb_clear_cmd_sync2 <= fb_clear_cmd_sync1;
            fb_clear_cmd_sync3 <= fb_clear_cmd_sync2;
        end
    end

    // Rising edge detection
    assign fb_clear_pulse = fb_clear_cmd_sync2 && !fb_clear_cmd_sync3;

    // Also sync clear color
    logic [15:0] fb_clear_color_sync;
    always_ff @(posedge ui_clk) begin
        if (fb_clear_pulse) begin
            fb_clear_color_sync <= fb_clear_color;
        end
    end

    localparam PIXELS_PER_BEAT = 16;
    localparam BEATS_PER_LINE = FB_WIDTH / PIXELS_PER_BEAT;

    // Generate clear pattern (replicated clear color)
    logic [255:0] clear_pattern;
    always_comb begin
        for (int i = 0; i < 16; i++) begin
            clear_pattern[i*16 +: 16] = fb_clear_color_sync;
        end
    end

    // Clear state machine
    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst) begin
            clr_state <= CLR_IDLE;
            clr_addr <= FB_BASE_ADDR;
            clr_line <= '0;
            clr_beat <= '0;
            fb_clearing <= 1'b0;
        end else begin
            case (clr_state)
                CLR_IDLE: begin
                    if (fb_clear_pulse && init_calib_complete) begin
                        clr_addr <= FB_BASE_ADDR;
                        clr_line <= '0;
                        clr_beat <= '0;
                        fb_clearing <= 1'b1;
                        clr_state <= CLR_ADDR;
                    end
                end

                CLR_ADDR: begin
                    if (clr_axi_awvalid && s_axi_awready) begin
                        clr_state <= CLR_DATA;
                    end
                end

                CLR_DATA: begin
                    if (clr_axi_wvalid && s_axi_wready) begin
                        clr_state <= CLR_RESP;
                    end
                end

                CLR_RESP: begin
                    if (s_axi_bvalid && clr_axi_bready) begin
                        clr_state <= CLR_NEXT;
                    end
                end

                CLR_NEXT: begin
                    clr_addr <= clr_addr + 32;
                    clr_beat <= clr_beat + 1'b1;

                    if (clr_beat == BEATS_PER_LINE - 1) begin
                        clr_beat <= '0;
                        clr_line <= clr_line + 1'b1;

                        if (clr_line == FB_HEIGHT - 1) begin
                            clr_state <= CLR_DONE;
                        end else begin
                            clr_state <= CLR_ADDR;
                        end
                    end else begin
                        clr_state <= CLR_ADDR;
                    end
                end

                CLR_DONE: begin
                    fb_clearing <= 1'b0;
                    clr_state <= CLR_IDLE;
                end

                default: clr_state <= CLR_IDLE;
            endcase
        end
    end

    // Clear AXI signals
    logic clr_axi_awvalid;
    logic clr_axi_wvalid;
    logic clr_axi_bready;

    assign clr_axi_awvalid = (clr_state == CLR_ADDR);
    assign clr_axi_wvalid = (clr_state == CLR_DATA);
    assign clr_axi_bready = (clr_state == CLR_RESP);

    // =========================================================================
    // Line Buffer for Video Readout
    // =========================================================================
    logic frame_start;
    logic line_start;
    logic timing_de;
    logic [9:0] timing_x;
    logic [9:0] timing_y;
    logic timing_hsync;
    logic timing_vsync;

    rgb565_t fb_pixel_data;
    logic fb_pixel_ready;

    logic [3:0]   lb_axi_arid;
    logic [29:0]  lb_axi_araddr;
    logic [7:0]   lb_axi_arlen;
    logic [2:0]   lb_axi_arsize;
    logic [1:0]   lb_axi_arburst;
    logic [0:0]   lb_axi_arlock;
    logic [3:0]   lb_axi_arcache;
    logic [2:0]   lb_axi_arprot;
    logic [3:0]   lb_axi_arqos;
    logic         lb_axi_arvalid;
    logic         lb_axi_arready;

    ddr3_fb_line_buffer #(
        .FB_WIDTH     (FB_WIDTH),
        .FB_HEIGHT    (FB_HEIGHT),
        .FB_BASE_ADDR (FB_BASE_ADDR)
    ) u_line_buffer (
        .ddr_clk        (ui_clk),
        .ddr_rst_n      (~ui_clk_sync_rst),
        .ddr_calib_done (init_calib_complete),

        .video_clk      (clk_25mhz),
        .video_rst_n    (video_rst_n),

        .frame_start    (frame_start),
        .line_start     (line_start),
        .pixel_valid    (timing_de),
        .pixel_x        (timing_x),
        .pixel_y        (timing_y),
        .pixel_data     (fb_pixel_data),
        .pixel_ready    (fb_pixel_ready),

        .m_axi_arid     (lb_axi_arid),
        .m_axi_araddr   (lb_axi_araddr),
        .m_axi_arlen    (lb_axi_arlen),
        .m_axi_arsize   (lb_axi_arsize),
        .m_axi_arburst  (lb_axi_arburst),
        .m_axi_arlock   (lb_axi_arlock),
        .m_axi_arcache  (lb_axi_arcache),
        .m_axi_arprot   (lb_axi_arprot),
        .m_axi_arqos    (lb_axi_arqos),
        .m_axi_arvalid  (lb_axi_arvalid),
        .m_axi_arready  (lb_axi_arready),

        .m_axi_rid      (s_axi_rid),
        .m_axi_rdata    (s_axi_rdata),
        .m_axi_rresp    (s_axi_rresp),
        .m_axi_rlast    (s_axi_rlast),
        .m_axi_rvalid   (s_axi_rvalid),
        .m_axi_rready   (s_axi_rready)
    );

    // =========================================================================
    // AXI Arbitration (Clear vs Pixel Writer vs Reader)
    // =========================================================================
    // Priority: Clear > Pixel writes, Reader runs concurrently

    logic clear_active;
    assign clear_active = (clr_state == CLR_ADDR) || (clr_state == CLR_DATA) || (clr_state == CLR_RESP);

    // Write Address Channel
    always_comb begin
        if (clear_active) begin
            s_axi_awid    = 4'd0;
            s_axi_awaddr  = clr_addr;
            s_axi_awlen   = 8'd0;
            s_axi_awsize  = 3'b101;
            s_axi_awburst = 2'b01;
            s_axi_awlock  = 1'b0;
            s_axi_awcache = 4'b0011;
            s_axi_awprot  = 3'b000;
            s_axi_awqos   = 4'd0;
            s_axi_awvalid = clr_axi_awvalid;
        end else begin
            s_axi_awid    = px_axi_awid;
            s_axi_awaddr  = px_axi_awaddr;
            s_axi_awlen   = px_axi_awlen;
            s_axi_awsize  = px_axi_awsize;
            s_axi_awburst = px_axi_awburst;
            s_axi_awlock  = px_axi_awlock;
            s_axi_awcache = px_axi_awcache;
            s_axi_awprot  = px_axi_awprot;
            s_axi_awqos   = px_axi_awqos;
            s_axi_awvalid = px_axi_awvalid;
        end
    end

    assign px_axi_awready = !clear_active && s_axi_awready;

    // Write Data Channel
    always_comb begin
        if (clear_active) begin
            s_axi_wdata  = clear_pattern;
            s_axi_wstrb  = 32'hFFFFFFFF;
            s_axi_wlast  = 1'b1;
            s_axi_wvalid = clr_axi_wvalid;
        end else begin
            s_axi_wdata  = px_axi_wdata;
            s_axi_wstrb  = px_axi_wstrb;
            s_axi_wlast  = px_axi_wlast;
            s_axi_wvalid = px_axi_wvalid;
        end
    end

    assign px_axi_wready = !clear_active && s_axi_wready;

    // Write Response
    assign s_axi_bready = clear_active ? clr_axi_bready : px_axi_bready;

    // Read channel
    assign s_axi_arid    = lb_axi_arid;
    assign s_axi_araddr  = lb_axi_araddr;
    assign s_axi_arlen   = lb_axi_arlen;
    assign s_axi_arsize  = lb_axi_arsize;
    assign s_axi_arburst = lb_axi_arburst;
    assign s_axi_arlock  = lb_axi_arlock;
    assign s_axi_arcache = lb_axi_arcache;
    assign s_axi_arprot  = lb_axi_arprot;
    assign s_axi_arqos   = lb_axi_arqos;
    assign s_axi_arvalid = init_calib_complete && lb_axi_arvalid;

    assign lb_axi_arready = init_calib_complete && s_axi_arready;

    // =========================================================================
    // Video Timing Generator
    // =========================================================================
    logic pixel_clk;
    logic rst_pixel_n;

    assign pixel_clk = clk_25mhz;

    logic [2:0] rst_sync_reg;
    always_ff @(posedge pixel_clk or negedge video_rst_n) begin
        if (!video_rst_n) begin
            rst_sync_reg <= 3'b000;
        end else begin
            rst_sync_reg <= {rst_sync_reg[1:0], 1'b1};
        end
    end
    assign rst_pixel_n = rst_sync_reg[2];

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
    // RGB to YCbCr Conversion and HDMI Output
    // =========================================================================
    logic timing_de_r, timing_hsync_r, timing_vsync_r;

    always_ff @(posedge pixel_clk or negedge rst_pixel_n) begin
        if (!rst_pixel_n) begin
            timing_de_r <= 1'b0;
            timing_hsync_r <= 1'b1;
            timing_vsync_r <= 1'b1;
        end else begin
            timing_de_r <= timing_de;
            timing_hsync_r <= timing_hsync;
            timing_vsync_r <= timing_vsync;
        end
    end

    rgb565_t selected_rgb;
    assign selected_rgb = fb_pixel_ready ? fb_pixel_data : 16'h0000;

    logic [15:0] ycbcr_data;
    logic        ycbcr_de;
    logic        ycbcr_hsync;
    logic        ycbcr_vsync;

    rgb_to_ycbcr u_rgb_to_ycbcr (
        .pixel_clk    (pixel_clk),
        .rst_n        (rst_pixel_n),
        .rgb565_in    (selected_rgb),
        .de_in        (timing_de_r),
        .hsync_in     (timing_hsync_r),
        .vsync_in     (timing_vsync_r),
        .ycbcr_out    (ycbcr_data),
        .de_out       (ycbcr_de),
        .hsync_out    (ycbcr_hsync),
        .vsync_out    (ycbcr_vsync)
    );

    always_ff @(posedge pixel_clk or negedge rst_pixel_n) begin
        if (!rst_pixel_n) begin
            hdmi_d     <= 16'h8010;
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

    assign hdmi_clk = pixel_clk;

    // =========================================================================
    // ADV7511 I2C Initialization
    // =========================================================================
    logic i2c_scl_o, i2c_scl_oen, i2c_scl_i;
    logic i2c_sda_o, i2c_sda_oen, i2c_sda_i;
    logic hdmi_init_done, hdmi_init_error;

    IOBUF iobuf_scl (
        .O  (i2c_scl_i),
        .IO (i2c_scl),
        .I  (i2c_scl_o),
        .T  (i2c_scl_oen)
    );

    IOBUF iobuf_sda (
        .O  (i2c_sda_i),
        .IO (i2c_sda),
        .I  (i2c_sda_o),
        .T  (i2c_sda_oen)
    );

    logic [6:0]  i2c_slave_addr;
    logic [7:0]  i2c_reg_addr;
    logic [7:0]  i2c_write_data;
    logic        i2c_write_req;
    logic        i2c_single_byte;
    logic        i2c_busy;
    logic        i2c_done;
    logic        i2c_ack_error;

    logic init_start;
    logic init_started;
    logic [15:0] init_delay;

    always_ff @(posedge clk_50mhz or negedge video_rst_n) begin
        if (!video_rst_n) begin
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
        .rst_n          (video_rst_n),
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
        .CLK_DIV (125)
    ) u_i2c_master (
        .clk            (clk_50mhz),
        .rst_n          (video_rst_n),
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

    // =========================================================================
    // LED Status Display
    // =========================================================================
    logic [25:0] heartbeat_cnt;

    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst) begin
            heartbeat_cnt <= '0;
        end else begin
            heartbeat_cnt <= heartbeat_cnt + 1'b1;
        end
    end

    // LED assignments
    // LED[0] = MMCM locked
    // LED[1] = DDR3 calibration complete
    // LED[2] = Rasterizer busy / FIFO has data
    // LED[3] = FB clearing
    // LED[4] = UART activity (blink on valid byte)
    // LED[5] = HDMI init done
    // LED[6] = HDMI init error
    // LED[7] = Heartbeat

    // Sync UART valid to ui_clk for LED
    logic uart_valid_sync1, uart_valid_sync2;
    always_ff @(posedge ui_clk) begin
        uart_valid_sync1 <= uart_valid;
        uart_valid_sync2 <= uart_valid_sync1;
    end

    logic [19:0] uart_led_cnt;
    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst) begin
            uart_led_cnt <= '0;
        end else if (uart_valid_sync2) begin
            uart_led_cnt <= '1;
        end else if (uart_led_cnt != 0) begin
            uart_led_cnt <= uart_led_cnt - 1'b1;
        end
    end

    always_comb begin
        gpio_led[0] = mmcm_locked;
        gpio_led[1] = init_calib_complete;
        gpio_led[2] = rast_busy || (fifo_fill_level > 0);
        gpio_led[3] = fb_clearing;
        gpio_led[4] = (uart_led_cnt != 0);
        gpio_led[5] = hdmi_init_done;
        gpio_led[6] = hdmi_init_error;
        gpio_led[7] = heartbeat_cnt[24];
    end

endmodule
