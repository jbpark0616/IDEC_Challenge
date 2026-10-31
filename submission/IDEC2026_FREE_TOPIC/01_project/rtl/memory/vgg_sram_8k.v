// One 1024 x 64 single-port synchronous SRAM. No byte-write mask or reset.
// Address is a 64-bit WORD index. Read output holds when no read is issued.
// Caller must not assert rd_en and wr_en together when en is high.
// Compile the vendor behavioral model ONLY for simulation; use Liberty as a
// blackbox for synthesis so this array remains a physical SRAM instance.
module vgg_sram_8k (
    input wire clk,
    input wire en,
    input wire rd_en,
    input wire wr_en,
    input wire [9:0] addr,
    input wire [63:0] wdata,
    output wire [63:0] rdata
);
    srambank_256x4x64_6t122 u_sram (
        .clk(clk), .ADDRESS(addr), .wd(wdata), .banksel(en),
        .read(rd_en), .write(wr_en), .dataout(rdata)
    );
endmodule
