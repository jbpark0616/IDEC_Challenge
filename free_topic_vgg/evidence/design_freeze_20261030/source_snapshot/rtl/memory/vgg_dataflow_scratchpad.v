`default_nettype none
// U: banks 0..3. V/line history: banks 4..7.
// Optional legacy activation: banks 8..11. The main cluster disables these
// four instances and uses vgg_activation_sram for its A/B activation banks.
// Independent clients, no shared local-port FSM.
// The layer's CB ownership prevents host/internal writes to live data.
// V writer versus MAC uses alternating priority under sustained contention.
module vgg_dataflow_scratchpad #(parameter SRAM_LINES=0, INTERNAL_ACTIVATION=1) (
    input wire clk, rst_n,

    // Circular line-buffer client; banks 4..7, words 512..1023 only.
    input wire line_valid, line_write,
    output wire line_ready,
    input wire [8:0] line_addr,
    input wire [255:0] line_wdata,
    output wire line_rvalid,
    input wire line_rready,
    output wire [255:0] line_rdata,

    input wire [3:0] row_read, v_read_enable,
    output wire row_accept,
    input wire [39:0] u_addr, v_addr,
    output wire [255:0] u_data, v_data,

    input wire [3:0] p_valid,
    output wire [3:0] p_ready,
    input wire [9:0] p_addr,
    input wire [255:0] p_data,

    input wire x_valid, x_slot,
    output wire x_ready,
    input wire [9:0] x_addr,
    output reg x_rvalid,
    input wire x_rready,
    output reg [63:0] x_rdata,

    input wire y_valid, y_slot,
    output wire y_ready,
    input wire [9:0] y_addr,
    input wire [63:0] y_data,

    input wire host_valid, host_write,
    output wire host_ready,
    input wire [3:0] host_bank,
    input wire [9:0] host_addr,
    input wire [63:0] host_wdata,
    output reg host_rvalid,
    input wire host_rready,
    output reg [63:0] host_rdata,
    output wire host_idle,
    output reg [31:0] v_conflict_cycles,
    output reg [31:0] parallel_cycles
);
    wire [767:0] bank_rdata;
    reg [3:0] prefer_writer;
    reg x_pending, x_read_slot, host_pending;
    reg [3:0] host_read_bank;
    reg prefer_line, line_pending, line_response_valid;
    reg [255:0] line_response_data;
    wire compute_request = (|row_read) || (|p_valid);
    wire line_can_accept = !line_pending && !line_response_valid;
    assign line_ready = SRAM_LINES && line_can_accept && (!compute_request || prefer_line);
    wire line_fire = SRAM_LINES && line_valid && line_ready;
    assign line_rvalid = SRAM_LINES && line_response_valid;
    assign line_rdata = line_response_data;
    wire [3:0] collision = p_valid & row_read;
    wire writer_wins = |(collision & prefer_writer);
    assign row_accept = !writer_wins && !line_fire;
    assign p_ready = (~row_read | {4{writer_wins}}) & {4{!line_fire}};
    wire [3:0] p_fire = p_valid & p_ready;
    assign x_ready = !x_pending && !x_rvalid;
    assign y_ready = 1'b1;
    wire x_fire = x_valid && x_ready;
    wire y_fire = y_valid && y_ready;
    wire [3:0] x_bank = {3'b100, x_slot};
    wire [3:0] y_bank = {3'b101, y_slot};
    wire [11:0] internal_access;
    assign host_ready = host_bank < (INTERNAL_ACTIVATION ? 12 : 8) && !host_pending && !host_rvalid
                      && !internal_access[host_bank];
    assign host_idle = !host_pending && !host_rvalid;
    wire host_fire = host_valid && host_ready;
    wire host_read_fire = host_fire && !host_write;
    wire [3:0] accepted_rows = row_read & {4{row_accept}};
    assign u_data = bank_rdata[255:0];
    assign v_data = bank_rdata[511:256];

    genvar b;
    generate for (b=0; b<12; b=b+1) begin : g_bank
        // Elaboration-time roles: no runtime bank-type decoder is needed.
        wire engine_read;
        wire [9:0] engine_addr;
        wire producer_write;
        wire [63:0] producer_data;
        wire line_access;
        wire [63:0] line_data;
        if (b<4) begin : g_u
            assign engine_read = accepted_rows[b];
            assign engine_addr = u_addr[b*10 +: 10];
            assign producer_write = 1'b0;
            assign producer_data = 64'b0;
            assign line_access = 1'b0;
            assign line_data = 64'b0;
        end else if (b<8) begin : g_v
            assign engine_read = accepted_rows[b-4] && v_read_enable[b-4];
            assign engine_addr = v_addr[(b-4)*10 +: 10];
            assign producer_write = p_fire[b-4];
            assign producer_data = p_data[(b-4)*64 +: 64];
            assign line_access = line_fire;
            assign line_data = line_wdata[(b-4)*64 +: 64];
        end else begin : g_io
            assign engine_read = 1'b0;
            assign engine_addr = 10'b0;
            assign producer_write = 1'b0;
            assign producer_data = 64'b0;
            assign line_access = 1'b0;
            assign line_data = 64'b0;
        end
        wire line_read = line_access && !line_write;
        wire line_store = line_access && line_write;
        wire source_read = x_fire && b == x_bank;
        wire output_write = y_fire && b == y_bank;
        assign internal_access[b] = engine_read || producer_write || source_read || output_write || line_access;
        wire selected = host_fire && host_bank == b;
        wire rd_en = line_read || engine_read || source_read || (selected && !host_write);
        wire wr_en = line_store || producer_write || output_write || (selected && host_write);
        wire [9:0] addr = line_access ? {1'b1,line_addr} : engine_read ? engine_addr :
                           producer_write ? p_addr : source_read ? x_addr :
                           output_write ? y_addr : host_addr;
        wire [63:0] data = line_store ? line_data : producer_write ? producer_data : output_write ? y_data : host_wdata;
        if (b<8 || INTERNAL_ACTIVATION!=0) begin : g_physical
            vgg_sram_8k u_bank (
                .clk(clk), .en(rd_en || wr_en), .rd_en(rd_en), .wr_en(wr_en),
                .addr(addr), .wdata(data), .rdata(bank_rdata[b*64 +: 64])
            );
        end else begin : g_external_activation
            assign bank_rdata[b*64 +: 64] = 64'b0;
        end
    end endgenerate

    // Capture read responses before another client can overwrite a bank's
    // read-data register. Writes leave the macro read-data register unchanged.
    always @(posedge clk) begin
        if (line_pending) line_response_data <= bank_rdata[511:256];
        if (x_fire) x_read_slot <= x_slot;
        if (x_pending) x_rdata <= bank_rdata[(8+x_read_slot)*64 +: 64];
        if (host_read_fire) host_read_bank <= host_bank;
        if (host_pending) host_rdata <= bank_rdata[host_read_bank*64 +: 64];
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prefer_line <= 0;
            line_pending <= 0;
            line_response_valid <= 0;
            prefer_writer <= 0;
            x_pending <= 0;
            x_rvalid <= 0;
            host_pending <= 0;
            host_rvalid <= 0;
            v_conflict_cycles <= 0;
            parallel_cycles <= 0;
        end else begin
            line_pending <= line_fire && !line_write;
            if (line_response_valid && line_rready) line_response_valid <= 0;
            if (line_pending) line_response_valid <= 1;
            if (SRAM_LINES && line_valid && line_can_accept && compute_request)
                prefer_line <= !line_fire;
            x_pending <= x_fire;
            host_pending <= host_read_fire;
            if (x_rvalid && x_rready) x_rvalid <= 0;
            if (x_pending) x_rvalid <= 1;
            if (host_rvalid && host_rready) host_rvalid <= 0;
            if (host_pending) host_rvalid <= 1;
            if (|collision && !line_fire) begin
                prefer_writer <= (prefer_writer & ~collision) | ({4{!writer_wins}} & collision);
                v_conflict_cycles <= v_conflict_cycles + 1'b1;
            end
            if (((|row_read) && row_accept && (x_fire || y_fire || (|p_fire))) ||
                (x_fire && (y_fire || (|p_fire))) || (y_fire && (|p_fire)))
                parallel_cycles <= parallel_cycles + 1'b1;
        end
    end
endmodule
`default_nettype wire
