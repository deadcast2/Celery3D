//-----------------------------------------------------------------------------
// adv7511_init.sv
// ADV7511 HDMI transmitter initialization
// Configures I2C mux and programs ADV7511 registers
//-----------------------------------------------------------------------------

module adv7511_init #(
    parameter CLK_FREQ_HZ = 100_000_000
)(
    input  wire       clk,
    input  wire       rst_n,

    // Control
    input  wire       start,
    output reg        done,
    output reg        error,

    // I2C mux reset
    output reg        i2c_mux_reset_n,

    // I2C master interface
    output reg        i2c_start,
    input  wire       i2c_done,
    input  wire       i2c_error,
    output reg  [6:0] i2c_slave_addr,
    output reg  [7:0] i2c_reg_addr,
    output reg        i2c_rw,
    output reg  [7:0] i2c_wdata
);

    // Addresses
    localparam I2C_MUX_ADDR = 7'h74;
    localparam ADV7511_ADDR = 7'h39;

    // Timing
    localparam WAIT_1MS   = CLK_FREQ_HZ / 1000;
    localparam WAIT_200MS = CLK_FREQ_HZ / 5;

    // Register table: {addr, data}
    localparam NUM_REGS = 15;
    wire [15:0] regs [0:NUM_REGS-1];

    // Fixed registers
    assign regs[0]  = {8'h98, 8'h03};
    assign regs[1]  = {8'h9A, 8'hE0};
    assign regs[2]  = {8'h9C, 8'h30};
    assign regs[3]  = {8'h9D, 8'h01};
    assign regs[4]  = {8'hA2, 8'hA4};
    assign regs[5]  = {8'hA3, 8'hA4};
    assign regs[6]  = {8'hE0, 8'hD0};
    assign regs[7]  = {8'hF9, 8'h00};
    // Video config
    assign regs[8]  = {8'h15, 8'h01};   // 16-bit YCbCr 4:2:2
    assign regs[9]  = {8'h16, 8'h08};   // Style 2
    assign regs[10] = {8'h17, 8'h00};   // Aspect 4:3
    assign regs[11] = {8'h18, 8'hC0};   // CSC enable
    assign regs[12] = {8'h48, 8'h08};   // Right justified
    assign regs[13] = {8'h57, 8'h04};   // Limited range
    assign regs[14] = {8'hAF, 8'h06};   // HDMI mode

    // State machine
    typedef enum logic [3:0] {
        IDLE,
        RELEASE_RST,
        WAIT_RST,
        CFG_MUX,
        WAIT_MUX,
        WAIT_ADV,
        POWER_UP,
        WAIT_PWR,
        WRITE_REG,
        WAIT_REG,
        DONE_ST,
        ERROR_ST
    } state_t;

    state_t state;
    reg [31:0] wait_cnt;
    reg [4:0]  reg_idx;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            wait_cnt <= 0;
            reg_idx <= 0;
            done <= 0;
            error <= 0;
            i2c_mux_reset_n <= 0;
            i2c_start <= 0;
            i2c_slave_addr <= 0;
            i2c_reg_addr <= 0;
            i2c_rw <= 0;
            i2c_wdata <= 0;
        end else begin
            i2c_start <= 0;

            case (state)
                IDLE: begin
                    done <= 0;
                    error <= 0;
                    i2c_mux_reset_n <= 0;
                    if (start) state <= RELEASE_RST;
                end

                RELEASE_RST: begin
                    i2c_mux_reset_n <= 1;
                    wait_cnt <= WAIT_1MS;
                    state <= WAIT_RST;
                end

                WAIT_RST: begin
                    if (wait_cnt == 0) state <= CFG_MUX;
                    else wait_cnt <= wait_cnt - 1;
                end

                CFG_MUX: begin
                    i2c_slave_addr <= I2C_MUX_ADDR;
                    i2c_reg_addr <= 8'h20;  // Select channel 5
                    i2c_wdata <= 8'h20;
                    i2c_rw <= 0;
                    i2c_start <= 1;
                    state <= WAIT_MUX;
                end

                WAIT_MUX: begin
                    if (i2c_done) begin
                        if (i2c_error) state <= ERROR_ST;
                        else begin
                            wait_cnt <= WAIT_200MS;
                            state <= WAIT_ADV;
                        end
                    end
                end

                WAIT_ADV: begin
                    if (wait_cnt == 0) state <= POWER_UP;
                    else wait_cnt <= wait_cnt - 1;
                end

                POWER_UP: begin
                    i2c_slave_addr <= ADV7511_ADDR;
                    i2c_reg_addr <= 8'h41;
                    i2c_wdata <= 8'h10;
                    i2c_rw <= 0;
                    i2c_start <= 1;
                    state <= WAIT_PWR;
                end

                WAIT_PWR: begin
                    if (i2c_done) begin
                        if (i2c_error) state <= ERROR_ST;
                        else begin
                            reg_idx <= 0;
                            state <= WRITE_REG;
                        end
                    end
                end

                WRITE_REG: begin
                    i2c_slave_addr <= ADV7511_ADDR;
                    i2c_reg_addr <= regs[reg_idx][15:8];
                    i2c_wdata <= regs[reg_idx][7:0];
                    i2c_rw <= 0;
                    i2c_start <= 1;
                    state <= WAIT_REG;
                end

                WAIT_REG: begin
                    if (i2c_done) begin
                        if (i2c_error) state <= ERROR_ST;
                        else if (reg_idx == NUM_REGS - 1) state <= DONE_ST;
                        else begin
                            reg_idx <= reg_idx + 1;
                            state <= WRITE_REG;
                        end
                    end
                end

                DONE_ST: begin
                    done <= 1;
                end

                ERROR_ST: begin
                    done <= 1;
                    error <= 1;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
