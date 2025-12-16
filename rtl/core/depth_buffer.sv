// Celery3D GPU - Depth Buffer Unit
// BRAM-based depth buffer with Glide-compatible comparison functions
// 3-stage pipeline: address/read → compare/write → output
//
// SPDX-License-Identifier: CERN-OHL-P-2.0

module depth_buffer
    import celery_pkg::*;
#(
    // Depth buffer dimensions (matches framebuffer)
    parameter DB_WIDTH  = 640,
    parameter DB_HEIGHT = 480
)(
    input  logic        clk,
    input  logic        rst_n,

    // Configuration
    input  logic        depth_test_enable,   // Enable depth test
    input  logic        depth_write_enable,  // Enable depth buffer writes
    input  depth_func_t depth_func,          // Comparison function

    // Clear interface
    input  logic        depth_clear,         // Pulse to start clear
    input  logic [15:0] depth_clear_value,   // Clear value (typically 0xFFFF for far)
    output logic        depth_clearing,      // High while clearing

    // Input from texture_unit
    input  fragment_t   frag_in,
    input  rgb565_t     color_in,
    input  logic        frag_in_valid,
    output logic        frag_in_ready,

    // Output (passed fragments)
    output fragment_t   frag_out,
    output rgb565_t     color_out,
    output logic        frag_out_valid,
    input  logic        frag_out_ready
);

    // =========================================================================
    // Derived Parameters
    // =========================================================================

    localparam DB_SIZE   = DB_WIDTH * DB_HEIGHT;
    localparam ADDR_BITS = $clog2(DB_SIZE);

    // =========================================================================
    // Depth Buffer Memory (Simple Dual-Port BRAM)
    // =========================================================================

    logic [15:0] depth_mem [0:DB_SIZE-1];

    // Initialize depth memory to far plane for simulation
    // (In synthesis, this is handled by the clear operation)
    initial begin
        for (int i = 0; i < DB_SIZE; i++) begin
            depth_mem[i] = 16'hFFFF;
        end
    end

    // Read port
    logic [ADDR_BITS-1:0] read_addr;
    logic [15:0] depth_read_data;

    // Write port
    logic [ADDR_BITS-1:0] write_addr;
    logic [15:0] write_data;
    logic write_en;

    // BRAM read (registered for timing - 1 cycle latency)
    always_ff @(posedge clk) begin
        if (!stall) begin
            depth_read_data <= depth_mem[read_addr];
        end
    end

    // BRAM write
    always_ff @(posedge clk) begin
        if (write_en) begin
            depth_mem[write_addr] <= write_data;
        end
    end

    // =========================================================================
    // Clear State Machine
    // =========================================================================

    logic [ADDR_BITS-1:0] clear_addr;
    logic clear_active;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clear_active <= 1'b0;
            clear_addr <= '0;
        end else if (depth_clear && !clear_active) begin
            // Start clearing
            clear_active <= 1'b1;
            clear_addr <= '0;
        end else if (clear_active) begin
            if (clear_addr == DB_SIZE - 1) begin
                clear_active <= 1'b0;
            end else begin
                clear_addr <= clear_addr + 1'b1;
            end
        end
    end

    assign depth_clearing = clear_active;

    // =========================================================================
    // Pipeline Control
    // =========================================================================

    logic stall;
    assign stall = p3_valid && !frag_out_ready;
    assign frag_in_ready = !stall && !clear_active;

    // =========================================================================
    // Z-Value Conversion (S15.16 to 16-bit unsigned)
    // =========================================================================

    // Convert 32-bit S15.16 fixed-point z to 16-bit unsigned depth
    // z=0.0 maps to 0x0000 (near), z=1.0 maps to 0xFFFF (far)
    function automatic logic [15:0] z_to_depth16(input fp32_t z);
        if (z[31]) begin
            // Negative z -> clamp to near (0)
            return 16'h0000;
        end else if (z[31:16] != 16'h0000) begin
            // z >= 1.0 -> clamp to far (max)
            return 16'hFFFF;
        end else begin
            // 0 <= z < 1.0: use fractional bits [15:0]
            return z[15:0];
        end
    endfunction

    // =========================================================================
    // Depth Comparison Function
    // =========================================================================

    function automatic logic depth_compare(
        input depth_func_t func,
        input logic [15:0] z_new,
        input logic [15:0] z_stored
    );
        case (func)
            GR_CMP_NEVER:    return 1'b0;
            GR_CMP_LESS:     return z_new < z_stored;
            GR_CMP_EQUAL:    return z_new == z_stored;
            GR_CMP_LEQUAL:   return z_new <= z_stored;
            GR_CMP_GREATER:  return z_new > z_stored;
            GR_CMP_NOTEQUAL: return z_new != z_stored;
            GR_CMP_GEQUAL:   return z_new >= z_stored;
            GR_CMP_ALWAYS:   return 1'b1;
            default:         return 1'b0;
        endcase
    endfunction

    // =========================================================================
    // Stage 1: Address Calculation and BRAM Read Issue
    // =========================================================================

    fragment_t p1_frag;
    rgb565_t p1_color;
    logic p1_valid;
    logic [15:0] p1_depth16;
    logic [ADDR_BITS-1:0] p1_addr;
    logic p1_in_bounds;
    logic p1_depth_test_enable;
    logic p1_depth_write_enable;
    depth_func_t p1_depth_func;

    // Compute read address from fragment coordinates
    logic [ADDR_BITS-1:0] frag_addr;
    logic frag_in_bounds;

    // Address calculation function (matches framebuffer.sv)
    function automatic logic [ADDR_BITS-1:0] calc_addr(
        input logic [$clog2(DB_WIDTH)-1:0] x,
        input logic [$clog2(DB_HEIGHT)-1:0] y
    );
        return y * DB_WIDTH + x;
    endfunction

    // Extract coordinates from fragment
    logic [$clog2(DB_WIDTH)-1:0] frag_x;
    logic [$clog2(DB_HEIGHT)-1:0] frag_y;
    assign frag_x = frag_in.x[$clog2(DB_WIDTH)-1:0];
    assign frag_y = frag_in.y[$clog2(DB_HEIGHT)-1:0];

    always_comb begin
        // Address = y * width + x
        frag_addr = calc_addr(frag_x, frag_y);

        // Bounds check: fragment coordinates must be within depth buffer dimensions
        frag_in_bounds = (frag_in.x < DB_WIDTH) && (frag_in.y < DB_HEIGHT);
    end

    // Issue BRAM read with fragment address (or clear address during clear)
    assign read_addr = clear_active ? clear_addr : frag_addr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p1_frag <= '0;
            p1_color <= 16'h0000;
            p1_valid <= 1'b0;
            p1_depth16 <= 16'h0000;
            p1_addr <= '0;
            p1_in_bounds <= 1'b0;
            p1_depth_test_enable <= 1'b0;
            p1_depth_write_enable <= 1'b0;
            p1_depth_func <= GR_CMP_LESS;
        end else if (!stall && !clear_active) begin
            p1_valid <= frag_in_valid && frag_in.valid;
            p1_frag <= frag_in;
            p1_color <= color_in;
            p1_depth16 <= z_to_depth16(frag_in.z);
            p1_addr <= frag_addr;
            p1_in_bounds <= frag_in_bounds;
            p1_depth_test_enable <= depth_test_enable;
            p1_depth_write_enable <= depth_write_enable;
            p1_depth_func <= depth_func;
        end else if (!stall && clear_active) begin
            // Invalidate pipeline during clear
            p1_valid <= 1'b0;
        end
    end

    // =========================================================================
    // Stage 2: Depth Compare and Write Decision
    // =========================================================================

    fragment_t p2_frag;
    rgb565_t p2_color;
    logic p2_valid;
    logic [15:0] p2_depth16;
    logic [ADDR_BITS-1:0] p2_addr;
    logic p2_in_bounds;
    logic p2_depth_test_enable;
    logic p2_depth_write_enable;
    depth_func_t p2_depth_func;
    logic p2_depth_pass;

    // Depth comparison result (combinational)
    logic depth_test_result;

    always_comb begin
        if (!p1_depth_test_enable) begin
            // Depth test disabled: always pass
            depth_test_result = 1'b1;
        end else if (!p1_in_bounds) begin
            // Out of bounds: fail (don't write garbage)
            depth_test_result = 1'b0;
        end else begin
            // Perform depth comparison
            depth_test_result = depth_compare(p1_depth_func, p1_depth16, depth_read_data);
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p2_frag <= '0;
            p2_color <= 16'h0000;
            p2_valid <= 1'b0;
            p2_depth16 <= 16'h0000;
            p2_addr <= '0;
            p2_in_bounds <= 1'b0;
            p2_depth_test_enable <= 1'b0;
            p2_depth_write_enable <= 1'b0;
            p2_depth_func <= GR_CMP_LESS;
            p2_depth_pass <= 1'b0;
        end else if (!stall) begin
            p2_valid <= p1_valid;
            p2_frag <= p1_frag;
            p2_color <= p1_color;
            p2_depth16 <= p1_depth16;
            p2_addr <= p1_addr;
            p2_in_bounds <= p1_in_bounds;
            p2_depth_test_enable <= p1_depth_test_enable;
            p2_depth_write_enable <= p1_depth_write_enable;
            p2_depth_func <= p1_depth_func;
            p2_depth_pass <= depth_test_result;
        end
    end

    // =========================================================================
    // Stage 3: Output and Write
    // =========================================================================

    fragment_t p3_frag;
    rgb565_t p3_color;
    logic p3_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p3_frag <= '0;
            p3_color <= 16'h0000;
            p3_valid <= 1'b0;
        end else if (!stall) begin
            // Only output valid fragments that passed depth test
            p3_valid <= p2_valid && p2_depth_pass;
            p3_frag <= p2_frag;
            p3_color <= p2_color;
        end
    end

    // =========================================================================
    // BRAM Write Logic
    // =========================================================================

    // Write depth value if:
    // 1. During clear: write clear value at clear_addr
    // 2. During normal operation: write if fragment passed and write enabled

    always_comb begin
        if (clear_active) begin
            // Clear mode: write clear value to sequential addresses
            write_en = 1'b1;
            write_addr = clear_addr;
            write_data = depth_clear_value;
        end else if (!stall && p2_valid && p2_depth_pass && p2_depth_write_enable && p2_in_bounds) begin
            // Normal mode: write new depth if test passed
            write_en = 1'b1;
            write_addr = p2_addr;
            write_data = p2_depth16;
        end else begin
            write_en = 1'b0;
            write_addr = '0;
            write_data = 16'h0000;
        end
    end

    // =========================================================================
    // Output Assignments
    // =========================================================================

    assign frag_out = p3_frag;
    assign color_out = p3_color;
    assign frag_out_valid = p3_valid;

endmodule
