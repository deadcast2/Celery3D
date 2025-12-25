// Celery3D GPU - Pixel Clock Generator
// Generates 25 MHz pixel clock from 50 MHz input using MMCM
// For simulation: uses simple clock divider
// For synthesis: uses MMCME2_ADV primitive

module pixel_clk_gen (
    input  logic        clk_50mhz,    // 50 MHz input clock
    input  logic        rst,          // Synchronous reset (active high)

    output logic        pixel_clk,    // 25 MHz pixel clock
    output logic        locked        // MMCM locked indicator
);

`ifdef SYNTHESIS
    // =========================================================================
    // Synthesis: Use MMCME2_ADV for Kintex-7
    // =========================================================================
    //
    // MMCM Configuration:
    //   Input:  50 MHz (CLKIN1)
    //   VCO:    50 * 20 = 1000 MHz (CLKFBOUT_MULT_F = 20.0)
    //   Output: 1000 / 40 = 25 MHz (CLKOUT0_DIVIDE_F = 40.0)

    logic clkfb;
    logic clk_out0;
    logic clk_out0_buf;

    MMCME2_ADV #(
        .BANDWIDTH            ("OPTIMIZED"),
        .CLKFBOUT_MULT_F      (20.0),       // VCO = 50 * 20 = 1000 MHz
        .CLKFBOUT_PHASE       (0.0),
        .CLKIN1_PERIOD        (20.0),       // 50 MHz = 20 ns period
        .CLKOUT0_DIVIDE_F     (40.0),       // 1000 / 40 = 25 MHz
        .CLKOUT0_DUTY_CYCLE   (0.5),
        .CLKOUT0_PHASE        (0.0),
        .DIVCLK_DIVIDE        (1),
        .REF_JITTER1          (0.01),
        .STARTUP_WAIT         ("FALSE")
    ) mmcm_inst (
        .CLKIN1      (clk_50mhz),
        .CLKIN2      (1'b0),
        .CLKINSEL    (1'b1),          // Select CLKIN1

        .CLKFBIN     (clkfb),
        .CLKFBOUT    (clkfb),
        .CLKFBOUTB   (),

        .CLKOUT0     (clk_out0),
        .CLKOUT0B    (),
        .CLKOUT1     (),
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

    // Buffer the output clock
    BUFG clkout_buf (
        .I (clk_out0),
        .O (clk_out0_buf)
    );

    assign pixel_clk = clk_out0_buf;

`else
    // =========================================================================
    // Simulation: Simple clock divider (divide by 2)
    // =========================================================================

    logic clk_div;
    logic locked_r;

    // Simple divide-by-2
    always_ff @(posedge clk_50mhz or posedge rst) begin
        if (rst) begin
            clk_div <= 1'b0;
        end else begin
            clk_div <= ~clk_div;
        end
    end

    // Simulate lock delay
    logic [7:0] lock_counter;

    always_ff @(posedge clk_50mhz or posedge rst) begin
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

    assign pixel_clk = clk_div;
    assign locked = locked_r;

`endif

endmodule
