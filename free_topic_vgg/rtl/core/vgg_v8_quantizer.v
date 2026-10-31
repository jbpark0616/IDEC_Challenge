`default_nettype none
// Same signed round-half-up and symmetric saturation as uv_common.quant_v.
// Values remain sign-extended on the boundary bus; SRAM packs their low bytes.
module vgg_v8_quantizer (
    input wire [255:0] in_tile,
    input wire [2:0] shift,
    output wire [255:0] out_tile,
    output wire [3:0] zero_rows
);
    genvar i,r;
    generate for(i=0;i<16;i=i+1) begin : g_value
        wire signed [16:0] value={{1{in_tile[i*16+15]}},in_tile[i*16 +:16]};
        wire signed [16:0] rounded=(value + (shift==0 ? 17'sd0 : (17'sd1 << (shift-1'b1)))) >>> shift;
        wire signed [7:0] quantized=rounded>127 ? 8'sd127 : rounded < -127 ? -8'sd127 : rounded[7:0];
        assign out_tile[i*16 +:16]={{8{quantized[7]}},quantized};
    end
    for(r=0;r<4;r=r+1) begin : g_zero
        assign zero_rows[r]=~|out_tile[r*64 +:64];
    end endgenerate
endmodule
`default_nettype wire
