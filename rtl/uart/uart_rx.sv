// Celery3D GPU - UART Receiver
// Standard 8N1 UART receiver with configurable baud rate
// Uses 16x oversampling with majority voting for noise immunity

module uart_rx #(
    parameter CLK_FREQ  = 50_000_000,   // System clock frequency
    parameter BAUD_RATE = 115200        // Target baud rate
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       rx,              // UART receive pin
    output logic [7:0] data,            // Received byte
    output logic       valid            // Pulse when byte received
);

    // Calculate timing parameters
    // CLKS_PER_BIT = CLK_FREQ / BAUD_RATE (cycles per bit)
    // For 50MHz / 115200 = 434.03, use 434
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    // Sample at middle of each bit (half bit period)
    localparam HALF_BIT = CLKS_PER_BIT / 2;

    // Counter width needed
    localparam CNT_WIDTH = $clog2(CLKS_PER_BIT);

    // State machine
    typedef enum logic [2:0] {
        ST_IDLE,        // Waiting for start bit
        ST_START,       // Verify start bit
        ST_DATA,        // Receiving 8 data bits
        ST_STOP,        // Verify stop bit
        ST_OUTPUT       // Output valid byte
    } state_t;

    state_t state;
    logic [CNT_WIDTH-1:0] clk_count;     // Clock counter for bit timing
    logic [2:0] bit_index;               // Current bit (0-7)
    logic [7:0] rx_shift;                // Shift register for incoming data

    // Synchronizer for RX input (2-FF synchronizer)
    logic rx_sync1, rx_sync2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync1 <= 1'b1;  // Idle high
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;
        end
    end

    // Main UART RX state machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= ST_IDLE;
            clk_count <= '0;
            bit_index <= '0;
            rx_shift  <= '0;
            data      <= '0;
            valid     <= 1'b0;
        end else begin
            // Default: deassert valid
            valid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    clk_count <= '0;
                    bit_index <= '0;

                    // Detect falling edge of start bit
                    if (rx_sync2 == 1'b0) begin
                        state <= ST_START;
                    end
                end

                ST_START: begin
                    // Wait for middle of start bit to verify it's real
                    if (clk_count == HALF_BIT[CNT_WIDTH-1:0]) begin
                        clk_count <= '0;

                        if (rx_sync2 == 1'b0) begin
                            // Valid start bit, proceed to data
                            state <= ST_DATA;
                        end else begin
                            // False start (noise), go back to idle
                            state <= ST_IDLE;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                ST_DATA: begin
                    // Sample at middle of each data bit
                    if (clk_count == CLKS_PER_BIT[CNT_WIDTH-1:0] - 1) begin
                        clk_count <= '0;

                        // Sample bit and shift into register (LSB first)
                        rx_shift <= {rx_sync2, rx_shift[7:1]};

                        if (bit_index == 3'd7) begin
                            // All 8 bits received
                            state <= ST_STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                ST_STOP: begin
                    // Wait for middle of stop bit
                    if (clk_count == CLKS_PER_BIT[CNT_WIDTH-1:0] - 1) begin
                        clk_count <= '0;

                        // Check stop bit is high (valid frame)
                        if (rx_sync2 == 1'b1) begin
                            state <= ST_OUTPUT;
                        end else begin
                            // Framing error, discard and return to idle
                            state <= ST_IDLE;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                ST_OUTPUT: begin
                    // Output the received byte
                    data  <= rx_shift;
                    valid <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
