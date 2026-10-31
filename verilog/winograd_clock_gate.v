`timescale 1ns/1ps
// Latch-based glitch-free gate. Control/valid logic must use the root clock.
module winograd_clock_gate(input wire clk, input wire enable, output wire gclk);
`ifdef CLOCK_GATING_BYPASS
    assign gclk = clk;
`elsif SYNTHESIS
    // The platform map must be enabled with -DOPENROAD_CLKGATE.
    OPENROAD_CLKGATE u_icg (.CK(clk), .E(enable), .GCK(gclk));
`else
    reg enable_latched;
    always @* if (!clk) enable_latched = enable;
    assign gclk = clk & enable_latched;
`endif
endmodule
