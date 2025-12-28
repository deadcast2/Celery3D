// Video Clock Generator from MIG ui_clk
// Generates 50 MHz and 25 MHz clocks from MIG's ui_clk (~100 MHz)
// Used when DDR3 MIG is handling the main 200MHz clock input

module video_clk_from_mig (
    // MIG ui_clk input (typically 100 MHz from MIG)
    input  logic        ui_clk,
    input  logic        ui_rst,       // MIG reset (active high)

    output logic        clk_50mhz,    // 50 MHz system clock
    output logic        clk_25mhz,    // 25 MHz pixel clock
    output logic        locked        // PLL locked indicator
);

`ifdef SYNTHESIS
    // =========================================================================
    // Synthesis: MMCME2_ADV for Kintex-7
    // =========================================================================
    //
    // MMCM Configuration (assuming 100 MHz ui_clk input):
    //   Input:  100 MHz (CLKIN1)
    //   VCO:    100 * 10 = 1000 MHz (CLKFBOUT_MULT_F = 10.0)
    //   CLKOUT0: 1000 / 40 = 25 MHz (pixel clock)
    //   CLKOUT1: 1000 / 20 = 50 MHz (system clock)

    logic clkfb;
    logic clk_out0, clk_out1;
    logic clk_out0_buf, clk_out1_buf;

    MMCME2_ADV #(
        .BANDWIDTH            ("OPTIMIZED"),
        .CLKFBOUT_MULT_F      (10.0),       // VCO = 100 * 10 = 1000 MHz
        .CLKFBOUT_PHASE       (0.0),
        .CLKIN1_PERIOD        (10.0),       // 100 MHz = 10 ns period
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
        .CLKIN1      (ui_clk),
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
        .RST         (ui_rst),

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
    BUFG clkout0_buf_inst (
        .I (clk_out0),
        .O (clk_out0_buf)
    );

    BUFG clkout1_buf_inst (
        .I (clk_out1),
        .O (clk_out1_buf)
    );

    assign clk_25mhz = clk_out0_buf;
    assign clk_50mhz = clk_out1_buf;

`else
    // =========================================================================
    // Simulation: Simple clock dividers from 100 MHz
    // =========================================================================

    logic [1:0] div_cnt;
    logic locked_r;
    logic [7:0] lock_counter;

    // Generate 50 MHz (divide by 2) and 25 MHz (divide by 4)
    always_ff @(posedge ui_clk or posedge ui_rst) begin
        if (ui_rst) begin
            div_cnt <= '0;
        end else begin
            div_cnt <= div_cnt + 1'b1;
        end
    end

    assign clk_50mhz = div_cnt[0];  // 100/2 = 50 MHz
    assign clk_25mhz = div_cnt[1];  // 100/4 = 25 MHz

    // Simulate lock delay
    always_ff @(posedge ui_clk or posedge ui_rst) begin
        if (ui_rst) begin
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
