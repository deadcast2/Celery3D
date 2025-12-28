// DDR3 Framebuffer Line Buffer
// Double-buffered line buffer for reading 640x480 framebuffer from DDR3 memory
// Provides continuous pixel stream to video timing generator
//
// Features:
// - Ping-pong line buffers (read one while filling other)
// - AXI4 burst reads from DDR3
// - Cross-clock domain handling (ui_clk -> video_clk)
// - Prefetch logic to stay ahead of video output

module ddr3_fb_line_buffer
    import video_pkg::*;
    import celery_pkg::rgb565_t;
#(
    parameter FB_WIDTH  = 640,
    parameter FB_HEIGHT = 480,
    parameter FB_BASE_ADDR = 30'h0000_0000  // Base address in DDR3
)(
    // DDR3 clock domain (ui_clk from MIG, ~100MHz)
    input  logic        ddr_clk,
    input  logic        ddr_rst_n,
    input  logic        ddr_calib_done,

    // Video clock domain (25 MHz pixel clock)
    input  logic        video_clk,
    input  logic        video_rst_n,

    // Video timing interface (video_clk domain)
    input  logic        frame_start,      // Pulse at start of frame
    input  logic        line_start,       // Pulse at start of each line
    input  logic        pixel_valid,      // DE - active display area
    input  logic [9:0]  pixel_x,          // Current X coordinate
    input  logic [9:0]  pixel_y,          // Current Y coordinate
    output rgb565_t     pixel_data,       // Output pixel
    output logic        pixel_ready,      // Data is valid

    // AXI4 Read Address Channel (ddr_clk domain)
    output logic [3:0]   m_axi_arid,
    output logic [29:0]  m_axi_araddr,
    output logic [7:0]   m_axi_arlen,
    output logic [2:0]   m_axi_arsize,
    output logic [1:0]   m_axi_arburst,
    output logic [0:0]   m_axi_arlock,
    output logic [3:0]   m_axi_arcache,
    output logic [2:0]   m_axi_arprot,
    output logic [3:0]   m_axi_arqos,
    output logic         m_axi_arvalid,
    input  logic         m_axi_arready,

    // AXI4 Read Data Channel (ddr_clk domain)
    input  logic [3:0]   m_axi_rid,
    input  logic [255:0] m_axi_rdata,
    input  logic [1:0]   m_axi_rresp,
    input  logic         m_axi_rlast,
    input  logic         m_axi_rvalid,
    output logic         m_axi_rready
);

    // =========================================================================
    // Constants
    // =========================================================================

    // Each pixel is 2 bytes (RGB565)
    localparam BYTES_PER_PIXEL = 2;
    localparam BYTES_PER_LINE = FB_WIDTH * BYTES_PER_PIXEL;  // 1280 bytes

    // AXI is 256 bits = 32 bytes per beat
    localparam AXI_BYTES_PER_BEAT = 32;
    localparam PIXELS_PER_BEAT = AXI_BYTES_PER_BEAT / BYTES_PER_PIXEL;  // 16 pixels
    localparam BEATS_PER_LINE = (BYTES_PER_LINE + AXI_BYTES_PER_BEAT - 1) / AXI_BYTES_PER_BEAT;  // 40 beats

    // Burst length: use 16-beat bursts (awlen = 15)
    // 40 beats = 2 bursts of 16 + 1 burst of 8
    localparam BURST_LEN = 16;
    localparam BURSTS_PER_LINE = (BEATS_PER_LINE + BURST_LEN - 1) / BURST_LEN;  // 3 bursts

    // Line buffer depth (in 256-bit words)
    localparam LINE_BUF_DEPTH = BEATS_PER_LINE;  // 40 words

    // =========================================================================
    // Line Buffers (Ping-Pong)
    // =========================================================================

    // Two line buffers, each holds one scanline
    // Addressed by beat index (0-39), each entry is 256 bits (16 pixels)
    // Force BRAM inference for proper dual-clock domain support
    (* ram_style = "block" *) logic [255:0] line_buf_a [LINE_BUF_DEPTH];
    (* ram_style = "block" *) logic [255:0] line_buf_b [LINE_BUF_DEPTH];

    // =========================================================================
    // DDR Clock Domain - Read State Machine
    // =========================================================================

    typedef enum logic [2:0] {
        DDR_IDLE,
        DDR_WAIT_SYNC,
        DDR_READ_ADDR,
        DDR_READ_DATA,
        DDR_LINE_DONE,
        DDR_WAIT_PREFETCH
    } ddr_state_t;

    ddr_state_t ddr_state;

    // Current line being fetched
    logic [9:0] fetch_line;
    logic [5:0] fetch_beat;      // 0-39
    logic [1:0] fetch_burst;     // 0-2

    // Address calculation
    logic [29:0] line_base_addr;
    logic [29:0] burst_addr;

    assign line_base_addr = FB_BASE_ADDR + (fetch_line * BYTES_PER_LINE);
    assign burst_addr = line_base_addr + (fetch_burst * BURST_LEN * AXI_BYTES_PER_BEAT);

    // Burst length for current burst
    logic [7:0] current_burst_len;
    always_comb begin
        if (fetch_burst < BURSTS_PER_LINE - 1) begin
            current_burst_len = BURST_LEN - 1;  // Full 16-beat burst
        end else begin
            // Last burst: remaining beats
            current_burst_len = BEATS_PER_LINE - (fetch_burst * BURST_LEN) - 1;
        end
    end

    // Cross-domain sync: frame_start from video to DDR domain
    logic frame_start_sync_r1, frame_start_sync_r2, frame_start_sync_r3;
    logic frame_start_pulse_ddr;

    always_ff @(posedge ddr_clk or negedge ddr_rst_n) begin
        if (!ddr_rst_n) begin
            frame_start_sync_r1 <= 1'b0;
            frame_start_sync_r2 <= 1'b0;
            frame_start_sync_r3 <= 1'b0;
        end else begin
            frame_start_sync_r1 <= frame_start;
            frame_start_sync_r2 <= frame_start_sync_r1;
            frame_start_sync_r3 <= frame_start_sync_r2;
        end
    end
    assign frame_start_pulse_ddr = frame_start_sync_r2 && !frame_start_sync_r3;

    // Cross-domain sync: line_start from video to DDR domain
    logic line_start_sync_r1, line_start_sync_r2, line_start_sync_r3;
    logic line_start_pulse_ddr;

    always_ff @(posedge ddr_clk or negedge ddr_rst_n) begin
        if (!ddr_rst_n) begin
            line_start_sync_r1 <= 1'b0;
            line_start_sync_r2 <= 1'b0;
            line_start_sync_r3 <= 1'b0;
        end else begin
            line_start_sync_r1 <= line_start;
            line_start_sync_r2 <= line_start_sync_r1;
            line_start_sync_r3 <= line_start_sync_r2;
        end
    end
    assign line_start_pulse_ddr = line_start_sync_r2 && !line_start_sync_r3;

    // DDR-domain buffer selection - track locally, no CDC race!
    // ddr_write_to_b: 1=write to B, 0=write to A
    // Pattern: line 0 -> B, line 1 -> A, line 2 -> B, ... (alternates)
    // Buffer selection is simply based on line number: even lines -> B, odd lines -> A
    // This matches video: even lines read from B (sel=1), odd lines from A (sel=0)
    wire ddr_write_to_b = ~fetch_line[0];  // Even line -> B (1), Odd line -> A (0)

    // DDR read state machine
    // Key insight: DDR must read line N BEFORE display needs it.
    // Strategy:
    // 1. Prefetch line 0 immediately after calibration (before frame_start)
    // 2. Wait for frame_start to trigger display
    // 3. Then stay exactly 1 line ahead: read line N+1 while display shows line N
    logic prefetch_done;

    always_ff @(posedge ddr_clk or negedge ddr_rst_n) begin
        if (!ddr_rst_n) begin
            ddr_state <= DDR_IDLE;
            fetch_line <= '0;
            fetch_beat <= '0;
            fetch_burst <= '0;
            prefetch_done <= 1'b0;
        end else begin
            case (ddr_state)
                DDR_IDLE: begin
                    // Start prefetching line 0 as soon as calibration is done
                    if (ddr_calib_done) begin
                        fetch_line <= 10'd0;
                        fetch_beat <= 6'd0;
                        fetch_burst <= 2'd0;
                        prefetch_done <= 1'b0;
                        ddr_state <= DDR_READ_ADDR;
                    end
                end

                DDR_WAIT_SYNC: begin
                    if (!prefetch_done) begin
                        // After prefetching line 0, wait for frame_start
                        if (frame_start_pulse_ddr) begin
                            prefetch_done <= 1'b1;
                            // Now read line 1 (display is starting line 0)
                            fetch_line <= 10'd1;
                            fetch_beat <= 6'd0;
                            fetch_burst <= 2'd0;
                            ddr_state <= DDR_READ_ADDR;
                        end
                    end else begin
                        // Normal operation: wait for line_start to read next line
                        if (line_start_pulse_ddr) begin
                            fetch_beat <= 6'd0;
                            fetch_burst <= 2'd0;
                            ddr_state <= DDR_READ_ADDR;
                        end
                        // Handle frame wrap
                        if (frame_start_pulse_ddr) begin
                            fetch_line <= 10'd1;  // Read line 1 (line 0 still in buffer)
                            fetch_beat <= 6'd0;
                            fetch_burst <= 2'd0;
                            ddr_state <= DDR_READ_ADDR;
                        end
                    end
                end

                DDR_READ_ADDR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        ddr_state <= DDR_READ_DATA;
                    end
                end

                DDR_READ_DATA: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        // Buffer writes moved to separate always block for BRAM inference
                        fetch_beat <= fetch_beat + 1'b1;

                        if (m_axi_rlast) begin
                            // End of burst
                            fetch_burst <= fetch_burst + 1'b1;

                            if (fetch_burst >= BURSTS_PER_LINE - 1) begin
                                // Line complete
                                ddr_state <= DDR_LINE_DONE;
                            end else begin
                                // More bursts needed
                                ddr_state <= DDR_READ_ADDR;
                            end
                        end
                    end
                end

                DDR_LINE_DONE: begin
                    if (!prefetch_done) begin
                        // Just finished prefetching line 0, wait for frame_start
                        ddr_state <= DDR_WAIT_SYNC;
                    end else if (fetch_line < FB_HEIGHT - 1) begin
                        // Advance to next line, wait for line_start
                        fetch_line <= fetch_line + 1'b1;
                        ddr_state <= DDR_WAIT_SYNC;
                    end else begin
                        // Frame complete - prepare to prefetch line 0
                        // BUT: video is still reading row 478 from buffer B!
                        // We must wait for line_start (row 479 begins) before
                        // prefetching row 0 to buffer B, to avoid corruption.
                        fetch_line <= 10'd0;
                        fetch_beat <= 6'd0;
                        fetch_burst <= 2'd0;
                        prefetch_done <= 1'b0;  // Back to prefetch mode
                        ddr_state <= DDR_WAIT_PREFETCH;
                    end
                end

                DDR_WAIT_PREFETCH: begin
                    // Wait for line_start (video row 479 begins, row 478 done)
                    // Now safe to prefetch row 0 to buffer B
                    if (line_start_pulse_ddr) begin
                        ddr_state <= DDR_READ_ADDR;
                    end
                end

                default: ddr_state <= DDR_IDLE;
            endcase
        end
    end

    // AXI Read Address Channel
    assign m_axi_arid    = 4'd0;
    assign m_axi_araddr  = burst_addr;
    assign m_axi_arlen   = current_burst_len;
    assign m_axi_arsize  = 3'b101;         // 32 bytes
    assign m_axi_arburst = 2'b01;          // INCR
    assign m_axi_arlock  = 1'b0;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arqos   = 4'd0;
    assign m_axi_arvalid = (ddr_state == DDR_READ_ADDR);

    // AXI Read Data Channel
    assign m_axi_rready = (ddr_state == DDR_READ_DATA);

    // =========================================================================
    // Line Buffer Writes (separate block for BRAM inference)
    // =========================================================================
    // IMPORTANT: This must be in a separate always_ff WITHOUT async reset.
    // BRAM primitives don't support async reset, so having the write inside
    // a block with async reset prevents BRAM inference.

    always_ff @(posedge ddr_clk) begin
        if (m_axi_rvalid && m_axi_rready) begin
            if (ddr_write_to_b) begin
                line_buf_b[fetch_beat] <= m_axi_rdata;
            end else begin
                line_buf_a[fetch_beat] <= m_axi_rdata;
            end
        end
    end

    // =========================================================================
    // Video Clock Domain - Pixel Output
    // =========================================================================

    // Calculate which 256-bit word and which pixel within it
    logic [5:0] read_beat;
    logic [3:0] read_pixel_offset;  // 0-15, which pixel in 256-bit word

    assign read_beat = pixel_x[9:4];         // pixel_x / 16
    assign read_pixel_offset = pixel_x[3:0]; // pixel_x % 16

    // Read from the appropriate line buffer
    // Use pixel_y directly: even lines from B, odd lines from A
    // This avoids race conditions with display_buf_sel toggle timing
    //
    // IMPORTANT: Read from both buffers unconditionally to enable BRAM inference.
    // Conditional reads prevent Vivado from inferring true dual-port BRAM.
    logic [255:0] read_word_a, read_word_b;
    logic [255:0] read_word;
    logic read_from_b_r;  // Registered to match read_word timing

    // Unconditional reads from both buffers - enables BRAM inference
    always_ff @(posedge video_clk) begin
        read_word_a <= line_buf_a[read_beat];
        read_word_b <= line_buf_b[read_beat];
        read_from_b_r <= ~pixel_y[0];  // Even Y -> B, Odd Y -> A
    end

    // Mux after the BRAM read
    always_comb begin
        read_word = read_from_b_r ? read_word_b : read_word_a;
    end

    // Sync prefetch_done to video domain to know when system has started
    // Use a latched version that stays high forever once first prefetch completes
    logic prefetch_done_sync1, prefetch_done_sync2;
    logic system_ready;  // Latched high after first prefetch

    always_ff @(posedge video_clk or negedge video_rst_n) begin
        if (!video_rst_n) begin
            prefetch_done_sync1 <= 1'b0;
            prefetch_done_sync2 <= 1'b0;
            system_ready <= 1'b0;
        end else begin
            prefetch_done_sync1 <= prefetch_done;
            prefetch_done_sync2 <= prefetch_done_sync1;
            // Latch high once first prefetch completes
            if (prefetch_done_sync2)
                system_ready <= 1'b1;
        end
    end

    // Extract the correct 16-bit pixel from 256-bit word
    // Pixels are stored little-endian: pixel 0 at bits [15:0], pixel 1 at [31:16], etc.
    logic [3:0] pixel_offset_r;
    logic pixel_valid_r;

    always_ff @(posedge video_clk or negedge video_rst_n) begin
        if (!video_rst_n) begin
            pixel_offset_r <= '0;
            pixel_valid_r <= 1'b0;
        end else begin
            pixel_offset_r <= read_pixel_offset;
            // Only output valid pixels when:
            // 1. We're in the active display area (pixel_valid)
            // 2. We're within the framebuffer height
            // 3. System has initialized (first prefetch completed)
            pixel_valid_r <= pixel_valid && (pixel_y < FB_HEIGHT) && system_ready;
        end
    end

    // Mux to select correct pixel
    always_comb begin
        case (pixel_offset_r)
            4'd0:  pixel_data = read_word[15:0];
            4'd1:  pixel_data = read_word[31:16];
            4'd2:  pixel_data = read_word[47:32];
            4'd3:  pixel_data = read_word[63:48];
            4'd4:  pixel_data = read_word[79:64];
            4'd5:  pixel_data = read_word[95:80];
            4'd6:  pixel_data = read_word[111:96];
            4'd7:  pixel_data = read_word[127:112];
            4'd8:  pixel_data = read_word[143:128];
            4'd9:  pixel_data = read_word[159:144];
            4'd10: pixel_data = read_word[175:160];
            4'd11: pixel_data = read_word[191:176];
            4'd12: pixel_data = read_word[207:192];
            4'd13: pixel_data = read_word[223:208];
            4'd14: pixel_data = read_word[239:224];
            4'd15: pixel_data = read_word[255:240];
        endcase
    end

    assign pixel_ready = pixel_valid_r;

endmodule
