//-----------------------------------------------------------------------------
// video_timing_gen.sv
// Video timing generator for 640x480@60Hz
// Generates sync signals and pixel coordinates
//-----------------------------------------------------------------------------

module video_timing_gen (
    input  wire        clk_pixel,       // 25.175 MHz pixel clock (25 MHz OK)
    input  wire        rst_n,

    // Timing outputs
    output wire        hsync,           // Horizontal sync (directly active high for ADV7511)
    output wire        vsync,           // Vertical sync (directly active high for ADV7511)
    output wire        data_enable,     // Active video indicator

    // Position counters
    output wire [9:0]  pixel_x,         // 0-639 during active video
    output wire [9:0]  pixel_y,         // 0-479 during active video

    // Frame timing
    output wire        frame_start,     // Pulse at start of frame
    output wire        line_start       // Pulse at start of each line
);

    //-------------------------------------------------------------------------
    // 640x480@60Hz timing parameters
    // Pixel clock: 25.175 MHz (25 MHz close enough)
    //-------------------------------------------------------------------------
    localparam H_ACTIVE      = 640;
    localparam H_FRONT_PORCH = 16;
    localparam H_SYNC_PULSE  = 96;
    localparam H_BACK_PORCH  = 48;
    localparam H_TOTAL       = H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH; // 800

    localparam V_ACTIVE      = 480;
    localparam V_FRONT_PORCH = 10;
    localparam V_SYNC_PULSE  = 2;
    localparam V_BACK_PORCH  = 33;
    localparam V_TOTAL       = V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH; // 525

    // Sync pulse positions
    localparam H_SYNC_START  = H_ACTIVE + H_FRONT_PORCH;                    // 656
    localparam H_SYNC_END    = H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE;    // 752
    localparam V_SYNC_START  = V_ACTIVE + V_FRONT_PORCH;                    // 490
    localparam V_SYNC_END    = V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE;    // 492

    //-------------------------------------------------------------------------
    // Counters
    //-------------------------------------------------------------------------
    reg [9:0] h_count;
    reg [9:0] v_count;

    //-------------------------------------------------------------------------
    // Horizontal counter
    //-------------------------------------------------------------------------
    always_ff @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            h_count <= 10'd0;
        end else begin
            if (h_count == H_TOTAL - 1)
                h_count <= 10'd0;
            else
                h_count <= h_count + 1'b1;
        end
    end

    //-------------------------------------------------------------------------
    // Vertical counter
    //-------------------------------------------------------------------------
    always_ff @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            v_count <= 10'd0;
        end else begin
            if (h_count == H_TOTAL - 1) begin
                if (v_count == V_TOTAL - 1)
                    v_count <= 10'd0;
                else
                    v_count <= v_count + 1'b1;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Sync generation
    // Note: VGA standard has negative polarity syncs, but ADV7511
    // can be configured for either. We output directly active high.
    //-------------------------------------------------------------------------
    assign hsync = (h_count >= H_SYNC_START) && (h_count < H_SYNC_END);
    assign vsync = (v_count >= V_SYNC_START) && (v_count < V_SYNC_END);

    //-------------------------------------------------------------------------
    // Data enable - active during visible area
    //-------------------------------------------------------------------------
    assign data_enable = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);

    //-------------------------------------------------------------------------
    // Pixel coordinates (valid during active region)
    //-------------------------------------------------------------------------
    assign pixel_x = h_count;
    assign pixel_y = v_count;

    //-------------------------------------------------------------------------
    // Frame/line timing pulses
    //-------------------------------------------------------------------------
    assign frame_start = (h_count == 0) && (v_count == 0);
    assign line_start = (h_count == 0);

endmodule
