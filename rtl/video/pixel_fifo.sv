// Pixel FIFO - Async FIFO for pixel data between rasterizer and DDR3
// Handles clock domain crossing between rasterizer clock and DDR ui_clk
// Stores (x, y, color) tuples

module pixel_fifo #(
    parameter DEPTH = 256,  // Number of entries (power of 2)
    parameter ADDR_W = $clog2(DEPTH)
)(
    // Write side (rasterizer clock domain)
    input  logic        wr_clk,
    input  logic        wr_rst_n,
    input  logic [9:0]  wr_x,
    input  logic [9:0]  wr_y,
    input  logic [15:0] wr_color,
    input  logic        wr_valid,
    output logic        wr_ready,

    // Read side (DDR clock domain)
    input  logic        rd_clk,
    input  logic        rd_rst_n,
    output logic [9:0]  rd_x,
    output logic [9:0]  rd_y,
    output logic [15:0] rd_color,
    output logic        rd_valid,
    input  logic        rd_ready,

    // Status (approximate, for debugging)
    output logic [ADDR_W:0] fill_level  // In write clock domain
);

    // Data width: 10 + 10 + 16 = 36 bits
    localparam DATA_W = 36;

    // Memory
    logic [DATA_W-1:0] mem [0:DEPTH-1];

    // Write pointer (gray code for CDC)
    logic [ADDR_W:0] wr_ptr;       // Binary write pointer (extra bit for full/empty)
    logic [ADDR_W:0] wr_ptr_gray;  // Gray code version
    logic [ADDR_W:0] rd_ptr_gray_sync;  // Read pointer synced to write domain

    // Read pointer (gray code for CDC)
    logic [ADDR_W:0] rd_ptr;       // Binary read pointer
    logic [ADDR_W:0] rd_ptr_gray;  // Gray code version
    logic [ADDR_W:0] wr_ptr_gray_sync;  // Write pointer synced to read domain

    // Binary to Gray conversion
    function automatic logic [ADDR_W:0] bin2gray(input logic [ADDR_W:0] bin);
        return bin ^ (bin >> 1);
    endfunction

    // Gray to Binary conversion
    function automatic logic [ADDR_W:0] gray2bin(input logic [ADDR_W:0] gray);
        logic [ADDR_W:0] bin;
        bin[ADDR_W] = gray[ADDR_W];
        for (int i = ADDR_W-1; i >= 0; i--) begin
            bin[i] = bin[i+1] ^ gray[i];
        end
        return bin;
    endfunction

    // Pack/unpack data
    logic [DATA_W-1:0] wr_data;
    logic [DATA_W-1:0] rd_data;

    assign wr_data = {wr_x, wr_y, wr_color};
    assign {rd_x, rd_y, rd_color} = rd_data;

    // =========================================================================
    // Write Side Logic (wr_clk domain)
    // =========================================================================

    // Synchronize read pointer to write domain (2-stage sync)
    logic [ADDR_W:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_ptr_gray_sync1 <= '0;
            rd_ptr_gray_sync2 <= '0;
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end
    assign rd_ptr_gray_sync = rd_ptr_gray_sync2;

    // Full detection (in write domain)
    logic [ADDR_W:0] rd_ptr_sync_bin;
    assign rd_ptr_sync_bin = gray2bin(rd_ptr_gray_sync);

    logic full;
    // Full when write pointer is one lap ahead of read pointer
    assign full = (wr_ptr[ADDR_W] != rd_ptr_sync_bin[ADDR_W]) &&
                  (wr_ptr[ADDR_W-1:0] == rd_ptr_sync_bin[ADDR_W-1:0]);

    assign wr_ready = !full;

    // Write pointer update
    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr <= '0;
        end else if (wr_valid && wr_ready) begin
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    // Gray code write pointer
    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr_gray <= '0;
        end else begin
            wr_ptr_gray <= bin2gray(wr_ptr + (wr_valid && wr_ready ? 1'b1 : 1'b0));
        end
    end

    // Memory write
    always_ff @(posedge wr_clk) begin
        if (wr_valid && wr_ready) begin
            mem[wr_ptr[ADDR_W-1:0]] <= wr_data;
        end
    end

    // Fill level (approximate)
    assign fill_level = wr_ptr - rd_ptr_sync_bin;

    // =========================================================================
    // Read Side Logic (rd_clk domain)
    // =========================================================================

    // Synchronize write pointer to read domain (2-stage sync)
    logic [ADDR_W:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_ptr_gray_sync1 <= '0;
            wr_ptr_gray_sync2 <= '0;
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end
    assign wr_ptr_gray_sync = wr_ptr_gray_sync2;

    // Empty detection (in read domain)
    logic [ADDR_W:0] wr_ptr_sync_bin;
    assign wr_ptr_sync_bin = gray2bin(wr_ptr_gray_sync);

    logic empty;
    assign empty = (rd_ptr == wr_ptr_sync_bin);

    // Read data output register
    logic rd_data_valid;

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_data <= '0;
            rd_data_valid <= 1'b0;
        end else if (!empty && (!rd_data_valid || rd_ready)) begin
            rd_data <= mem[rd_ptr[ADDR_W-1:0]];
            rd_data_valid <= 1'b1;
        end else if (rd_ready) begin
            rd_data_valid <= 1'b0;
        end
    end

    assign rd_valid = rd_data_valid;

    // Read pointer update
    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr <= '0;
        end else if (!empty && (!rd_data_valid || rd_ready)) begin
            rd_ptr <= rd_ptr + 1'b1;
        end
    end

    // Gray code read pointer
    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr_gray <= '0;
        end else begin
            rd_ptr_gray <= bin2gray(rd_ptr + ((!empty && (!rd_data_valid || rd_ready)) ? 1'b1 : 1'b0));
        end
    end

endmodule
