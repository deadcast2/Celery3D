// Celery3D GPU - ADV7511 HDMI Transmitter Initialization
// ROM-based I2C configuration sequence for ADV7511
// Configures for 16-bit YCbCr 4:2:2 input with separate syncs

module adv7511_init
    import video_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // Control
    input  logic        start,        // Pulse to begin initialization
    output logic        done,         // High when initialization complete
    output logic        error,        // High if I2C error occurred

    // I2C master interface
    output logic [6:0]  i2c_slave_addr,
    output logic [7:0]  i2c_reg_addr,
    output logic [7:0]  i2c_write_data,
    output logic        i2c_write_req,
    output logic        i2c_single_byte,  // For PCA9548 mux (no register address)
    input  logic        i2c_busy,
    input  logic        i2c_done,
    input  logic        i2c_ack_error
);

    // =========================================================================
    // Configuration ROM
    // Each entry: {slave_addr[6:0], is_mux, reg_addr[7:0], data[7:0]}
    // For mux writes: reg_addr is ignored, data selects channel
    // =========================================================================

    // I2C addresses
    localparam [6:0] PCA9548_I2C_ADDR = 7'h74;  // I2C mux address

    // Number of registers to program (including mux config)
    localparam REG_COUNT = 22;

    // ROM containing configuration entries
    // Format: {slave_addr[6:0], is_mux_write, reg_addr[7:0], data[7:0]}
    logic [23:0] config_rom [0:REG_COUNT-1];

    initial begin
        // First: Configure I2C mux to select channel 5 (ADV7511)
        // PCA9548: write channel mask directly (no register address)
        // Channel 5 = bit 5 = 0x20
        config_rom[0]  = {PCA9548_I2C_ADDR, 1'b1, 8'h00, 8'h20};  // Select mux ch5

        // Now configure ADV7511 (all remaining entries use ADV7511 address)
        // Power and HPD control
        config_rom[1]  = {ADV7511_I2C_ADDR, 1'b0, 8'h41, 8'h10};  // Power up
        config_rom[2]  = {ADV7511_I2C_ADDR, 1'b0, 8'hD6, 8'hC0};  // HPD: always hot plug

        // Input video format - YCbCr 4:2:2 mode (required for KC705 16-bit wiring)
        // 0x15: Input ID register
        //   [3:0] = Input ID: 1 = 16-bit YCbCr 4:2:2
        config_rom[3]  = {ADV7511_I2C_ADDR, 1'b0, 8'h15, 8'h01};

        // 0x16: Input/Output format
        //   [0]   = Output colorspace: 0 = RGB
        //   [2:1] = Input color depth: 00 = 8-bit
        //   [4:3] = Input style: 01 = style 1
        //   [5]   = DDR input: 0 = SDR
        //   [7:6] = Output color depth: 00 = 8-bit
        config_rom[4]  = {ADV7511_I2C_ADDR, 1'b0, 8'h16, 8'h08};

        // 0x17: Aspect ratio and sync
        //   [1]   = Aspect ratio: 0 = 4:3
        //   [7]   = External DE: 1 = use input DE
        config_rom[5]  = {ADV7511_I2C_ADDR, 1'b0, 8'h17, 8'h02};

        // 0x18: CSC enable + scaling for YCbCr to RGB conversion
        //   [7]   = CSC enable: 1 = enable
        //   [6:5] = CSC scaling: 10 = higher scaling
        config_rom[6]  = {ADV7511_I2C_ADDR, 1'b0, 8'h18, 8'hC0};

        // 0x48: Video input justification
        config_rom[7]  = {ADV7511_I2C_ADDR, 1'b0, 8'h48, 8'h08};

        // 0x49: Bit trimming
        config_rom[8]  = {ADV7511_I2C_ADDR, 1'b0, 8'h49, 8'hA8};

        // 0x4C: GC packet enable
        config_rom[9]  = {ADV7511_I2C_ADDR, 1'b0, 8'h4C, 8'h00};

        // 0x55: AVI InfoFrame Y1Y0 (output color space)
        config_rom[10] = {ADV7511_I2C_ADDR, 1'b0, 8'h55, 8'h00};

        // 0x56: AVI InfoFrame aspect ratio
        config_rom[11] = {ADV7511_I2C_ADDR, 1'b0, 8'h56, 8'h08};

        // 0x57: AVI InfoFrame quantization range
        //   [3:2] = Q1Q0: 00=default, 01=limited range, 10=full range
        //   Set to 01 (limited) so monitor expands 16-235 to full display range
        config_rom[12] = {ADV7511_I2C_ADDR, 1'b0, 8'h57, 8'h04};

        // Fixed registers (required per ADV7511 programming guide)
        config_rom[13] = {ADV7511_I2C_ADDR, 1'b0, 8'h98, 8'h03};
        config_rom[14] = {ADV7511_I2C_ADDR, 1'b0, 8'h99, 8'h02};
        config_rom[15] = {ADV7511_I2C_ADDR, 1'b0, 8'h9A, 8'hE0};
        config_rom[16] = {ADV7511_I2C_ADDR, 1'b0, 8'h9C, 8'h30};
        config_rom[17] = {ADV7511_I2C_ADDR, 1'b0, 8'h9D, 8'h01};  // HDMI mode
        config_rom[18] = {ADV7511_I2C_ADDR, 1'b0, 8'hA2, 8'hA4};
        config_rom[19] = {ADV7511_I2C_ADDR, 1'b0, 8'hA3, 8'hA4};
        config_rom[20] = {ADV7511_I2C_ADDR, 1'b0, 8'hE0, 8'hD0};
        config_rom[21] = {ADV7511_I2C_ADDR, 1'b0, 8'hF9, 8'h00};
    end

    // =========================================================================
    // State Machine
    // =========================================================================

    typedef enum logic [2:0] {
        IDLE,
        START_DELAY,    // Brief delay after start
        SEND_REG,       // Issue I2C write request
        WAIT_BUSY,      // Wait for I2C to become busy
        WAIT_DONE,      // Wait for I2C transaction to complete
        NEXT_REG,       // Move to next register
        DONE_STATE,
        ERROR_STATE
    } state_t;

    state_t state;
    logic [$clog2(REG_COUNT)-1:0] reg_index;
    logic [23:0] current_entry;

    // Delay counter for settling time between registers
    logic [7:0] delay_count;

    // Extract fields from current ROM entry
    // Format: {slave_addr[6:0], is_mux_write, reg_addr[7:0], data[7:0]}
    assign current_entry = config_rom[reg_index];
    assign i2c_slave_addr = current_entry[23:17];
    assign i2c_single_byte = current_entry[16];     // is_mux_write flag
    assign i2c_reg_addr = current_entry[15:8];
    assign i2c_write_data = current_entry[7:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            reg_index <= '0;
            delay_count <= '0;
            i2c_write_req <= 1'b0;
            done <= 1'b0;
            error <= 1'b0;
        end else begin
            // Default: clear write request after one cycle
            i2c_write_req <= 1'b0;

            case (state)
                IDLE: begin
                    done <= 1'b0;
                    error <= 1'b0;
                    reg_index <= '0;

                    if (start) begin
                        delay_count <= 8'd255;  // Initial delay
                        state <= START_DELAY;
                    end
                end

                START_DELAY: begin
                    if (delay_count == 0) begin
                        state <= SEND_REG;
                    end else begin
                        delay_count <= delay_count - 1'b1;
                    end
                end

                SEND_REG: begin
                    if (!i2c_busy) begin
                        i2c_write_req <= 1'b1;
                        state <= WAIT_BUSY;
                    end
                end

                WAIT_BUSY: begin
                    // Wait for I2C master to acknowledge the request
                    if (i2c_busy) begin
                        state <= WAIT_DONE;
                    end
                end

                WAIT_DONE: begin
                    if (i2c_done) begin
                        if (i2c_ack_error) begin
                            // I2C NAK - error
                            error <= 1'b1;
                            state <= ERROR_STATE;
                        end else begin
                            // Success - move to next register
                            state <= NEXT_REG;
                            delay_count <= 8'd50;  // Brief delay between writes
                        end
                    end
                end

                NEXT_REG: begin
                    if (delay_count == 0) begin
                        if (reg_index == REG_COUNT - 1) begin
                            // All registers programmed
                            done <= 1'b1;
                            state <= DONE_STATE;
                        end else begin
                            reg_index <= reg_index + 1'b1;
                            state <= SEND_REG;
                        end
                    end else begin
                        delay_count <= delay_count - 1'b1;
                    end
                end

                DONE_STATE: begin
                    // Stay in done state
                    done <= 1'b1;
                end

                ERROR_STATE: begin
                    // Stay in error state until reset
                    error <= 1'b1;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
