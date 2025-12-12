// Celery3D GPU - Edge Equation Evaluator
// Evaluates E(x,y) = A*x + B*y + C for rasterization
// Supports incremental evaluation: E(x+1,y) = E(x,y) + A

module edge_eval
    import celery_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // Edge equation coefficients
    input  edge_t       edge_in,

    // Current position (fixed-point)
    input  fp32_t       x,
    input  fp32_t       y,

    // Control
    input  logic        eval_start,     // Start new evaluation at (x,y)
    input  logic        step_x,         // Increment X by 1 (add A)
    input  logic        step_y,         // Increment Y by 1 (add B), reset X

    // Output
    output fp32_t       result,         // Current edge function value
    output logic        is_inside,      // result >= 0 (or > 0 for non-top-left edges)
    output logic        valid           // Result is valid
);

    // Internal state
    fp32_t eval_reg;
    logic  valid_reg;

    // Combinational evaluation
    fp32_t ax, by, ax_plus_by, full_eval;

    always_comb begin
        ax = fp_mul(edge_in.a, x);
        by = fp_mul(edge_in.b, y);
        ax_plus_by = ax + by;
        full_eval = ax_plus_by + edge_in.c;
    end

    // Determine if pixel is inside edge
    // Top-left fill rule: include pixel if E > 0, or E == 0 and edge is top-left
    always_comb begin
        if (eval_reg > 0)
            is_inside = 1'b1;
        else if (eval_reg == 0)
            is_inside = edge_in.top_left;
        else
            is_inside = 1'b0;
    end

    // Sequential logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            eval_reg <= FP_ZERO;
            valid_reg <= 1'b0;
        end else begin
            if (eval_start) begin
                // Full evaluation at (x, y)
                eval_reg <= full_eval;
                valid_reg <= 1'b1;
            end else if (step_x) begin
                // Incremental X step: E(x+1,y) = E(x,y) + A
                eval_reg <= eval_reg + edge_in.a;
            end else if (step_y) begin
                // Y step needs full re-evaluation since we might reset X
                // In practice, we'd track row start and add B
                eval_reg <= eval_reg + edge_in.b;
            end
        end
    end

    assign result = eval_reg;
    assign valid = valid_reg;

endmodule
