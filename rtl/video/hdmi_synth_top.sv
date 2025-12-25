// Celery3D GPU - HDMI Output Synthesis Top Level for KC705
// Uses 200 MHz differential clock from KC705 oscillator
// Generates 50 MHz system clock and 25 MHz pixel clock internally

module hdmi_synth_top (
    // 200 MHz differential input clock (KC705 SYSCLK)
    input  logic        sys_clk_p,
    input  logic        sys_clk_n,

    // NOTE: No external reset - use internal power-on reset like working board test

    // HDMI output pins (directly to ADV7511)
    output logic [15:0] hdmi_d,       // YCbCr 4:2:2 data
    output logic        hdmi_clk,     // Pixel clock to ADV7511
    output logic        hdmi_de,      // Data enable
    output logic        hdmi_hsync,   // Horizontal sync
    output logic        hdmi_vsync,   // Vertical sync

    // I2C bidirectional pins (directly to board)
    inout  wire         i2c_scl,
    inout  wire         i2c_sda,
    output logic        i2c_mux_reset_n,  // PCA9548 mux reset (active low)

    // Control inputs (directly from DIP switches)
    input  logic [1:0]  pattern_sel,      // Test pattern selection
    input  logic        use_framebuffer,  // 0=test pattern, 1=framebuffer

    // Status outputs (directly to LEDs)
    output logic        hdmi_init_done,
    output logic        hdmi_init_error,
    output logic        pixel_clk_locked,
    output logic        heartbeat,        // Debug: blinks to show design is running
    output logic        alive             // Debug: always ON to verify pin mapping
);

    // =========================================================================
    // Clock Generation
    // Single MMCM generates both 50 MHz (system) and 25 MHz (pixel) clocks
    // =========================================================================
    logic clk_50mhz;
    logic clk_25mhz;
    logic mmcm_locked;

    clk_gen_kc705 u_clk_gen (
        .clk_200mhz_p (sys_clk_p),
        .clk_200mhz_n (sys_clk_n),
        .rst          (1'b0),         // No external reset - MMCM self-resets
        .clk_50mhz    (clk_50mhz),
        .clk_25mhz    (clk_25mhz),
        .locked       (mmcm_locked)
    );

    // Use the 25 MHz directly from the main MMCM - no second MMCM needed!

    // =========================================================================
    // Internal Reset Generation (like working board test - no external reset)
    // =========================================================================
    // Generate internal reset from MMCM lock
    logic [7:0] reset_cnt;
    logic       rst_n;

    always_ff @(posedge clk_50mhz) begin
        if (!mmcm_locked) begin
            reset_cnt <= 8'd0;
            rst_n <= 1'b0;
        end else if (reset_cnt != 8'hFF) begin
            reset_cnt <= reset_cnt + 1'b1;
            rst_n <= 1'b0;
        end else begin
            rst_n <= 1'b1;
        end
    end

    // Drive I2C mux reset HIGH to enable the PCA9548 mux
    // (active-low reset, so HIGH = normal operation)
    assign i2c_mux_reset_n = rst_n;

    // =========================================================================
    // Heartbeat LED - blinks ~1Hz to show design is running
    // Uses MMCM locked directly - no reset dependency for basic visibility
    // =========================================================================
    logic [25:0] heartbeat_cnt;

    always_ff @(posedge clk_50mhz) begin
        if (!mmcm_locked) begin
            heartbeat_cnt <= '0;
        end else begin
            heartbeat_cnt <= heartbeat_cnt + 1'b1;
        end
    end

    assign heartbeat = heartbeat_cnt[25];  // ~1.5 Hz blink with 50MHz clock

    // Alive LED: Shows MMCM lock status - ON when clocks are working
    assign alive = mmcm_locked;

    // =========================================================================
    // I2C Tristate Signals
    // =========================================================================
    logic i2c_scl_o;
    logic i2c_scl_oen;
    logic i2c_scl_i;
    logic i2c_sda_o;
    logic i2c_sda_oen;
    logic i2c_sda_i;

    // I2C SCL IOBUF (active-low output enable)
    IOBUF iobuf_scl (
        .O  (i2c_scl_i),        // Buffer output (input path)
        .IO (i2c_scl),          // Bidirectional pad
        .I  (i2c_scl_o),        // Buffer input (output path)
        .T  (i2c_scl_oen)       // 3-state enable (active high = tristate)
    );

    // I2C SDA IOBUF (active-low output enable)
    IOBUF iobuf_sda (
        .O  (i2c_sda_i),        // Buffer output (input path)
        .IO (i2c_sda),          // Bidirectional pad
        .I  (i2c_sda_o),        // Buffer input (output path)
        .T  (i2c_sda_oen)       // 3-state enable (active high = tristate)
    );

    // =========================================================================
    // Framebuffer Interface (unused for standalone test)
    // =========================================================================
    import celery_pkg::rgb565_t;

    logic [9:0]  fb_read_x;
    logic [9:0]  fb_read_y;
    logic        fb_read_en;
    rgb565_t     fb_read_data;
    logic        fb_read_valid;

    // Tie off framebuffer interface - not used in standalone test
    assign fb_read_data = 16'h0000;
    assign fb_read_valid = 1'b0;

    // =========================================================================
    // Internal HDMI signals
    // =========================================================================

    // =========================================================================
    // HDMI Top Instance
    // =========================================================================
    hdmi_top u_hdmi_top (
        .clk_50mhz      (clk_50mhz),
        .clk_25mhz      (clk_25mhz),     // Pass 25 MHz directly (no second MMCM)
        .rst_n          (rst_n & mmcm_locked),

        // HDMI outputs
        .hdmi_d         (hdmi_d),
        .hdmi_clk       (hdmi_clk),
        .hdmi_de        (hdmi_de),
        .hdmi_hsync     (hdmi_hsync),
        .hdmi_vsync     (hdmi_vsync),

        // I2C (tristate interface)
        .i2c_scl_o      (i2c_scl_o),
        .i2c_scl_oen    (i2c_scl_oen),
        .i2c_scl_i      (i2c_scl_i),
        .i2c_sda_o      (i2c_sda_o),
        .i2c_sda_oen    (i2c_sda_oen),
        .i2c_sda_i      (i2c_sda_i),

        // Framebuffer interface (unused)
        .fb_read_x      (fb_read_x),
        .fb_read_y      (fb_read_y),
        .fb_read_en     (fb_read_en),
        .fb_read_data   (fb_read_data),
        .fb_read_valid  (fb_read_valid),

        // Control - force test pattern mode for debugging
        .pattern_sel    (2'b00),           // Force color bars
        .use_framebuffer(1'b0),            // Force test pattern (ignore DIP switch)

        // Status
        .hdmi_init_done (hdmi_init_done),
        .hdmi_init_error(hdmi_init_error)
    );

    // Use single MMCM lock status
    assign pixel_clk_locked = mmcm_locked;

endmodule
