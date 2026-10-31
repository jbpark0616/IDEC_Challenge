`default_nettype none
// Two-level priority encoder (8 groups x 16 bits), not a 128-deep priority chain.
module vgg_first_one128 (
    input wire [127:0] bits,
    output wire valid, output wire [6:0] index,
    output wire [127:0] onehot
);
    wire [7:0] group_valid;
    reg [2:0] group_index;
    reg [3:0] bit_index;
    wire [15:0] group_bits = bits[group_index*16 +: 16];
    genvar g;
    generate for (g=0; g<8; g=g+1) begin : g_group
        assign group_valid[g] = |bits[g*16 +: 16];
    end endgenerate
    always @* begin
        casez (group_valid)
            8'b???????1: group_index=0;
            8'b??????10: group_index=1;
            8'b?????100: group_index=2;
            8'b????1000: group_index=3;
            8'b???10000: group_index=4;
            8'b??100000: group_index=5;
            8'b?1000000: group_index=6;
            default: group_index=7;
        endcase
        casez (group_bits)
            16'b???????????????1: bit_index=0;
            16'b??????????????10: bit_index=1;
            16'b?????????????100: bit_index=2;
            16'b????????????1000: bit_index=3;
            16'b???????????10000: bit_index=4;
            16'b??????????100000: bit_index=5;
            16'b?????????1000000: bit_index=6;
            16'b????????10000000: bit_index=7;
            16'b???????100000000: bit_index=8;
            16'b??????1000000000: bit_index=9;
            16'b?????10000000000: bit_index=10;
            16'b????100000000000: bit_index=11;
            16'b???1000000000000: bit_index=12;
            16'b??10000000000000: bit_index=13;
            16'b?100000000000000: bit_index=14;
            default: bit_index=15;
        endcase
    end
    assign valid = |group_valid;
    assign index = {group_index,bit_index};
    generate for (g=0; g<128; g=g+1) begin : g_decode
        assign onehot[g] = valid && index == g;
    end endgenerate
endmodule

// Four existing 128-bit trees cover 512 channels; no linear 512-way priority
// chain. The default configuration is exactly the original 128-bit selector.
module vgg_first_one_channels #(
    parameter integer CHANNEL_BITS=7
) (
    input wire [(1<<CHANNEL_BITS)-1:0] bits,
    output wire valid,
    output wire [CHANNEL_BITS-1:0] index,
    output wire [(1<<CHANNEL_BITS)-1:0] onehot
);
    genvar g;
    generate if(CHANNEL_BITS==7) begin : g_128
        vgg_first_one128 u_pick(.bits(bits), .valid(valid), .index(index), .onehot(onehot));
    end else begin : g_512
        wire [3:0] group_valid;
        wire [27:0] group_index;
        wire [511:0] group_onehot;
        wire [1:0] selected = group_valid[0] ? 2'd0 : group_valid[1] ? 2'd1
                           : group_valid[2] ? 2'd2 : 2'd3;
        assign valid=|group_valid;
        assign index={selected,group_index[selected*7 +: 7]};
        for(g=0;g<4;g=g+1) begin : g_group
            vgg_first_one128 u_pick(.bits(bits[g*128 +: 128]), .valid(group_valid[g]),
                .index(group_index[g*7 +: 7]), .onehot(group_onehot[g*128 +: 128]));
            assign onehot[g*128 +: 128]=group_onehot[g*128 +: 128] & {128{selected==g}};
        end
    end endgenerate
endmodule
`default_nettype wire
