//-----------------------------------------------------------------------------
// celery3d_top.sv
// Top-level module for Celery3D Phase 1 - Video Foundation
//-----------------------------------------------------------------------------

module celery3d_top (
    // System clock (200 MHz differential)
    input  wire        sys_clk_p,
    input  wire        sys_clk_n,

    // System reset (active-HIGH from CPU_RESET button)
    input  wire        cpu_reset,

    // I2C interface
    inout  wire        iic_sda,
    inout  wire        iic_scl,
    output wire        iic_mux_reset_n,

    // HDMI interface
    output wire        hdmi_clk,
    output wire [15:0] hdmi_data,
    output wire        hdmi_de,
    output wire        hdmi_hsync,
    output wire        hdmi_vsync,
    input  wire        hdmi_int,

    // Status LEDs
    output wire [7:0]  led,

    // DIP switches for pattern selection
    input  wire [3:0]  gpio_sw
);

    //-------------------------------------------------------------------------
    // Clocks and Reset
    //-------------------------------------------------------------------------
    wire clk_100mhz, clk_pixel, mmcm_locked;
    wire rst_n = ~cpu_reset;

    // Synchronized resets
    reg [3:0] rst_sync_100, rst_sync_pixel;
    wire rst_n_100 = rst_sync_100[3];
    wire rst_n_pixel = rst_sync_pixel[3];

    always_ff @(posedge clk_100mhz or negedge rst_n) begin
        if (!rst_n) rst_sync_100 <= 4'b0;
        else if (!mmcm_locked) rst_sync_100 <= 4'b0;
        else rst_sync_100 <= {rst_sync_100[2:0], 1'b1};
    end

    always_ff @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) rst_sync_pixel <= 4'b0;
        else if (!mmcm_locked) rst_sync_pixel <= 4'b0;
        else rst_sync_pixel <= {rst_sync_pixel[2:0], 1'b1};
    end

    //-------------------------------------------------------------------------
    // Clock Generation
    //-------------------------------------------------------------------------
    clock_gen u_clock_gen (
        .clk_in_p   (sys_clk_p),
        .clk_in_n   (sys_clk_n),
        .clk_100mhz (clk_100mhz),
        .clk_pixel  (clk_pixel),
        .locked     (mmcm_locked),
        .rst_n      (rst_n)
    );

    //-------------------------------------------------------------------------
    // I2C Interface
    //-------------------------------------------------------------------------
    wire i2c_scl_o, i2c_scl_oe, i2c_scl_i;
    wire i2c_sda_o, i2c_sda_oe, i2c_sda_i;

    IOBUF iobuf_sda (.IO(iic_sda), .I(i2c_sda_o), .T(~i2c_sda_oe), .O(i2c_sda_i));
    IOBUF iobuf_scl (.IO(iic_scl), .I(i2c_scl_o), .T(~i2c_scl_oe), .O(i2c_scl_i));

    // I2C master signals
    wire        i2c_start, i2c_done, i2c_error;
    wire [6:0]  i2c_slave_addr;
    wire [7:0]  i2c_reg_addr, i2c_wdata;
    wire        i2c_rw;

    i2c_master #(
        .CLK_FREQ_HZ(100_000_000),
        .I2C_FREQ_HZ(100_000)
    ) u_i2c_master (
        .clk        (clk_100mhz),
        .rst_n      (rst_n_100),
        .start      (i2c_start),
        .done       (i2c_done),
        .error      (i2c_error),
        .slave_addr (i2c_slave_addr),
        .reg_addr   (i2c_reg_addr),
        .rw         (i2c_rw),
        .wdata      (i2c_wdata),
        .rdata      (),
        .scl_o      (i2c_scl_o),
        .scl_oe     (i2c_scl_oe),
        .scl_i      (i2c_scl_i),
        .sda_o      (i2c_sda_o),
        .sda_oe     (i2c_sda_oe),
        .sda_i      (i2c_sda_i)
    );

    //-------------------------------------------------------------------------
    // ADV7511 Initialization
    //-------------------------------------------------------------------------
    wire init_done, init_error;

    // Auto-start after reset
    reg init_start_r, init_started;
    always_ff @(posedge clk_100mhz or negedge rst_n_100) begin
        if (!rst_n_100) begin
            init_start_r <= 0;
            init_started <= 0;
        end else begin
            init_start_r <= 0;
            if (!init_started && !init_done) begin
                init_start_r <= 1;
                init_started <= 1;
            end
        end
    end

    adv7511_init #(
        .CLK_FREQ_HZ(100_000_000)
    ) u_adv7511_init (
        .clk            (clk_100mhz),
        .rst_n          (rst_n_100),
        .start          (init_start_r),
        .done           (init_done),
        .error          (init_error),
        .i2c_mux_reset_n(iic_mux_reset_n),
        .i2c_start      (i2c_start),
        .i2c_done       (i2c_done),
        .i2c_error      (i2c_error),
        .i2c_slave_addr (i2c_slave_addr),
        .i2c_reg_addr   (i2c_reg_addr),
        .i2c_rw         (i2c_rw),
        .i2c_wdata      (i2c_wdata)
    );

    //-------------------------------------------------------------------------
    // Video Pipeline
    //-------------------------------------------------------------------------
    wire vtg_hsync, vtg_vsync, vtg_de;
    wire [9:0] pixel_x, pixel_y;

    video_timing_gen u_video_timing_gen (
        .clk_pixel   (clk_pixel),
        .rst_n       (rst_n_pixel),
        .hsync       (vtg_hsync),
        .vsync       (vtg_vsync),
        .data_enable (vtg_de),
        .pixel_x     (pixel_x),
        .pixel_y     (pixel_y),
        .frame_start (),
        .line_start  ()
    );

    wire [15:0] pattern_rgb565;
    wire pattern_valid;

    test_pattern_gen u_test_pattern_gen (
        .clk_pixel   (clk_pixel),
        .rst_n       (rst_n_pixel),
        .pixel_x     (pixel_x),
        .pixel_y     (pixel_y),
        .data_enable (vtg_de),
        .pattern_sel (gpio_sw[2:0]),
        .rgb565      (pattern_rgb565),
        .rgb565_valid(pattern_valid)
    );

    wire [15:0] ycbcr_data;
    wire ycbcr_de, ycbcr_hsync, ycbcr_vsync;

    rgb565_to_ycbcr u_rgb565_to_ycbcr (
        .clk_pixel      (clk_pixel),
        .rst_n          (rst_n_pixel),
        .rgb565_in      (pattern_rgb565),
        .data_enable_in (pattern_valid),
        .hsync_in       (vtg_hsync),
        .vsync_in       (vtg_vsync),
        .ycbcr_out      (ycbcr_data),
        .data_enable_out(ycbcr_de),
        .hsync_out      (ycbcr_hsync),
        .vsync_out      (ycbcr_vsync)
    );

    hdmi_output u_hdmi_output (
        .clk_pixel  (clk_pixel),
        .rst_n      (rst_n_pixel),
        .ycbcr_data (ycbcr_data),
        .data_enable(ycbcr_de),
        .hsync      (ycbcr_hsync),
        .vsync      (ycbcr_vsync),
        .hdmi_clk   (hdmi_clk),
        .hdmi_data  (hdmi_data),
        .hdmi_de    (hdmi_de),
        .hdmi_hsync (hdmi_hsync),
        .hdmi_vsync (hdmi_vsync)
    );

    //-------------------------------------------------------------------------
    // LED Status
    //-------------------------------------------------------------------------
    assign led[0] = mmcm_locked;
    assign led[1] = init_done;
    assign led[2] = init_error;
    assign led[3] = vtg_vsync;
    assign led[7:4] = 4'b0;

endmodule
