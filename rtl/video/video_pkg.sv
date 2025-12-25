// Celery3D GPU - Video Output Package
// Timing parameters for HDMI/VGA output
// Target: 640x480 @ 60Hz via ADV7511 on KC705

package video_pkg;

    // =========================================================================
    // Video Timing Parameters (640x480 @ 60Hz)
    // Pixel clock: 25.175 MHz (using 25 MHz for simplicity)
    // =========================================================================

    // Horizontal timing (in pixels)
    parameter H_ACTIVE      = 640;   // Visible pixels per line
    parameter H_FRONT_PORCH = 16;    // After active, before sync
    parameter H_SYNC_PULSE  = 96;    // Sync pulse width
    parameter H_BACK_PORCH  = 48;    // After sync, before active
    parameter H_TOTAL       = 800;   // Total pixels per line

    // Vertical timing (in lines)
    parameter V_ACTIVE      = 480;   // Visible lines per frame
    parameter V_FRONT_PORCH = 10;    // After active, before sync
    parameter V_SYNC_PULSE  = 2;     // Sync pulse width
    parameter V_BACK_PORCH  = 33;    // After sync, before active
    parameter V_TOTAL       = 525;   // Total lines per frame

    // Sync polarities (active low for 640x480)
    parameter H_SYNC_POL    = 1'b0;  // HSYNC active low
    parameter V_SYNC_POL    = 1'b0;  // VSYNC active low

    // Derived timing positions
    parameter H_SYNC_START  = H_ACTIVE + H_FRONT_PORCH;
    parameter H_SYNC_END    = H_SYNC_START + H_SYNC_PULSE;
    parameter V_SYNC_START  = V_ACTIVE + V_FRONT_PORCH;
    parameter V_SYNC_END    = V_SYNC_START + V_SYNC_PULSE;

    // Counter bit widths
    parameter H_COUNT_BITS  = $clog2(H_TOTAL);   // 10 bits
    parameter V_COUNT_BITS  = $clog2(V_TOTAL);   // 10 bits

    // =========================================================================
    // ADV7511 Configuration
    // =========================================================================

    // I2C address (7-bit)
    parameter ADV7511_I2C_ADDR = 7'h39;

    // Number of registers to configure
    parameter ADV7511_REG_COUNT = 18;

    // =========================================================================
    // Color Types
    // =========================================================================

    typedef logic [7:0] y_t;     // Luminance
    typedef logic [7:0] cb_t;    // Blue chrominance
    typedef logic [7:0] cr_t;    // Red chrominance

    // YCbCr 4:2:2 output (16-bit packed)
    // Even pixels: {Cb, Y0}
    // Odd pixels:  {Cr, Y1}
    typedef logic [15:0] ycbcr422_t;

endpackage
