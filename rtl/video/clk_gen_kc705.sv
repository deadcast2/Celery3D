// Celery3D GPU - Clock Generator for KC705
// Generates clocks from 200 MHz differential input
// Outputs: 50 MHz system clock, 25 MHz pixel clock

module clk_gen_kc705 (
    // 200 MHz differential input (from KC705 oscillator)
    input  logic        clk_200mhz_p,
    input  logic        clk_200mhz_n,

    input  logic        rst,          // Async reset (active high)

    output logic        clk_50mhz,    // 50 MHz system clock
    output logic        clk_25mhz,    // 25 MHz pixel clock
    output logic        locked        // MMCM locked indicator
);

`ifdef SYNTHESIS
    // =========================================================================
    // Synthesis: IBUFDS + MMCME2_ADV for Kintex-7
    // =========================================================================
    //
    // MMCM Configuration:
    //   Input:  200 MHz (CLKIN1)
    //   VCO:    200 * 5 = 1000 MHz (CLKFBOUT_MULT_F = 5.0)
    //   CLKOUT0: 1000 / 40 = 25 MHz (pixel clock)
    //   CLKOUT1: 1000 / 20 = 50 MHz (system clock)

    logic clk_200mhz_ibuf;
    logic clkfb;
    logic clk_out0, clk_out1;
    logic clk_out0_buf, clk_out1_buf;

    // Differential input buffer
    IBUFDS #(
        .DIFF_TERM    ("FALSE"),
        .IBUF_LOW_PWR ("FALSE"),
        .IOSTANDARD   ("LVDS")
    ) ibufds_clk (
        .O  (clk_200mhz_ibuf),
        .I  (clk_200mhz_p),
        .IB (clk_200mhz_n)
    );

    MMCME2_ADV #(
        .BANDWIDTH            ("OPTIMIZED"),
        .CLKFBOUT_MULT_F      (5.0),        // VCO = 200 * 5 = 1000 MHz
        .CLKFBOUT_PHASE       (0.0),
        .CLKIN1_PERIOD        (5.0),        // 200 MHz = 5 ns period
        .CLKOUT0_DIVIDE_F     (40.0),       // 1000 / 40 = 25 MHz (pixel)
        .CLKOUT0_DUTY_CYCLE   (0.5),
        .CLKOUT0_PHASE        (0.0),
        .CLKOUT1_DIVIDE       (20),         // 1000 / 20 = 50 MHz (system)
        .CLKOUT1_DUTY_CYCLE   (0.5),
        .CLKOUT1_PHASE        (0.0),
        .DIVCLK_DIVIDE        (1),
        .REF_JITTER1          (0.01),
        .STARTUP_WAIT         ("FALSE")
    ) mmcm_inst (
        .CLKIN1      (clk_200mhz_ibuf),
        .CLKIN2      (1'b0),
        .CLKINSEL    (1'b1),          // Select CLKIN1

        .CLKFBIN     (clkfb),
        .CLKFBOUT    (clkfb),
        .CLKFBOUTB   (),

        .CLKOUT0     (clk_out0),      // 25 MHz
        .CLKOUT0B    (),
        .CLKOUT1     (clk_out1),      // 50 MHz
        .CLKOUT1B    (),
        .CLKOUT2     (),
        .CLKOUT2B    (),
        .CLKOUT3     (),
        .CLKOUT3B    (),
        .CLKOUT4     (),
        .CLKOUT5     (),
        .CLKOUT6     (),

        .LOCKED      (locked),

        .PWRDWN      (1'b0),
        .RST         (rst),

        // Dynamic reconfiguration (unused)
        .DADDR       (7'd0),
        .DCLK        (1'b0),
        .DEN         (1'b0),
        .DI          (16'd0),
        .DO          (),
        .DRDY        (),
        .DWE         (1'b0),

        // Phase shift (unused)
        .PSCLK       (1'b0),
        .PSEN        (1'b0),
        .PSINCDEC    (1'b0),
        .PSDONE      (),

        .CLKINSTOPPED(),
        .CLKFBSTOPPED()
    );

    // Buffer the output clocks
    BUFG clkout0_buf (
        .I (clk_out0),
        .O (clk_out0_buf)
    );

    BUFG clkout1_buf (
        .I (clk_out1),
        .O (clk_out1_buf)
    );

    assign clk_25mhz = clk_out0_buf;
    assign clk_50mhz = clk_out1_buf;

`else
    // =========================================================================
    // Simulation: Simple clock dividers
    // =========================================================================

    logic clk_in;
    logic [2:0] div_cnt;
    logic locked_r;
    logic [7:0] lock_counter;

    // For simulation, just use the positive clock
    assign clk_in = clk_200mhz_p;

    // Generate 50 MHz (divide by 4) and 25 MHz (divide by 8)
    always_ff @(posedge clk_in or posedge rst) begin
        if (rst) begin
            div_cnt <= '0;
        end else begin
            div_cnt <= div_cnt + 1'b1;
        end
    end

    assign clk_50mhz = div_cnt[1];  // 200/4 = 50 MHz
    assign clk_25mhz = div_cnt[2];  // 200/8 = 25 MHz

    // Simulate lock delay
    always_ff @(posedge clk_in or posedge rst) begin
        if (rst) begin
            lock_counter <= '0;
            locked_r <= 1'b0;
        end else if (!locked_r) begin
            if (lock_counter == 8'hFF) begin
                locked_r <= 1'b1;
            end else begin
                lock_counter <= lock_counter + 1'b1;
            end
        end
    end

    assign locked = locked_r;

`endif

endmodule
