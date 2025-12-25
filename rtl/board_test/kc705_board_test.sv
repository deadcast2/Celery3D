// KC705 Board Test - LED Blink
// Simple test to verify the board is working and we can upload a bitstream
// Uses 200 MHz differential clock and 8 GPIO LEDs

module kc705_board_test (
    // 200 MHz differential system clock
    input  logic sysclk_p,
    input  logic sysclk_n,

    // 8 GPIO LEDs (directly active-high from FPGA)
    output logic [7:0] gpio_led
);

    // Internal signals
    logic clk_200mhz;
    logic [27:0] counter;  // 28-bit counter for visible blink rate

    // Differential clock buffer
    // IBUFGDS converts differential LVDS to single-ended
    IBUFGDS #(
        .DIFF_TERM("FALSE"),
        .IBUF_LOW_PWR("FALSE"),
        .IOSTANDARD("LVDS")
    ) ibufgds_sysclk (
        .O(clk_200mhz),
        .I(sysclk_p),
        .IB(sysclk_n)
    );

    // Simple counter - no reset needed, will start from random state
    // At 200 MHz, counter[27] toggles every ~0.67 seconds
    // counter[24] toggles every ~84ms (good for walking LED)
    always_ff @(posedge clk_200mhz) begin
        counter <= counter + 1'b1;
    end

    // LED pattern: Walking LED using upper counter bits
    // Bits [26:24] select which LED is lit (cycles through 0-7)
    // Bit [27] controls overall blink of the walking LED
    logic [2:0] led_select;
    assign led_select = counter[26:24];

    always_comb begin
        gpio_led = 8'b0;
        if (counter[27]) begin
            // Walking LED pattern
            gpio_led[led_select] = 1'b1;
        end else begin
            // Binary counter display on LEDs
            gpio_led = counter[27:20];
        end
    end

endmodule
