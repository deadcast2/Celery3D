// Celery3D GPU - Framebuffer
// Stores rendered pixels for display output
// For simulation: uses behavioral memory array at full resolution
// For synthesis: small sizes use BRAM, full 640x480 would use DDR3

module framebuffer
    import celery_pkg::*;
#(
    parameter FB_WIDTH  = 640,
    parameter FB_HEIGHT = 480
)(
    input  logic        clk,
    input  logic        rst_n,

    // Fragment write interface (from depth buffer / rasterizer)
    input  fragment_t   frag_in,
    input  rgb565_t     color_in,
    input  logic        frag_in_valid,
    output logic        frag_in_ready,

    // Read interface (for video output or alpha blending)
    input  logic [$clog2(FB_WIDTH)-1:0]  read_x,
    input  logic [$clog2(FB_HEIGHT)-1:0] read_y,
    input  logic                          read_en,
    output rgb565_t                       read_data,
    output logic                          read_valid,

    // Clear interface
    input  logic        clear,
    input  rgb565_t     clear_color,
    output logic        clearing,

    // Status
    output logic        busy
);

    // Memory array
    // For simulation this is just a big array
    // For small sizes, synthesis will infer BRAM
    localparam ADDR_BITS = $clog2(FB_WIDTH * FB_HEIGHT);
    rgb565_t mem [0:FB_WIDTH*FB_HEIGHT-1];

    // Clear state machine
    typedef enum logic [1:0] {
        IDLE,
        CLEARING,
        CLEAR_DONE
    } state_t;

    state_t state;
    logic [ADDR_BITS-1:0] clear_addr;

    // Address calculation
    function automatic logic [ADDR_BITS-1:0] calc_addr(
        input logic [$clog2(FB_WIDTH)-1:0] x,
        input logic [$clog2(FB_HEIGHT)-1:0] y
    );
        return y * FB_WIDTH + x;
    endfunction

    // Write logic
    logic [ADDR_BITS-1:0] write_addr;
    logic write_en;

    // Extract coordinates from fragment
    logic [$clog2(FB_WIDTH)-1:0] frag_x;
    logic [$clog2(FB_HEIGHT)-1:0] frag_y;
    assign frag_x = frag_in.x[$clog2(FB_WIDTH)-1:0];
    assign frag_y = frag_in.y[$clog2(FB_HEIGHT)-1:0];

    always_comb begin
        write_addr = calc_addr(frag_x, frag_y);
        // Can write when not clearing and fragment is valid and in bounds
        write_en = frag_in_valid && (state == IDLE) &&
                   (frag_in.x < FB_WIDTH) && (frag_in.y < FB_HEIGHT);
    end

    // Fragment input is ready when not clearing
    assign frag_in_ready = (state == IDLE);

    // Memory write - either clear or fragment write
    always_ff @(posedge clk) begin
        if (state == CLEARING) begin
            mem[clear_addr] <= clear_color;
        end else if (write_en) begin
            mem[write_addr] <= color_in;
        end
    end

    // Read logic - synchronous read with one cycle latency
    logic [ADDR_BITS-1:0] read_addr;
    logic read_en_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_data <= 16'h0;
            read_valid <= 1'b0;
            read_en_r <= 1'b0;
        end else begin
            read_en_r <= read_en;
            read_valid <= read_en_r;
            if (read_en) begin
                read_addr <= calc_addr(read_x, read_y);
            end
            if (read_en_r) begin
                read_data <= mem[read_addr];
            end
        end
    end

    // Clear state machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            clear_addr <= '0;
        end else begin
            case (state)
                IDLE: begin
                    if (clear) begin
                        state <= CLEARING;
                        clear_addr <= '0;
                    end
                end

                CLEARING: begin
                    if (clear_addr == FB_WIDTH * FB_HEIGHT - 1) begin
                        state <= CLEAR_DONE;
                    end else begin
                        clear_addr <= clear_addr + 1;
                    end
                end

                CLEAR_DONE: begin
                    // Single cycle done state, return to idle
                    state <= IDLE;
                    clear_addr <= '0;
                end
            endcase
        end
    end

    assign clearing = (state == CLEARING);
    assign busy = (state != IDLE);

    // Simulation initialization - clear to black
    `ifndef SYNTHESIS
    initial begin
        for (int i = 0; i < FB_WIDTH * FB_HEIGHT; i++) begin
            mem[i] = 16'h0000;
        end
    end
    `endif

endmodule
