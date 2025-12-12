// Celery3D GPU - Rasterizer Top Level
// Combines triangle setup and rasterizer core

module rasterizer_top
    import celery_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // Vertex input interface
    input  vertex_t     v0, v1, v2,
    input  logic        tri_valid,
    output logic        tri_ready,

    // Fragment output interface
    output fragment_t   frag_out,
    output logic        frag_valid,
    input  logic        frag_ready,

    // Status
    output logic        busy
);

    // Internal signals
    triangle_setup_t setup;
    logic setup_done;
    logic setup_busy;
    logic rast_start;
    logic rast_done;
    logic rast_busy;

    // State for coordinating setup and rasterizer
    typedef enum logic [1:0] {
        IDLE,
        SETUP,
        RASTERIZE
    } state_t;

    state_t state;

    // Triangle setup unit
    triangle_setup u_setup (
        .clk        (clk),
        .rst_n      (rst_n),
        .v0         (v0),
        .v1         (v1),
        .v2         (v2),
        .start      (tri_valid && state == IDLE),
        .setup      (setup),
        .done       (setup_done),
        .busy       (setup_busy)
    );

    // Rasterizer core
    rasterizer u_rast (
        .clk        (clk),
        .rst_n      (rst_n),
        .tri_in     (setup),
        .start      (rast_start),
        .frag_out   (frag_out),
        .frag_valid (frag_valid),
        .frag_ready (frag_ready),
        .done       (rast_done),
        .busy       (rast_busy)
    );

    // State machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            rast_start <= 1'b0;
        end else begin
            rast_start <= 1'b0;

            case (state)
                IDLE: begin
                    if (tri_valid) begin
                        state <= SETUP;
                    end
                end

                SETUP: begin
                    if (setup_done) begin
                        if (setup.valid) begin
                            rast_start <= 1'b1;
                            state <= RASTERIZE;
                        end else begin
                            // Degenerate triangle, skip
                            state <= IDLE;
                        end
                    end
                end

                RASTERIZE: begin
                    if (rast_done) begin
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

    assign tri_ready = (state == IDLE);
    assign busy = (state != IDLE);

endmodule
