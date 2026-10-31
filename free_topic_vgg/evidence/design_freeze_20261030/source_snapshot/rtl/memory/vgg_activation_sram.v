`default_nettype none
// Four 8KiB 1RW activation banks (local IDs 0..3, corresponding to banks 8..11).
// No X/Y role is hardwired. The CB owner supplies physical bank/word addresses.
// This boundary has no allocator and does not reset or duplicate payload SRAM.
//
// Clients: host read/write; multicast source read; compute output write.
// Different banks operate concurrently. Each bank has a 3-client round robin.
// Read data stays in the macro's output register until the receiver accepts it;
// writes to that bank do not change that register in the provided SRAM model.
module vgg_activation_sram (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         host_valid,
    output wire         host_ready,
    input  wire         host_write,
    input  wire [1:0]   host_bank,
    input  wire [9:0]   host_addr,
    input  wire [63:0]  host_wdata,
    output reg          host_rvalid,
    input  wire         host_rready,
    output wire [63:0]  host_rdata,

    input  wire         tx_valid,
    output wire         tx_ready,
    input  wire [1:0]   tx_bank,
    input  wire [9:0]   tx_addr,
    output reg          tx_rvalid,
    input  wire         tx_rready,
    output wire [63:0]  tx_rdata,

    input  wire         writer_valid,
    output wire         writer_ready,
    input  wire [1:0]   writer_bank,
    input  wire [9:0]   writer_addr,
    input  wire [63:0]  writer_data
);
    wire [255:0] bank_rdata;
    wire [3:0] host_grant, tx_grant, writer_grant;
    reg [1:0] host_response_bank, tx_response_bank;

    // A pending read protects the bank output register from ANY new read,
    // including another client, until the old response has been accepted.
    wire host_holding = host_rvalid && !host_rready;
    wire tx_holding = tx_rvalid && !tx_rready;
    wire host_can_request = host_write || !host_holding;
    wire tx_can_request = !tx_holding;
    assign host_ready = |host_grant;
    assign tx_ready = |tx_grant;
    assign writer_ready = |writer_grant;
    assign host_rdata = bank_rdata[host_response_bank*64 +: 64];
    assign tx_rdata = bank_rdata[tx_response_bank*64 +: 64];

    genvar b;
    generate for (b=0; b<4; b=b+1) begin : g_bank
        localparam [1:0] BANK_ID = b;
        localparam [1:0] HOST=2'd0, TX=2'd1, WRITER=2'd2;
        reg [1:0] priority_client;
        reg [2:0] grant;

        wire read_locked = (host_holding && host_response_bank == BANK_ID)
                        || (tx_holding && tx_response_bank == BANK_ID);
        wire request_host = rst_n && host_valid && host_bank == BANK_ID
                         && host_can_request && (host_write || !read_locked);
        wire request_tx = rst_n && tx_valid && tx_bank == BANK_ID
                       && tx_can_request && !read_locked;
        wire request_writer = rst_n && writer_valid && writer_bank == BANK_ID;

        // Fixed-size priority MUX, rather than a wide runtime search network.
        always @* begin
            grant = 3'b000;
            case (priority_client)
                TX: begin
                    if      (request_tx)     grant = 3'b010;
                    else if (request_writer) grant = 3'b100;
                    else if (request_host)   grant = 3'b001;
                end
                WRITER: begin
                    if      (request_writer) grant = 3'b100;
                    else if (request_host)   grant = 3'b001;
                    else if (request_tx)     grant = 3'b010;
                end
                default: begin
                    if      (request_host)   grant = 3'b001;
                    else if (request_tx)     grant = 3'b010;
                    else if (request_writer) grant = 3'b100;
                end
            endcase
        end

        assign host_grant[b] = grant[0];
        assign tx_grant[b] = grant[1];
        assign writer_grant[b] = grant[2];
        wire rd_en = grant[1] || (grant[0] && !host_write);
        wire wr_en = grant[2] || (grant[0] && host_write);
        wire [9:0] addr = grant[1] ? tx_addr : grant[2] ? writer_addr : host_addr;
        wire [63:0] wdata = grant[2] ? writer_data : host_wdata;

        vgg_sram_8k u_bank (
            .clk(clk), .en(|grant), .rd_en(rd_en), .wr_en(wr_en),
            .addr(addr), .wdata(wdata), .rdata(bank_rdata[b*64 +: 64])
        );

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) priority_client <= HOST;
            else if (grant[0]) priority_client <= TX;
            else if (grant[1]) priority_client <= WRITER;
            else if (grant[2]) priority_client <= HOST;
        end
    end endgenerate

    // Accepted reads become responses after the same edge as the macro read.
    // Simultaneous response consumption/new read keeps the port fully pipelined.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            host_rvalid <= 0;
            tx_rvalid <= 0;
            host_response_bank <= 0;
            tx_response_bank <= 0;
        end else begin
            if (host_rready) host_rvalid <= 0;
            if (tx_rready) tx_rvalid <= 0;
            if (host_valid && host_ready && !host_write) begin
                host_rvalid <= 1;
                host_response_bank <= host_bank;
            end
            if (tx_valid && tx_ready) begin
                tx_rvalid <= 1;
                tx_response_bank <= tx_bank;
            end
        end
    end
endmodule
`default_nettype wire
