//-----------------------------------------------------------------------------
// clock_gen.sv
// Clock generation using MMCM for Celery3D
// Generates 100 MHz core clock and 25 MHz pixel clock from 200 MHz input
//-----------------------------------------------------------------------------

module clock_gen (
    // External differential clock input (200 MHz LVDS)
    input  wire clk_in_p,       // SYSCLK_P (AD12)
    input  wire clk_in_n,       // SYSCLK_N (AD11)

    // Generated clocks
    output wire clk_100mhz,     // Core/I2C clock
    output wire clk_pixel,      // 25 MHz pixel clock

    // Status
    output wire locked,         // MMCM locked indicator

    // Reset
    input  wire rst_n           // Active-low reset
);

    //-------------------------------------------------------------------------
    // Internal signals
    //-------------------------------------------------------------------------
    wire clk_200mhz;            // Buffered 200 MHz input
    wire clk_100mhz_unbuf;      // MMCM output before BUFG
    wire clk_pixel_unbuf;       // MMCM output before BUFG
    wire mmcm_feedback;         // MMCM feedback clock
    wire mmcm_feedback_buf;     // Buffered feedback

    //-------------------------------------------------------------------------
    // Differential input buffer
    //-------------------------------------------------------------------------
    IBUFDS #(
        .DIFF_TERM    ("FALSE"),
        .IBUF_LOW_PWR ("FALSE"),
        .IOSTANDARD   ("LVDS")
    ) ibufds_clk (
        .I  (clk_in_p),
        .IB (clk_in_n),
        .O  (clk_200mhz)
    );

    //-------------------------------------------------------------------------
    // MMCM Configuration
    // Input:  200 MHz
    // VCO:    1000 MHz (200 MHz * 5.0)
    // CLKOUT0: 100 MHz (1000 / 10)
    // CLKOUT1:  25 MHz (1000 / 40)
    //-------------------------------------------------------------------------
    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (5.0),          // VCO = 200 * 5 = 1000 MHz
        .CLKFBOUT_PHASE     (0.0),
        .CLKIN1_PERIOD      (5.0),          // 200 MHz = 5 ns period

        .CLKOUT0_DIVIDE_F   (10.0),         // 1000 / 10 = 100 MHz
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT0_PHASE      (0.0),

        .CLKOUT1_DIVIDE     (40),           // 1000 / 40 = 25 MHz
        .CLKOUT1_DUTY_CYCLE (0.5),
        .CLKOUT1_PHASE      (0.0),

        .CLKOUT2_DIVIDE     (1),
        .CLKOUT3_DIVIDE     (1),
        .CLKOUT4_DIVIDE     (1),
        .CLKOUT5_DIVIDE     (1),
        .CLKOUT6_DIVIDE     (1),

        .DIVCLK_DIVIDE      (1),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) mmcm_inst (
        // Clock inputs
        .CLKIN1   (clk_200mhz),
        .CLKFBIN  (mmcm_feedback_buf),

        // Clock outputs
        .CLKOUT0  (clk_100mhz_unbuf),
        .CLKOUT0B (),
        .CLKOUT1  (clk_pixel_unbuf),
        .CLKOUT1B (),
        .CLKOUT2  (),
        .CLKOUT2B (),
        .CLKOUT3  (),
        .CLKOUT3B (),
        .CLKOUT4  (),
        .CLKOUT5  (),
        .CLKOUT6  (),
        .CLKFBOUT (mmcm_feedback),
        .CLKFBOUTB(),

        // Control
        .LOCKED   (locked),
        .PWRDWN   (1'b0),
        .RST      (~rst_n)
    );

    //-------------------------------------------------------------------------
    // Output clock buffers
    //-------------------------------------------------------------------------
    BUFG bufg_feedback (
        .I (mmcm_feedback),
        .O (mmcm_feedback_buf)
    );

    BUFG bufg_clk_100mhz (
        .I (clk_100mhz_unbuf),
        .O (clk_100mhz)
    );

    BUFG bufg_clk_pixel (
        .I (clk_pixel_unbuf),
        .O (clk_pixel)
    );

endmodule
