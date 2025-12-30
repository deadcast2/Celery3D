// Pixel Write Master - AXI4 write master for single-pixel framebuffer writes
// Converts pixel writes (x, y, color) to AXI4 transactions for DDR3 framebuffer
//
// Design: Simple single-pixel writes using byte strobes
// - Each pixel write becomes one AXI4 write transaction
// - Uses byte strobes to write only 2 bytes (RGB565) per 32-byte beat
// - Address: FB_BASE_ADDR + (y * FB_WIDTH + x) * 2

module pixel_write_master
    import celery_pkg::rgb565_t;
#(
    parameter FB_WIDTH     = 640,
    parameter FB_HEIGHT    = 480,
    parameter FB_BASE_ADDR = 30'h0000_0000
)(
    input  logic        clk,
    input  logic        rst_n,

    // Pixel input interface (from rasterizer)
    input  logic [9:0]  pixel_x,
    input  logic [9:0]  pixel_y,
    input  rgb565_t     pixel_color,
    input  logic        pixel_valid,
    output logic        pixel_ready,

    // AXI4 Write Address Channel
    output logic [3:0]   m_axi_awid,
    output logic [29:0]  m_axi_awaddr,
    output logic [7:0]   m_axi_awlen,
    output logic [2:0]   m_axi_awsize,
    output logic [1:0]   m_axi_awburst,
    output logic [0:0]   m_axi_awlock,
    output logic [3:0]   m_axi_awcache,
    output logic [2:0]   m_axi_awprot,
    output logic [3:0]   m_axi_awqos,
    output logic         m_axi_awvalid,
    input  logic         m_axi_awready,

    // AXI4 Write Data Channel
    output logic [255:0] m_axi_wdata,
    output logic [31:0]  m_axi_wstrb,
    output logic         m_axi_wlast,
    output logic         m_axi_wvalid,
    input  logic         m_axi_wready,

    // AXI4 Write Response Channel
    input  logic [3:0]   m_axi_bid,
    input  logic [1:0]   m_axi_bresp,
    input  logic         m_axi_bvalid,
    output logic         m_axi_bready,

    // Status
    output logic         busy
);

    // =========================================================================
    // State Machine
    // =========================================================================
    typedef enum logic [2:0] {
        IDLE,
        ADDR,
        DATA,
        RESP
    } state_t;

    state_t state;

    // =========================================================================
    // Registered pixel data
    // =========================================================================
    logic [9:0]  pixel_x_r;
    logic [9:0]  pixel_y_r;
    rgb565_t     pixel_color_r;

    // =========================================================================
    // Address and strobe calculation
    // =========================================================================
    // Pixel byte address = FB_BASE_ADDR + (y * FB_WIDTH + x) * 2
    // AXI address is 32-byte aligned (bits [4:0] = 0)
    // Byte position within 32-byte beat = (x % 16) * 2

    logic [29:0] pixel_byte_addr;
    logic [29:0] axi_aligned_addr;
    logic [3:0]  pixel_lane;        // Which of 16 pixel lanes (0-15)
    logic [31:0] byte_strobe;

    // Calculate byte address of pixel
    // pixel_byte_addr = FB_BASE_ADDR + (y * FB_WIDTH + x) * 2
    always_comb begin
        // Multiply y by FB_WIDTH (640 = 512 + 128 = 2^9 + 2^7)
        // y * 640 = y * 512 + y * 128 = (y << 9) + (y << 7)
        logic [29:0] y_offset;
        y_offset = ({20'b0, pixel_y_r} << 9) + ({20'b0, pixel_y_r} << 7);

        // Add x and multiply by 2 (for RGB565)
        pixel_byte_addr = FB_BASE_ADDR + ((y_offset + {20'b0, pixel_x_r}) << 1);
    end

    // AXI address is 32-byte aligned
    assign axi_aligned_addr = {pixel_byte_addr[29:5], 5'b0};

    // Pixel lane within the 32-byte (16-pixel) beat
    // pixel_lane = (pixel_byte_addr / 2) % 16 = pixel_byte_addr[4:1]
    assign pixel_lane = pixel_byte_addr[4:1];

    // Generate byte strobe - enable 2 bytes for this pixel
    always_comb begin
        byte_strobe = 32'b0;
        byte_strobe[pixel_lane * 2 +: 2] = 2'b11;
    end

    // =========================================================================
    // Write data - replicate pixel across all lanes, strobe selects active
    // =========================================================================
    logic [255:0] write_data;

    always_comb begin
        // Replicate the 16-bit pixel color across all 16 lanes
        for (int i = 0; i < 16; i++) begin
            write_data[i*16 +: 16] = pixel_color_r;
        end
    end

    // =========================================================================
    // State Machine
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            pixel_x_r <= '0;
            pixel_y_r <= '0;
            pixel_color_r <= '0;
        end else begin
            case (state)
                IDLE: begin
                    if (pixel_valid && pixel_ready) begin
                        // Capture pixel data
                        pixel_x_r <= pixel_x;
                        pixel_y_r <= pixel_y;
                        pixel_color_r <= pixel_color;
                        state <= ADDR;
                    end
                end

                ADDR: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        state <= DATA;
                    end
                end

                DATA: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        state <= RESP;
                    end
                end

                RESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    // =========================================================================
    // Output assignments
    // =========================================================================

    // Pixel interface
    assign pixel_ready = (state == IDLE);
    assign busy = (state != IDLE);

    // AXI Write Address Channel
    assign m_axi_awid    = 4'd1;              // Use ID 1 for pixel writes
    assign m_axi_awaddr  = axi_aligned_addr;
    assign m_axi_awlen   = 8'd0;              // Single beat
    assign m_axi_awsize  = 3'b101;            // 32 bytes per beat
    assign m_axi_awburst = 2'b01;             // INCR (doesn't matter for len=0)
    assign m_axi_awlock  = 1'b0;
    assign m_axi_awcache = 4'b0011;           // Normal non-cacheable bufferable
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awqos   = 4'd0;
    assign m_axi_awvalid = (state == ADDR);

    // AXI Write Data Channel
    assign m_axi_wdata  = write_data;
    assign m_axi_wstrb  = byte_strobe;
    assign m_axi_wlast  = 1'b1;               // Always last (single beat)
    assign m_axi_wvalid = (state == DATA);

    // AXI Write Response Channel
    assign m_axi_bready = (state == RESP);

endmodule
