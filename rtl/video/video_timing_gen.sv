// Celery3D GPU - Video Timing Generator
// Generates HSYNC, VSYNC, DE, and pixel coordinates for 640x480 @ 60Hz

module video_timing_gen
    import video_pkg::*;
(
    input  logic        pixel_clk,
    input  logic        rst_n,

    // Timing outputs
    output logic        hsync,        // Horizontal sync (directly to ADV7511)
    output logic        vsync,        // Vertical sync
    output logic        de,           // Data enable (active during visible region)

    // Pixel coordinates (valid when de=1)
    output logic [9:0]  pixel_x,      // 0 to H_ACTIVE-1 (0-639)
    output logic [9:0]  pixel_y,      // 0 to V_ACTIVE-1 (0-479)

    // Frame sync pulses
    output logic        frame_start,  // Pulse at start of new frame
    output logic        line_start    // Pulse at start of each visible line
);

    // Horizontal and vertical counters
    logic [H_COUNT_BITS-1:0] h_count;
    logic [V_COUNT_BITS-1:0] v_count;

    // End of line/frame detection
    logic h_end;
    logic v_end;

    assign h_end = (h_count == H_TOTAL - 1);
    assign v_end = (v_count == V_TOTAL - 1);

    // =========================================================================
    // Horizontal Counter
    // =========================================================================
    always_ff @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            h_count <= '0;
        end else begin
            if (h_end) begin
                h_count <= '0;
            end else begin
                h_count <= h_count + 1'b1;
            end
        end
    end

    // =========================================================================
    // Vertical Counter
    // =========================================================================
    always_ff @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            v_count <= '0;
        end else if (h_end) begin
            if (v_end) begin
                v_count <= '0;
            end else begin
                v_count <= v_count + 1'b1;
            end
        end
    end

    // =========================================================================
    // Sync Signal Generation
    // =========================================================================

    // HSYNC: active during sync pulse region
    // H_SYNC_POL = 0 means active low
    always_ff @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            hsync <= ~H_SYNC_POL;  // Inactive state
        end else begin
            if (h_count >= H_SYNC_START && h_count < H_SYNC_END) begin
                hsync <= H_SYNC_POL;   // Active
            end else begin
                hsync <= ~H_SYNC_POL;  // Inactive
            end
        end
    end

    // VSYNC: active during sync pulse region
    always_ff @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            vsync <= ~V_SYNC_POL;  // Inactive state
        end else begin
            if (v_count >= V_SYNC_START && v_count < V_SYNC_END) begin
                vsync <= V_SYNC_POL;   // Active
            end else begin
                vsync <= ~V_SYNC_POL;  // Inactive
            end
        end
    end

    // =========================================================================
    // Data Enable (active during visible region)
    // =========================================================================
    logic h_active;
    logic v_active;

    assign h_active = (h_count < H_ACTIVE);
    assign v_active = (v_count < V_ACTIVE);

    always_ff @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            de <= 1'b0;
        end else begin
            de <= h_active && v_active;
        end
    end

    // =========================================================================
    // Pixel Coordinates
    // =========================================================================
    always_ff @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_x <= '0;
            pixel_y <= '0;
        end else begin
            // X coordinate: directly from h_count during active region
            if (h_count < H_ACTIVE) begin
                pixel_x <= h_count[9:0];
            end else begin
                pixel_x <= '0;
            end

            // Y coordinate: directly from v_count during active region
            if (v_count < V_ACTIVE) begin
                pixel_y <= v_count[9:0];
            end else begin
                pixel_y <= '0;
            end
        end
    end

    // =========================================================================
    // Frame and Line Start Pulses
    // =========================================================================
    always_ff @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_start <= 1'b0;
            line_start  <= 1'b0;
        end else begin
            // Frame start: first pixel of first line
            frame_start <= (h_count == 0) && (v_count == 0);

            // Line start: first pixel of each visible line
            line_start <= (h_count == 0) && (v_count < V_ACTIVE);
        end
    end

endmodule
