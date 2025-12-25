// Celery3D GPU - I2C Master Controller
// Simple byte-oriented I2C master for ADV7511 configuration
// Supports single-byte register writes only (sufficient for ADV7511 init)
// I2C clock: ~100 kHz from 50 MHz input (divide by 500)

module i2c_master #(
    parameter CLK_DIV = 125   // 50 MHz / 125 / 4 = 100 kHz I2C clock
)(
    input  logic        clk,
    input  logic        rst_n,

    // Command interface
    input  logic [6:0]  slave_addr,   // 7-bit I2C slave address
    input  logic [7:0]  reg_addr,     // Register address to write
    input  logic [7:0]  write_data,   // Data to write
    input  logic        write_req,    // Pulse to start write transaction
    input  logic        single_byte,  // If 1, skip reg_addr (for PCA9548 mux)
    output logic        busy,         // Transaction in progress
    output logic        done,         // Transaction complete (1 cycle pulse)
    output logic        ack_error,    // NAK received

    // I2C signals (directly to FPGA pins)
    output logic        scl_o,        // SCL output (directly for open-drain emulation)
    output logic        scl_oen,      // SCL output enable (directly for open-drain emulation)
    input  logic        scl_i,        // SCL input (for clock stretching)
    output logic        sda_o,        // SDA output
    output logic        sda_oen,      // SDA output enable
    input  logic        sda_i         // SDA input
);

    // =========================================================================
    // Clock Divider for I2C timing
    // =========================================================================

    // I2C clock has 4 phases per bit:
    //   Phase 0: SCL low, setup SDA
    //   Phase 1: SCL rising edge
    //   Phase 2: SCL high, sample SDA (for ACK)
    //   Phase 3: SCL falling edge

    logic [$clog2(CLK_DIV)-1:0] clk_count;
    logic [1:0] phase;
    logic phase_tick;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_count <= '0;
            phase_tick <= 1'b0;
        end else begin
            if (clk_count == CLK_DIV - 1) begin
                clk_count <= '0;
                phase_tick <= 1'b1;
            end else begin
                clk_count <= clk_count + 1'b1;
                phase_tick <= 1'b0;
            end
        end
    end

    // =========================================================================
    // State Machine
    // =========================================================================

    typedef enum logic [3:0] {
        IDLE,
        START_SETUP,      // SDA goes low while SCL high (START condition)
        START_HOLD,       // Hold START, then SCL goes low
        SEND_ADDR,        // Send 7-bit address + W bit
        ADDR_ACK,         // Wait for ACK after address
        SEND_REG,         // Send register address byte
        REG_ACK,          // Wait for ACK after register
        SEND_DATA,        // Send data byte
        DATA_ACK,         // Wait for ACK after data
        STOP_SETUP,       // SCL goes high while SDA low
        STOP_HOLD,        // SDA goes high while SCL high (STOP condition)
        DONE_STATE
    } state_t;

    state_t state;
    logic [2:0] bit_count;     // 0-7 for 8 bits
    logic [7:0] shift_reg;     // Shift register for current byte
    logic ack_bit;             // Captured ACK bit

    // Registered inputs
    logic [6:0] slave_addr_r;
    logic [7:0] reg_addr_r;
    logic [7:0] write_data_r;
    logic       single_byte_r;

    // SCL and SDA control
    logic scl_out;
    logic sda_out;

    // Open-drain: output 0 to pull low, release (oen=1) to float high
    assign scl_o = 1'b0;
    assign scl_oen = scl_out;  // 1 = release (high-Z), 0 = drive low
    assign sda_o = 1'b0;
    assign sda_oen = sda_out;  // 1 = release (high-Z), 0 = drive low

    // =========================================================================
    // Main State Machine
    // =========================================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            bit_count <= '0;
            shift_reg <= '0;
            scl_out <= 1'b1;  // Released (high)
            sda_out <= 1'b1;  // Released (high)
            phase <= '0;
            slave_addr_r <= '0;
            reg_addr_r <= '0;
            write_data_r <= '0;
            single_byte_r <= 1'b0;
            ack_bit <= 1'b1;
            busy <= 1'b0;
            done <= 1'b0;
            ack_error <= 1'b0;
        end else begin
            done <= 1'b0;  // Default: done is a pulse

            case (state)
                IDLE: begin
                    scl_out <= 1'b1;
                    sda_out <= 1'b1;
                    busy <= 1'b0;
                    ack_error <= 1'b0;

                    if (write_req) begin
                        slave_addr_r <= slave_addr;
                        reg_addr_r <= reg_addr;
                        write_data_r <= write_data;
                        single_byte_r <= single_byte;
                        busy <= 1'b1;
                        state <= START_SETUP;
                    end
                end

                START_SETUP: begin
                    // START condition: SDA goes low while SCL is high
                    if (phase_tick) begin
                        sda_out <= 1'b0;  // Pull SDA low
                        state <= START_HOLD;
                    end
                end

                START_HOLD: begin
                    // Hold for one phase, then pull SCL low
                    if (phase_tick) begin
                        scl_out <= 1'b0;  // Pull SCL low
                        // Prepare first byte: 7-bit address + W (0)
                        shift_reg <= {slave_addr_r, 1'b0};
                        bit_count <= 3'd7;
                        phase <= 2'd0;
                        state <= SEND_ADDR;
                    end
                end

                SEND_ADDR: begin
                    if (phase_tick) begin
                        case (phase)
                            2'd0: begin
                                // Setup SDA with current bit
                                sda_out <= shift_reg[7];
                                phase <= 2'd1;
                            end
                            2'd1: begin
                                // Rising edge of SCL
                                scl_out <= 1'b1;
                                phase <= 2'd2;
                            end
                            2'd2: begin
                                // SCL high - data stable
                                phase <= 2'd3;
                            end
                            2'd3: begin
                                // Falling edge of SCL
                                scl_out <= 1'b0;
                                shift_reg <= {shift_reg[6:0], 1'b0};

                                if (bit_count == 0) begin
                                    // All 8 bits sent, wait for ACK
                                    sda_out <= 1'b1;  // Release SDA for ACK
                                    phase <= 2'd0;
                                    state <= ADDR_ACK;
                                end else begin
                                    bit_count <= bit_count - 1'b1;
                                    phase <= 2'd0;
                                end
                            end
                        endcase
                    end
                end

                ADDR_ACK: begin
                    if (phase_tick) begin
                        case (phase)
                            2'd0: begin
                                // SDA released, prepare for ACK
                                phase <= 2'd1;
                            end
                            2'd1: begin
                                // Rising edge of SCL
                                scl_out <= 1'b1;
                                phase <= 2'd2;
                            end
                            2'd2: begin
                                // Sample ACK (SDA should be low for ACK)
                                ack_bit <= sda_i;
                                phase <= 2'd3;
                            end
                            2'd3: begin
                                // Falling edge of SCL
                                scl_out <= 1'b0;

                                if (ack_bit) begin
                                    // NAK received - abort
                                    ack_error <= 1'b1;
                                    state <= STOP_SETUP;
                                end else if (single_byte_r) begin
                                    // Single-byte mode (PCA9548): skip reg addr, send data directly
                                    shift_reg <= write_data_r;
                                    bit_count <= 3'd7;
                                    phase <= 2'd0;
                                    state <= SEND_DATA;
                                end else begin
                                    // Normal mode: send register address
                                    shift_reg <= reg_addr_r;
                                    bit_count <= 3'd7;
                                    phase <= 2'd0;
                                    state <= SEND_REG;
                                end
                            end
                        endcase
                    end
                end

                SEND_REG: begin
                    if (phase_tick) begin
                        case (phase)
                            2'd0: begin
                                sda_out <= shift_reg[7];
                                phase <= 2'd1;
                            end
                            2'd1: begin
                                scl_out <= 1'b1;
                                phase <= 2'd2;
                            end
                            2'd2: begin
                                phase <= 2'd3;
                            end
                            2'd3: begin
                                scl_out <= 1'b0;
                                shift_reg <= {shift_reg[6:0], 1'b0};

                                if (bit_count == 0) begin
                                    sda_out <= 1'b1;
                                    phase <= 2'd0;
                                    state <= REG_ACK;
                                end else begin
                                    bit_count <= bit_count - 1'b1;
                                    phase <= 2'd0;
                                end
                            end
                        endcase
                    end
                end

                REG_ACK: begin
                    if (phase_tick) begin
                        case (phase)
                            2'd0: phase <= 2'd1;
                            2'd1: begin
                                scl_out <= 1'b1;
                                phase <= 2'd2;
                            end
                            2'd2: begin
                                ack_bit <= sda_i;
                                phase <= 2'd3;
                            end
                            2'd3: begin
                                scl_out <= 1'b0;

                                if (ack_bit) begin
                                    ack_error <= 1'b1;
                                    state <= STOP_SETUP;
                                end else begin
                                    shift_reg <= write_data_r;
                                    bit_count <= 3'd7;
                                    phase <= 2'd0;
                                    state <= SEND_DATA;
                                end
                            end
                        endcase
                    end
                end

                SEND_DATA: begin
                    if (phase_tick) begin
                        case (phase)
                            2'd0: begin
                                sda_out <= shift_reg[7];
                                phase <= 2'd1;
                            end
                            2'd1: begin
                                scl_out <= 1'b1;
                                phase <= 2'd2;
                            end
                            2'd2: begin
                                phase <= 2'd3;
                            end
                            2'd3: begin
                                scl_out <= 1'b0;
                                shift_reg <= {shift_reg[6:0], 1'b0};

                                if (bit_count == 0) begin
                                    sda_out <= 1'b1;
                                    phase <= 2'd0;
                                    state <= DATA_ACK;
                                end else begin
                                    bit_count <= bit_count - 1'b1;
                                    phase <= 2'd0;
                                end
                            end
                        endcase
                    end
                end

                DATA_ACK: begin
                    if (phase_tick) begin
                        case (phase)
                            2'd0: phase <= 2'd1;
                            2'd1: begin
                                scl_out <= 1'b1;
                                phase <= 2'd2;
                            end
                            2'd2: begin
                                ack_bit <= sda_i;
                                phase <= 2'd3;
                            end
                            2'd3: begin
                                scl_out <= 1'b0;

                                if (ack_bit) begin
                                    ack_error <= 1'b1;
                                end
                                // Generate STOP regardless
                                sda_out <= 1'b0;  // Ensure SDA low for STOP
                                phase <= 2'd0;
                                state <= STOP_SETUP;
                            end
                        endcase
                    end
                end

                STOP_SETUP: begin
                    // STOP: SCL goes high while SDA is low
                    if (phase_tick) begin
                        scl_out <= 1'b1;  // Release SCL (goes high)
                        state <= STOP_HOLD;
                    end
                end

                STOP_HOLD: begin
                    // Then SDA goes high (STOP condition)
                    if (phase_tick) begin
                        sda_out <= 1'b1;  // Release SDA (goes high)
                        state <= DONE_STATE;
                    end
                end

                DONE_STATE: begin
                    if (phase_tick) begin
                        done <= 1'b1;
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
