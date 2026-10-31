// Synthesis harness: unchanged compute core plus its 12 SRAM banks.
// Single-core cluster shell included; not an estimate of 16-core interconnect.
`default_nettype none
module vgg_single_core_synth #(
    parameter integer HEIGHT=32, WIDTH=32,
    parameter RETAIN_V=1'b1,
    // Current target stores signed INT8 U. Set 0 only for legacy U16 vectors.
    // Frozen application default: U8/V8. Override only for numerical regression.
    parameter integer V8_PACKED=1,
    parameter integer U8_PACKED=1,
    parameter ENABLE_FC=1
) (
    input wire clk, rst_n,
    input wire host_valid,
    output wire host_ready,
    input wire host_write,
    input wire [0:0] host_core,
    input wire [3:0] host_bank,
    input wire [9:0] host_addr,
    input wire [63:0] host_wdata,
    output wire host_rvalid,
    input wire host_rready,
    output wire [63:0] host_rdata,

    input wire cmd_fc, cmd_fc_final,
    output wire class_valid,
    output wire [3:0] class_index,
    input wire cmd_valid,
    output wire cmd_ready,
    input wire cmd_phase, cmd_sharded,
    input wire [5:0] cmd_height, cmd_width,
    input wire [10:0] cmd_input_base, cmd_output_base,
    input wire [9:0] cmd_channels,
    input wire [7:0] cmd_shard_channels,
    input wire [3:0] cmd_outputs,
    // Block mode retains the input until every local output channel is written.
    // cmd_output_base addresses the whole region, not the individual block.
    input wire [7:0] cmd_output_total, cmd_output_offset,
    input wire cmd_pooling, cmd_sparse,
    input wire cmd_input_signed,
    input wire [1*256-1:0] cmd_biases,
    input wire [1*192-1:0] cmd_multipliers,
    input wire [1*24-1:0] cmd_u_shifts,
    output wire done_valid,
    input wire done_ready,
    output wire done_error,
    output wire [31:0] total_cycles,
    output wire [1*32-1:0] core_cycles, mac_row_issues,
    output wire [1*15-1:0] output_bytes,
    output wire [31:0] source_reads, stream_words,
    output wire [1:0] committed_regions
);
    vgg_single_core_shell #(
        .ENABLE_FC(ENABLE_FC), .HEIGHT(HEIGHT), .WIDTH(WIDTH), .CORES(1), .CORE_BITS(1), .BLOCK_COMMANDS(1),
        .RETAIN_V(RETAIN_V), .U8_PACKED(U8_PACKED), .V8_PACKED(V8_PACKED), .CHANNEL_BITS(9)
    ) u_cluster (
        .clk(clk),
        .rst_n(rst_n),
        .host_valid(host_valid),
        .host_ready(host_ready),
        .host_write(host_write),
        .host_core(host_core),
        .host_bank(host_bank),
        .host_addr(host_addr),
        .host_wdata(host_wdata),
        .host_rvalid(host_rvalid),
        .host_rready(host_rready),
        .host_rdata(host_rdata),
        .cmd_fc(cmd_fc),.cmd_fc_final(cmd_fc_final),.class_valid(class_valid),.class_index(class_index),
        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_phase(cmd_phase),
        .cmd_sharded(cmd_sharded),
        .cmd_height(cmd_height),
        .cmd_width(cmd_width),
        .cmd_input_base(cmd_input_base),
        .cmd_output_base(cmd_output_base),
        .cmd_channels(cmd_channels),
        .cmd_shard_channels(cmd_shard_channels),
        .cmd_outputs(cmd_outputs),
        .cmd_output_total(cmd_output_total),
        .cmd_output_offset(cmd_output_offset),
        .cmd_pooling(cmd_pooling),
        .cmd_sparse(cmd_sparse),
        .cmd_input_signed(cmd_input_signed),
        .cmd_biases(cmd_biases),
        .cmd_multipliers(cmd_multipliers),
        .cmd_u_shifts(cmd_u_shifts),
        .done_valid(done_valid),
        .done_ready(done_ready),
        .done_error(done_error),
        .total_cycles(total_cycles),
        .core_cycles(core_cycles),
        .mac_row_issues(mac_row_issues),
        .output_bytes(output_bytes),
        .source_reads(source_reads),
        .stream_words(stream_words),
        .committed_regions(committed_regions)
    );
endmodule
`default_nettype wire
