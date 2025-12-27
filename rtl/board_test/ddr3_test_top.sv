// DDR3 Memory Test for KC705
// Simple write/read verification using AXI4 interface to MIG controller
// LEDs show: calibration status, test progress, pass/fail

module ddr3_test_top (
    // 200 MHz differential system clock
    input  logic        sys_clk_p,
    input  logic        sys_clk_n,

    // System reset button (active-low from KC705 SW4 South)
    input  logic        sys_rst_n,

    // DDR3 SDRAM interface
    inout  [63:0]       ddr3_dq,
    inout  [7:0]        ddr3_dqs_n,
    inout  [7:0]        ddr3_dqs_p,
    output [13:0]       ddr3_addr,
    output [2:0]        ddr3_ba,
    output              ddr3_ras_n,
    output              ddr3_cas_n,
    output              ddr3_we_n,
    output              ddr3_reset_n,
    output [0:0]        ddr3_ck_p,
    output [0:0]        ddr3_ck_n,
    output [0:0]        ddr3_cke,
    output [0:0]        ddr3_cs_n,
    output [7:0]        ddr3_dm,
    output [0:0]        ddr3_odt,

    // 8 GPIO LEDs
    output logic [7:0]  gpio_led
);

    // =========================================================================
    // MIG signals
    // =========================================================================
    logic        ui_clk;
    logic        ui_clk_sync_rst;
    logic        mmcm_locked;
    logic        init_calib_complete;
    logic [11:0] device_temp;

    // AXI4 Write Address Channel
    logic [3:0]   s_axi_awid;
    logic [29:0]  s_axi_awaddr;
    logic [7:0]   s_axi_awlen;
    logic [2:0]   s_axi_awsize;
    logic [1:0]   s_axi_awburst;
    logic [0:0]   s_axi_awlock;
    logic [3:0]   s_axi_awcache;
    logic [2:0]   s_axi_awprot;
    logic [3:0]   s_axi_awqos;
    logic         s_axi_awvalid;
    logic         s_axi_awready;

    // AXI4 Write Data Channel
    logic [255:0] s_axi_wdata;
    logic [31:0]  s_axi_wstrb;
    logic         s_axi_wlast;
    logic         s_axi_wvalid;
    logic         s_axi_wready;

    // AXI4 Write Response Channel
    logic [3:0]   s_axi_bid;
    logic [1:0]   s_axi_bresp;
    logic         s_axi_bvalid;
    logic         s_axi_bready;

    // AXI4 Read Address Channel
    logic [3:0]   s_axi_arid;
    logic [29:0]  s_axi_araddr;
    logic [7:0]   s_axi_arlen;
    logic [2:0]   s_axi_arsize;
    logic [1:0]   s_axi_arburst;
    logic [0:0]   s_axi_arlock;
    logic [3:0]   s_axi_arcache;
    logic [2:0]   s_axi_arprot;
    logic [3:0]   s_axi_arqos;
    logic         s_axi_arvalid;
    logic         s_axi_arready;

    // AXI4 Read Data Channel
    logic [3:0]   s_axi_rid;
    logic [255:0] s_axi_rdata;
    logic [1:0]   s_axi_rresp;
    logic         s_axi_rlast;
    logic         s_axi_rvalid;
    logic         s_axi_rready;

    // =========================================================================
    // Test state machine
    // =========================================================================
    typedef enum logic [3:0] {
        ST_WAIT_CALIB,
        ST_WRITE_ADDR,
        ST_WRITE_DATA,
        ST_WRITE_RESP,
        ST_READ_ADDR,
        ST_READ_DATA,
        ST_CHECK,
        ST_NEXT_ADDR,
        ST_PASS,
        ST_FAIL
    } state_t;

    state_t state, next_state;

    // Test parameters
    localparam TEST_COUNT = 256;           // Number of 256-bit words to test
    localparam ADDR_INCREMENT = 32;        // 256 bits = 32 bytes per transfer

    logic [29:0] test_addr;
    logic [15:0] test_count;
    logic [255:0] write_data;
    logic [255:0] read_data;
    logic [255:0] expected_data;
    logic         compare_error;

    // Heartbeat counter for LED animation
    logic [25:0] heartbeat_cnt;

    // =========================================================================
    // MIG instantiation
    // =========================================================================
    mig_7series_0 u_mig (
        // DDR3 interface
        .ddr3_dq            (ddr3_dq),
        .ddr3_dqs_n         (ddr3_dqs_n),
        .ddr3_dqs_p         (ddr3_dqs_p),
        .ddr3_addr          (ddr3_addr),
        .ddr3_ba            (ddr3_ba),
        .ddr3_ras_n         (ddr3_ras_n),
        .ddr3_cas_n         (ddr3_cas_n),
        .ddr3_we_n          (ddr3_we_n),
        .ddr3_reset_n       (ddr3_reset_n),
        .ddr3_ck_p          (ddr3_ck_p),
        .ddr3_ck_n          (ddr3_ck_n),
        .ddr3_cke           (ddr3_cke),
        .ddr3_cs_n          (ddr3_cs_n),
        .ddr3_dm            (ddr3_dm),
        .ddr3_odt           (ddr3_odt),

        // System clock
        .sys_clk_p          (sys_clk_p),
        .sys_clk_n          (sys_clk_n),

        // User interface clock and reset
        .ui_clk             (ui_clk),
        .ui_clk_sync_rst    (ui_clk_sync_rst),
        .mmcm_locked        (mmcm_locked),

        // Reset and calibration
        .aresetn            (~ui_clk_sync_rst),
        .sys_rst            (~sys_rst_n),  // Invert: button is active-low, MIG expects active-high
        .init_calib_complete(init_calib_complete),
        .device_temp        (device_temp),

        // Self-refresh, refresh, ZQ calibration requests (unused)
        .app_sr_req         (1'b0),
        .app_ref_req        (1'b0),
        .app_zq_req         (1'b0),
        .app_sr_active      (),
        .app_ref_ack        (),
        .app_zq_ack         (),

        // AXI4 Write Address Channel
        .s_axi_awid         (s_axi_awid),
        .s_axi_awaddr       (s_axi_awaddr),
        .s_axi_awlen        (s_axi_awlen),
        .s_axi_awsize       (s_axi_awsize),
        .s_axi_awburst      (s_axi_awburst),
        .s_axi_awlock       (s_axi_awlock),
        .s_axi_awcache      (s_axi_awcache),
        .s_axi_awprot       (s_axi_awprot),
        .s_axi_awqos        (s_axi_awqos),
        .s_axi_awvalid      (s_axi_awvalid),
        .s_axi_awready      (s_axi_awready),

        // AXI4 Write Data Channel
        .s_axi_wdata        (s_axi_wdata),
        .s_axi_wstrb        (s_axi_wstrb),
        .s_axi_wlast        (s_axi_wlast),
        .s_axi_wvalid       (s_axi_wvalid),
        .s_axi_wready       (s_axi_wready),

        // AXI4 Write Response Channel
        .s_axi_bid          (s_axi_bid),
        .s_axi_bresp        (s_axi_bresp),
        .s_axi_bvalid       (s_axi_bvalid),
        .s_axi_bready       (s_axi_bready),

        // AXI4 Read Address Channel
        .s_axi_arid         (s_axi_arid),
        .s_axi_araddr       (s_axi_araddr),
        .s_axi_arlen        (s_axi_arlen),
        .s_axi_arsize       (s_axi_arsize),
        .s_axi_arburst      (s_axi_arburst),
        .s_axi_arlock       (s_axi_arlock),
        .s_axi_arcache      (s_axi_arcache),
        .s_axi_arprot       (s_axi_arprot),
        .s_axi_arqos        (s_axi_arqos),
        .s_axi_arvalid      (s_axi_arvalid),
        .s_axi_arready      (s_axi_arready),

        // AXI4 Read Data Channel
        .s_axi_rid          (s_axi_rid),
        .s_axi_rdata        (s_axi_rdata),
        .s_axi_rresp        (s_axi_rresp),
        .s_axi_rlast        (s_axi_rlast),
        .s_axi_rvalid       (s_axi_rvalid),
        .s_axi_rready       (s_axi_rready)
    );

    // =========================================================================
    // Test pattern generation - simple walking 1s + address-based pattern
    // =========================================================================
    function automatic [255:0] generate_pattern(input [29:0] addr);
        logic [255:0] pattern;
        // Mix address bits into pattern for better coverage
        for (int i = 0; i < 8; i++) begin
            pattern[i*32 +: 32] = {addr[15:0], 8'hA5, 5'b0, i[2:0]} ^ {2{addr[15:0]}};
        end
        return pattern;
    endfunction

    // =========================================================================
    // State machine
    // =========================================================================
    always_ff @(posedge ui_clk) begin
        if (ui_clk_sync_rst) begin
            state <= ST_WAIT_CALIB;
            test_addr <= '0;
            test_count <= '0;
            compare_error <= 1'b0;
            heartbeat_cnt <= '0;
        end else begin
            state <= next_state;
            heartbeat_cnt <= heartbeat_cnt + 1'b1;

            case (state)
                ST_WAIT_CALIB: begin
                    test_addr <= '0;
                    test_count <= '0;
                    compare_error <= 1'b0;
                end

                ST_WRITE_ADDR: begin
                    write_data <= generate_pattern(test_addr);
                end

                ST_WRITE_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        // Check for write errors
                        if (s_axi_bresp != 2'b00) begin
                            compare_error <= 1'b1;
                        end
                    end
                end

                ST_READ_DATA: begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        read_data <= s_axi_rdata;
                        expected_data <= generate_pattern(test_addr);
                    end
                end

                ST_CHECK: begin
                    if (read_data != expected_data) begin
                        compare_error <= 1'b1;
                    end
                end

                ST_NEXT_ADDR: begin
                    test_addr <= test_addr + ADDR_INCREMENT;
                    test_count <= test_count + 1'b1;
                end

                default: ;
            endcase
        end
    end

    always_comb begin
        next_state = state;

        case (state)
            ST_WAIT_CALIB: begin
                if (init_calib_complete)
                    next_state = ST_WRITE_ADDR;
            end

            ST_WRITE_ADDR: begin
                if (s_axi_awvalid && s_axi_awready)
                    next_state = ST_WRITE_DATA;
            end

            ST_WRITE_DATA: begin
                if (s_axi_wvalid && s_axi_wready)
                    next_state = ST_WRITE_RESP;
            end

            ST_WRITE_RESP: begin
                if (s_axi_bvalid && s_axi_bready)
                    next_state = ST_READ_ADDR;
            end

            ST_READ_ADDR: begin
                if (s_axi_arvalid && s_axi_arready)
                    next_state = ST_READ_DATA;
            end

            ST_READ_DATA: begin
                if (s_axi_rvalid && s_axi_rready)
                    next_state = ST_CHECK;
            end

            ST_CHECK: begin
                if (compare_error)
                    next_state = ST_FAIL;
                else
                    next_state = ST_NEXT_ADDR;
            end

            ST_NEXT_ADDR: begin
                if (test_count >= TEST_COUNT - 1)
                    next_state = ST_PASS;
                else
                    next_state = ST_WRITE_ADDR;
            end

            ST_PASS: next_state = ST_PASS;  // Stay in pass
            ST_FAIL: next_state = ST_FAIL;  // Stay in fail

            default: next_state = ST_WAIT_CALIB;
        endcase
    end

    // =========================================================================
    // AXI4 signal assignments
    // =========================================================================

    // Write Address Channel
    assign s_axi_awid    = 4'd0;
    assign s_axi_awaddr  = test_addr;
    assign s_axi_awlen   = 8'd0;           // Single beat
    assign s_axi_awsize  = 3'b101;         // 32 bytes (256 bits)
    assign s_axi_awburst = 2'b01;          // INCR
    assign s_axi_awlock  = 1'b0;
    assign s_axi_awcache = 4'b0011;        // Normal, non-cacheable, bufferable
    assign s_axi_awprot  = 3'b000;
    assign s_axi_awqos   = 4'd0;
    assign s_axi_awvalid = (state == ST_WRITE_ADDR);

    // Write Data Channel
    assign s_axi_wdata   = write_data;
    assign s_axi_wstrb   = 32'hFFFFFFFF;   // All bytes valid
    assign s_axi_wlast   = 1'b1;           // Single beat, always last
    assign s_axi_wvalid  = (state == ST_WRITE_DATA);

    // Write Response Channel
    assign s_axi_bready  = (state == ST_WRITE_RESP);

    // Read Address Channel
    assign s_axi_arid    = 4'd0;
    assign s_axi_araddr  = test_addr;
    assign s_axi_arlen   = 8'd0;           // Single beat
    assign s_axi_arsize  = 3'b101;         // 32 bytes (256 bits)
    assign s_axi_arburst = 2'b01;          // INCR
    assign s_axi_arlock  = 1'b0;
    assign s_axi_arcache = 4'b0011;
    assign s_axi_arprot  = 3'b000;
    assign s_axi_arqos   = 4'd0;
    assign s_axi_arvalid = (state == ST_READ_ADDR);

    // Read Data Channel
    assign s_axi_rready  = (state == ST_READ_DATA);

    // =========================================================================
    // LED display
    // =========================================================================
    // LED[0] = MMCM locked
    // LED[1] = Calibration complete
    // LED[2] = Test running (heartbeat)
    // LED[3] = Test in progress indicator
    // LED[4] = Progress bit 0
    // LED[5] = Progress bit 1
    // LED[6] = PASS (steady on)
    // LED[7] = FAIL (steady on)

    always_comb begin
        gpio_led[0] = mmcm_locked;
        gpio_led[1] = init_calib_complete;
        gpio_led[2] = (state != ST_WAIT_CALIB && state != ST_PASS && state != ST_FAIL)
                      ? heartbeat_cnt[23] : 1'b0;
        gpio_led[3] = (state != ST_WAIT_CALIB && state != ST_PASS && state != ST_FAIL);
        gpio_led[4] = test_count[6];
        gpio_led[5] = test_count[7];
        gpio_led[6] = (state == ST_PASS);
        gpio_led[7] = (state == ST_FAIL);
    end

endmodule
