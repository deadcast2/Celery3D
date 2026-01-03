//-----------------------------------------------------------------------------
// i2c_master.sv
// Simple I2C master with register read/write interface
// Supports 100 kHz standard mode
//-----------------------------------------------------------------------------

module i2c_master #(
    parameter CLK_FREQ_HZ = 100_000_000,
    parameter I2C_FREQ_HZ = 100_000
)(
    input  wire       clk,
    input  wire       rst_n,

    // Register interface
    input  wire       start,            // Start transaction
    output reg        done,             // Transaction complete
    output reg        error,            // NACK received

    input  wire [6:0] slave_addr,       // I2C slave address
    input  wire [7:0] reg_addr,         // Register address
    input  wire       rw,               // 0=write, 1=read
    input  wire [7:0] wdata,            // Write data
    output reg  [7:0] rdata,            // Read data

    // I2C pins (directly active high use with IOBUF)
    output reg        scl_o,
    output reg        scl_oe,
    input  wire       scl_i,
    output reg        sda_o,
    output reg        sda_oe,
    input  wire       sda_i
);

    // Clock divider: 4 phases per bit period
    localparam QUARTER = CLK_FREQ_HZ / (I2C_FREQ_HZ * 4);
    localparam CNT_W = $clog2(QUARTER);

    // States
    typedef enum logic [3:0] {
        IDLE,
        START_1, START_2,           // START condition
        BIT_LO, BIT_HI,             // Data bit transfer
        ACK_LO, ACK_HI,             // ACK/NACK
        STOP_1, STOP_2              // STOP condition
    } state_t;

    state_t state;
    reg [CNT_W-1:0] cnt;
    reg [3:0] bit_idx;
    reg [7:0] shift;
    reg [2:0] byte_idx;             // Which byte: 0=addr_w, 1=reg, 2=data/addr_r, 3=rdata
    reg is_read;
    reg got_nack;

    // Byte to send based on byte_idx
    wire [7:0] tx_byte = (byte_idx == 0) ? {slave_addr, 1'b0} :      // Addr + Write
                         (byte_idx == 1) ? reg_addr :                 // Register
                         (byte_idx == 2 && is_read) ? {slave_addr, 1'b1} : // Addr + Read
                         wdata;                                       // Write data

    // Counter done
    wire cnt_done = (cnt == QUARTER - 1);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            cnt <= '0;
            bit_idx <= 4'd0;
            shift <= 8'd0;
            byte_idx <= 3'd0;
            is_read <= 1'b0;
            got_nack <= 1'b0;
            done <= 1'b0;
            error <= 1'b0;
            rdata <= 8'd0;
            scl_o <= 1'b1;
            scl_oe <= 1'b0;
            sda_o <= 1'b1;
            sda_oe <= 1'b0;
        end else begin
            done <= 1'b0;
            error <= 1'b0;
            cnt <= cnt + 1'b1;

            case (state)
                IDLE: begin
                    cnt <= '0;
                    scl_oe <= 1'b0;
                    sda_oe <= 1'b0;
                    if (start) begin
                        state <= START_1;
                        byte_idx <= 3'd0;
                        is_read <= rw;
                        got_nack <= 1'b0;
                        shift <= {slave_addr, 1'b0};
                    end
                end

                // START: SDA falls while SCL high
                START_1: begin
                    sda_oe <= 1'b1; sda_o <= 1'b0;  // SDA low
                    if (cnt_done) begin
                        state <= START_2;
                        cnt <= '0;
                    end
                end
                START_2: begin
                    scl_oe <= 1'b1; scl_o <= 1'b0;  // SCL low
                    if (cnt_done) begin
                        state <= BIT_LO;
                        cnt <= '0;
                        bit_idx <= 4'd7;
                        shift <= tx_byte;
                    end
                end

                // Transmit/receive bit: SCL low, setup SDA
                BIT_LO: begin
                    scl_oe <= 1'b1; scl_o <= 1'b0;
                    // Drive SDA for write, release for read (byte 3)
                    if (byte_idx == 3 && is_read) begin
                        sda_oe <= 1'b0;  // Release for read
                    end else begin
                        sda_oe <= 1'b1;
                        sda_o <= shift[7];
                    end
                    if (cnt_done) begin
                        state <= BIT_HI;
                        cnt <= '0;
                    end
                end

                // SCL high, sample/hold
                BIT_HI: begin
                    scl_oe <= 1'b0;  // Release SCL (goes high)
                    if (cnt_done && scl_i) begin
                        // Sample on read
                        if (byte_idx == 3 && is_read) begin
                            shift <= {shift[6:0], sda_i};
                        end
                        if (bit_idx == 0) begin
                            state <= ACK_LO;
                        end else begin
                            bit_idx <= bit_idx - 1'b1;
                            state <= BIT_LO;
                        end
                        cnt <= '0;
                    end
                end

                // ACK: SCL low, setup ACK
                ACK_LO: begin
                    scl_oe <= 1'b1; scl_o <= 1'b0;
                    if (byte_idx == 3 && is_read) begin
                        // Master sends NACK on last read byte
                        sda_oe <= 1'b1; sda_o <= 1'b1;
                    end else begin
                        // Release SDA to receive ACK from slave
                        sda_oe <= 1'b0;
                    end
                    if (cnt_done) begin
                        state <= ACK_HI;
                        cnt <= '0;
                    end
                end

                // ACK: SCL high, sample ACK
                ACK_HI: begin
                    scl_oe <= 1'b0;
                    if (cnt_done && scl_i) begin
                        // Check for NACK (SDA high = NACK)
                        if (!(byte_idx == 3 && is_read) && sda_i) begin
                            got_nack <= 1'b1;
                        end
                        // Save read data
                        if (byte_idx == 3 && is_read) begin
                            rdata <= shift;
                        end
                        cnt <= '0;

                        // Next byte or stop?
                        if (got_nack || sda_i && !(byte_idx == 3 && is_read)) begin
                            // NACK - go to stop
                            state <= STOP_1;
                            scl_oe <= 1'b1; scl_o <= 1'b0;
                            sda_oe <= 1'b1; sda_o <= 1'b0;
                        end else if (byte_idx == 1 && is_read) begin
                            // After reg addr, restart for read
                            byte_idx <= 3'd2;
                            state <= START_1;
                            scl_oe <= 1'b0;
                            sda_oe <= 1'b0;
                        end else if ((byte_idx == 2 && !is_read) || (byte_idx == 3)) begin
                            // Done - go to stop
                            state <= STOP_1;
                            scl_oe <= 1'b1; scl_o <= 1'b0;
                            sda_oe <= 1'b1; sda_o <= 1'b0;
                        end else begin
                            // Next byte
                            byte_idx <= byte_idx + 1'b1;
                            bit_idx <= 4'd7;
                            shift <= (byte_idx == 0) ? reg_addr :
                                     (byte_idx == 1 && is_read) ? {slave_addr, 1'b1} :
                                     wdata;
                            state <= BIT_LO;
                        end
                    end
                end

                // STOP: SCL rises, then SDA rises
                STOP_1: begin
                    scl_oe <= 1'b0;  // SCL high
                    sda_oe <= 1'b1; sda_o <= 1'b0;  // SDA low
                    if (cnt_done) begin
                        state <= STOP_2;
                        cnt <= '0;
                    end
                end
                STOP_2: begin
                    sda_oe <= 1'b0;  // SDA high (stop)
                    if (cnt_done) begin
                        state <= IDLE;
                        done <= 1'b1;
                        error <= got_nack;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
