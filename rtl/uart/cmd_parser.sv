// Celery3D GPU - UART Command Parser
// Parses incoming UART bytes and translates to GPU commands
//
// Command Protocol:
//   0x01 + 2 bytes  -> Clear framebuffer (RGB565 little-endian)
//   0x02            -> Clear depth buffer
//   0x03 + 120 bytes -> Submit triangle (3 vertices × 40 bytes)
//   0x04 + 1 byte   -> Set config flags
//
// Vertex format (40 bytes per vertex, little-endian fields):
//   Bytes 0-3:   x (S15.16 fixed-point)
//   Bytes 4-7:   y
//   Bytes 8-11:  z
//   Bytes 12-15: w
//   Bytes 16-19: u
//   Bytes 20-23: v
//   Bytes 24-27: r
//   Bytes 28-31: g
//   Bytes 32-35: b
//   Bytes 36-39: a

module cmd_parser
    import celery_pkg::*;
(
    input  logic       clk,
    input  logic       rst_n,

    // UART interface
    input  logic [7:0] uart_data,
    input  logic       uart_valid,

    // Triangle output (to rasterizer)
    output vertex_t    v0,
    output vertex_t    v1,
    output vertex_t    v2,
    output logic       tri_valid,
    input  logic       tri_ready,

    // Framebuffer control
    output logic       fb_clear,
    output rgb565_t    fb_clear_color,
    input  logic       fb_clearing,

    // Depth buffer control
    output logic       depth_clear,
    input  logic       depth_clearing,

    // Render configuration
    output logic       tex_enable,
    output logic       depth_test_enable,
    output logic       depth_write_enable,
    output logic       blend_enable
);

    // Command bytes
    localparam CMD_CLEAR_FB    = 8'h01;
    localparam CMD_CLEAR_DEPTH = 8'h02;
    localparam CMD_TRIANGLE    = 8'h03;
    localparam CMD_SET_CONFIG  = 8'h04;

    // Vertex size in bytes
    localparam VERTEX_BYTES = 40;
    localparam TRIANGLE_BYTES = VERTEX_BYTES * 3;  // 120 bytes

    // State machine
    typedef enum logic [3:0] {
        ST_IDLE,            // Wait for command byte
        ST_CLEAR_FB_0,      // Receive clear color low byte
        ST_CLEAR_FB_1,      // Receive clear color high byte
        ST_DO_CLEAR_FB,     // Issue framebuffer clear
        ST_DO_CLEAR_DEPTH,  // Issue depth buffer clear
        ST_RECV_TRIANGLE,   // Receive 120 bytes of vertex data
        ST_SUBMIT_TRI,      // Submit triangle to rasterizer
        ST_WAIT_TRI,        // Wait for triangle to complete
        ST_RECV_CONFIG      // Receive config byte
    } state_t;

    state_t state;
    logic [6:0] byte_count;   // 0-119 for triangle data
    logic [15:0] clear_color_reg;

    // Vertex data buffer (120 bytes = 960 bits)
    // We'll build vertices incrementally as bytes arrive
    logic [31:0] vertex_fields [0:29];  // 30 fields total (10 per vertex × 3)
    logic [1:0]  field_byte;            // Current byte within 32-bit field (0-3)
    logic [4:0]  field_index;           // Current field (0-29)

    // Build vertex from fields
    function automatic vertex_t build_vertex(input int base);
        vertex_t v;
        v.x = vertex_fields[base + 0];
        v.y = vertex_fields[base + 1];
        v.z = vertex_fields[base + 2];
        v.w = vertex_fields[base + 3];
        v.u = vertex_fields[base + 4];
        v.v = vertex_fields[base + 5];
        v.r = vertex_fields[base + 6];
        v.g = vertex_fields[base + 7];
        v.b = vertex_fields[base + 8];
        v.a = vertex_fields[base + 9];
        return v;
    endfunction

    // Main state machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            byte_count <= '0;
            field_byte <= '0;
            field_index <= '0;
            clear_color_reg <= '0;
            tri_valid <= 1'b0;
            fb_clear <= 1'b0;
            depth_clear <= 1'b0;
            fb_clear_color <= '0;
            v0 <= '0;
            v1 <= '0;
            v2 <= '0;

            // Default config: all enabled
            tex_enable <= 1'b1;
            depth_test_enable <= 1'b1;
            depth_write_enable <= 1'b1;
            blend_enable <= 1'b0;

            for (int i = 0; i < 30; i++) begin
                vertex_fields[i] <= '0;
            end

        end else begin
            // Default: deassert one-shot signals
            tri_valid <= 1'b0;
            fb_clear <= 1'b0;
            depth_clear <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (uart_valid) begin
                        case (uart_data)
                            CMD_CLEAR_FB: begin
                                state <= ST_CLEAR_FB_0;
                            end

                            CMD_CLEAR_DEPTH: begin
                                state <= ST_DO_CLEAR_DEPTH;
                            end

                            CMD_TRIANGLE: begin
                                state <= ST_RECV_TRIANGLE;
                                byte_count <= '0;
                                field_byte <= '0;
                                field_index <= '0;
                            end

                            CMD_SET_CONFIG: begin
                                state <= ST_RECV_CONFIG;
                            end

                            default: begin
                                // Unknown command, ignore
                                state <= ST_IDLE;
                            end
                        endcase
                    end
                end

                ST_CLEAR_FB_0: begin
                    // Receive low byte of RGB565 color
                    if (uart_valid) begin
                        clear_color_reg[7:0] <= uart_data;
                        state <= ST_CLEAR_FB_1;
                    end
                end

                ST_CLEAR_FB_1: begin
                    // Receive high byte of RGB565 color
                    if (uart_valid) begin
                        clear_color_reg[15:8] <= uart_data;
                        state <= ST_DO_CLEAR_FB;
                    end
                end

                ST_DO_CLEAR_FB: begin
                    // Issue framebuffer clear and wait for completion
                    if (!fb_clearing) begin
                        fb_clear_color <= {clear_color_reg[15:8], clear_color_reg[7:0]};
                        fb_clear <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                ST_DO_CLEAR_DEPTH: begin
                    // Issue depth buffer clear
                    if (!depth_clearing) begin
                        depth_clear <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                ST_RECV_TRIANGLE: begin
                    // Receive 120 bytes of vertex data
                    if (uart_valid) begin
                        // Shift byte into current field (little-endian)
                        case (field_byte)
                            2'd0: vertex_fields[field_index][7:0]   <= uart_data;
                            2'd1: vertex_fields[field_index][15:8]  <= uart_data;
                            2'd2: vertex_fields[field_index][23:16] <= uart_data;
                            2'd3: vertex_fields[field_index][31:24] <= uart_data;
                        endcase

                        if (field_byte == 2'd3) begin
                            // Move to next field
                            field_byte <= 2'd0;
                            field_index <= field_index + 1'b1;
                        end else begin
                            field_byte <= field_byte + 1'b1;
                        end

                        byte_count <= byte_count + 1'b1;

                        // Check if we've received all 120 bytes
                        if (byte_count == 7'd119) begin
                            state <= ST_SUBMIT_TRI;
                        end
                    end
                end

                ST_SUBMIT_TRI: begin
                    // Build vertices from received data
                    v0 <= build_vertex(0);   // Fields 0-9
                    v1 <= build_vertex(10);  // Fields 10-19
                    v2 <= build_vertex(20);  // Fields 20-29

                    // Wait for rasterizer to be ready
                    if (tri_ready) begin
                        tri_valid <= 1'b1;
                        state <= ST_WAIT_TRI;
                    end
                end

                ST_WAIT_TRI: begin
                    // Wait for rasterizer to accept triangle
                    // tri_valid was asserted for one cycle, now wait for ready
                    // to go low (busy) then high again (done)
                    // For simplicity, just go back to idle after submitting
                    state <= ST_IDLE;
                end

                ST_RECV_CONFIG: begin
                    // Receive config flags byte
                    if (uart_valid) begin
                        tex_enable         <= uart_data[0];
                        depth_test_enable  <= uart_data[1];
                        depth_write_enable <= uart_data[2];
                        blend_enable       <= uart_data[3];
                        state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
