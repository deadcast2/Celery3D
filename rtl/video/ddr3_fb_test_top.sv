// DDR3 Framebuffer Test Top Level for KC705
// Phase 1: Writes test pattern to DDR3, displays via HDMI
//
// This validates the DDR3 -> HDMI read path before integrating the rasterizer.
// A gradient test pattern is written to DDR3 at startup, then continuously
// read and displayed on HDMI.

module ddr3_fb_test_top (
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
    import celery_pkg::rgb565_t;

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
    // Test Pattern Writer State Machine
    // =========================================================================
    // Writes a gradient pattern to DDR3 at startup, then hands off to reader

    typedef enum logic [3:0] {
        WR_IDLE,
        WR_WAIT_CALIB,
        WR_ADDR,
        WR_DATA,
        WR_RESP,
        WR_NEXT,
        WR_DONE
    } wr_state_t;

    wr_state_t wr_state;

    // Write tracking
    logic [29:0] wr_addr;
    logic [9:0]  wr_line;
    logic [5:0]  wr_beat;
    logic        pattern_write_done;

    // Each beat writes 16 pixels (256 bits = 32 bytes)
    localparam PIXELS_PER_BEAT = 16;
    localparam BEATS_PER_LINE = FB_WIDTH / PIXELS_PER_BEAT;  // 40

    // Generate gradient test pattern (horizontal color gradient)
    function automatic [255:0] generate_gradient_pattern(
        input [9:0] line,
        input [5:0] beat
    );
        logic [255:0] data;
        logic [9:0] base_x;
        logic [15:0] pixel;

        base_x = beat * PIXELS_PER_BEAT;

        for (int i = 0; i < 16; i++) begin
            // RGB565 gradient: Red varies with X, Green with Y, Blue constant
            logic [4:0] r, b;
            logic [5:0] g;
            logic [9:0] x;

            x = base_x + i;

            // Horizontal red gradient (0-31 over 640 pixels)
            r = x[9:5];
            // Vertical green gradient (0-63 over 480 pixels)
            g = line[8:3];
            // Blue checkerboard pattern
            b = ((x[5] ^ line[5])) ? 5'd31 : 5'd0;

            pixel = {r, g, b};
            data[i*16 +: 16] = pixel;
        end

        return data;
    endfunction

    // Writer state machine
    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst) begin
            wr_state <= WR_IDLE;
            wr_addr <= FB_BASE_ADDR;
            wr_line <= '0;
            wr_beat <= '0;
            pattern_write_done <= 1'b0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    wr_state <= WR_WAIT_CALIB;
                end

                WR_WAIT_CALIB: begin
                    if (init_calib_complete) begin
                        wr_addr <= FB_BASE_ADDR;
                        wr_line <= '0;
                        wr_beat <= '0;
                        wr_state <= WR_ADDR;
                    end
                end

                WR_ADDR: begin
                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_state <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        wr_state <= WR_RESP;
                    end
                end

                WR_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        wr_state <= WR_NEXT;
                    end
                end

                WR_NEXT: begin
                    wr_addr <= wr_addr + 32;  // 32 bytes per beat
                    wr_beat <= wr_beat + 1'b1;

                    if (wr_beat == BEATS_PER_LINE - 1) begin
                        wr_beat <= '0;
                        wr_line <= wr_line + 1'b1;

                        if (wr_line == FB_HEIGHT - 1) begin
                            // Done writing entire framebuffer
                            wr_state <= WR_DONE;
                            pattern_write_done <= 1'b1;
                        end else begin
                            wr_state <= WR_ADDR;
                        end
                    end else begin
                        wr_state <= WR_ADDR;
                    end
                end

                WR_DONE: begin
                    // Stay here, pattern is written
                end

                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Line Buffer for Video Readout
    // =========================================================================

    // Video timing signals
    logic frame_start;
    logic line_start;
    logic timing_de;
    logic [9:0] timing_x;
    logic [9:0] timing_y;
    logic timing_hsync;
    logic timing_vsync;

    // Pixel data from line buffer
    rgb565_t fb_pixel_data;
    logic fb_pixel_ready;

    // Line buffer AXI read signals
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
        // DDR clock domain
        .ddr_clk        (ui_clk),
        .ddr_rst_n      (~ui_clk_sync_rst),
        .ddr_calib_done (pattern_write_done),  // Start reading after pattern is written

        // Video clock domain
        .video_clk      (clk_25mhz),
        .video_rst_n    (video_rst_n),

        // Video timing
        .frame_start    (frame_start),
        .line_start     (line_start),
        .pixel_valid    (timing_de),
        .pixel_x        (timing_x),
        .pixel_y        (timing_y),
        .pixel_data     (fb_pixel_data),
        .pixel_ready    (fb_pixel_ready),

        // AXI Read Address
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

        // AXI Read Data
        .m_axi_rid      (s_axi_rid),
        .m_axi_rdata    (s_axi_rdata),
        .m_axi_rresp    (s_axi_rresp),
        .m_axi_rlast    (s_axi_rlast),
        .m_axi_rvalid   (s_axi_rvalid),
        .m_axi_rready   (s_axi_rready)
    );

    // =========================================================================
    // AXI Arbitration (Writer vs Reader)
    // =========================================================================
    // Simple: Writer has priority during startup, Reader takes over after

    // Write channel - only active during pattern write
    assign s_axi_awid    = 4'd0;
    assign s_axi_awaddr  = wr_addr;
    assign s_axi_awlen   = 8'd0;           // Single beat
    assign s_axi_awsize  = 3'b101;         // 32 bytes
    assign s_axi_awburst = 2'b01;          // INCR
    assign s_axi_awlock  = 1'b0;
    assign s_axi_awcache = 4'b0011;
    assign s_axi_awprot  = 3'b000;
    assign s_axi_awqos   = 4'd0;
    assign s_axi_awvalid = (wr_state == WR_ADDR);

    assign s_axi_wdata   = generate_gradient_pattern(wr_line, wr_beat);
    assign s_axi_wstrb   = 32'hFFFFFFFF;
    assign s_axi_wlast   = 1'b1;
    assign s_axi_wvalid  = (wr_state == WR_DATA);

    assign s_axi_bready  = (wr_state == WR_RESP);

    // Read channel - from line buffer after pattern write done
    assign s_axi_arid    = lb_axi_arid;
    assign s_axi_araddr  = lb_axi_araddr;
    assign s_axi_arlen   = lb_axi_arlen;
    assign s_axi_arsize  = lb_axi_arsize;
    assign s_axi_arburst = lb_axi_arburst;
    assign s_axi_arlock  = lb_axi_arlock;
    assign s_axi_arcache = lb_axi_arcache;
    assign s_axi_arprot  = lb_axi_arprot;
    assign s_axi_arqos   = lb_axi_arqos;
    assign s_axi_arvalid = pattern_write_done && lb_axi_arvalid;

    assign lb_axi_arready = pattern_write_done && s_axi_arready;

    // =========================================================================
    // Video Timing Generator
    // =========================================================================
    logic pixel_clk;
    logic rst_pixel_n;

    assign pixel_clk = clk_25mhz;

    // Sync reset to pixel clock
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

    // Pipeline registers to align with line buffer latency
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

    // Select pixel: use framebuffer data if ready, else black
    rgb565_t selected_rgb;
    assign selected_rgb = fb_pixel_ready ? fb_pixel_data : 16'h0000;

    // YCbCr conversion
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

    // HDMI output registers
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

    // I2C IOBUFs
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

    // I2C signals
    logic [6:0]  i2c_slave_addr;
    logic [7:0]  i2c_reg_addr;
    logic [7:0]  i2c_write_data;
    logic        i2c_write_req;
    logic        i2c_single_byte;
    logic        i2c_busy;
    logic        i2c_done;
    logic        i2c_ack_error;

    // Start I2C init after reset
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
    // LED[2] = Pattern write in progress (heartbeat)
    // LED[3] = Pattern write done
    // LED[4] = Video clock locked
    // LED[5] = HDMI init done
    // LED[6] = HDMI init error
    // LED[7] = Heartbeat

    always_comb begin
        gpio_led[0] = mmcm_locked;
        gpio_led[1] = init_calib_complete;
        gpio_led[2] = (wr_state != WR_DONE && wr_state != WR_IDLE && wr_state != WR_WAIT_CALIB)
                      ? heartbeat_cnt[22] : 1'b0;
        gpio_led[3] = pattern_write_done;
        gpio_led[4] = video_clk_locked;
        gpio_led[5] = hdmi_init_done;
        gpio_led[6] = hdmi_init_error;
        gpio_led[7] = heartbeat_cnt[24];
    end

endmodule
