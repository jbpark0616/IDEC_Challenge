`default_nettype none
// X/Y page ownership around the physical SRAM, not a second payload memory.
// Bank 13 is the control window (64-bit WORD addresses):
// Writes require data[63]=1; other words are no-ops for 256-bit DMA packing.
// 0 write: streaming enable, only while idle. Read: status bits below.
// 1 write: reserve X slot, data[0]. 2 write: commit {words[10:0],slot}.
// 3 write: release Y slot, data[0], after all host reads have completed.
// 4/5 read: Y slot 0/1 {last at bit16, words at [10:0]}.
// X pages are consecutive HWC bytes, up to 1024 words; Y pages are 256 words.
// Resident mode preserves the existing CHW preload / DONE readback protocol.
module vgg_io_cbs (
    input wire clk, rst_n, idle, running, done, start,
    input wire mem_valid, mem_write,
    output wire mem_ready,
    input wire [3:0] mem_bank,
    input wire [9:0] mem_addr,
    input wire [63:0] mem_wdata,
    output wire mem_rvalid,
    input wire mem_rready,
    output wire [63:0] mem_rdata,

    output wire host_valid, host_write,
    input wire host_ready,
    output wire [3:0] host_bank,
    output wire [9:0] host_addr,
    output wire [63:0] host_wdata,
    input wire host_rvalid,
    output wire host_rready,
    input wire [63:0] host_rdata,
    input wire host_idle,

    output reg streaming,
    input wire x_slot, x_release,
    output wire x_available,
    output wire [10:0] x_words,

    input wire out_valid, out_last,
    output wire out_ready,
    input wire [9:0] resident_y_addr,
    output wire y_valid, y_slot,
    input wire y_ready,
    output wire [9:0] y_addr,
    output wire drained,
    output wire control_idle
);
    localparam FREE=0, FILLING=1, READY=2;
    reg [1:0] x_owner [0:1];
    reg [10:0] x_length [0:1];
    reg [1:0] y_published;
    reg [10:0] y_length [0:1];
    reg [1:0] y_last;
    reg y_write_slot;
    reg [7:0] y_word;
    reg ctrl_rvalid;
    reg [63:0] ctrl_rdata;
    reg host_read_padding;
    wire ctrl = mem_bank==13;
    wire slot = mem_wdata[0];
    wire [10:0] commit_words = mem_wdata[11:1];
    wire config_ok = mem_addr==0 && idle && x_owner[0]==FREE && x_owner[1]==FREE && !y_published;
    wire reserve_ok = streaming && mem_addr==1 && x_owner[slot]==FREE;
    wire commit_ok = streaming && mem_addr==2 && x_owner[slot]==FILLING
                   && commit_words!=0 && commit_words<=1024;
    wire release_ok = streaming && mem_addr==3 && y_published[slot];
    wire ctrl_ready = host_idle && !ctrl_rvalid
                    && (!mem_write || !mem_wdata[63] || config_ok || reserve_ok || commit_ok || release_ok);
    wire x_host = mem_bank==8 || mem_bank==9;
    wire y_host = mem_bank==10 || mem_bank==11;
    wire stream_access = (x_host && mem_write && x_owner[mem_bank[0]]==FILLING)
                       || (y_host && !mem_write && y_published[mem_bank[0]]
                           && {1'b0,mem_addr}<((y_length[mem_bank[0]]+11'd3)&11'h7fc))
                       || (idle && mem_bank<4)
                       || (done && !mem_write && mem_bank<8)
                       || (done && !mem_write && mem_bank==12);
    wire allowed = streaming ? stream_access : (idle || (done && !mem_write));
    assign host_valid = mem_valid && !ctrl && allowed && !ctrl_rvalid;
    assign host_write = mem_write;
    assign host_bank = mem_bank;
    assign host_addr = mem_addr;
    assign host_wdata = mem_wdata;
    assign host_rready = mem_rready && !ctrl_rvalid;
    assign mem_ready = ctrl ? ctrl_ready : (allowed && !ctrl_rvalid && host_ready);
    assign mem_rvalid = ctrl_rvalid || host_rvalid;
    assign mem_rdata = ctrl_rvalid ? ctrl_rdata : (host_read_padding ? 64'b0 : host_rdata);
    assign control_idle = host_idle && !ctrl_rvalid;
    assign x_available = x_owner[x_slot]==READY;
    assign x_words = x_length[x_slot];
    assign y_valid = out_valid && (!streaming || !y_published[y_write_slot]);
    assign out_ready = y_ready && (!streaming || !y_published[y_write_slot]);
    assign y_slot = streaming ? y_write_slot : 1'b0;
    assign y_addr = streaming ? {2'b0,y_word} : resident_y_addr;
    assign drained = !streaming || (!y_published && x_owner[0]==FREE && x_owner[1]==FREE);
    wire publish_y = streaming && y_valid && y_ready && (y_word==255 || out_last);
    wire ctrl_fire = mem_valid && mem_ready && ctrl;
    wire [63:0] status = {55'b0, y_published, (x_owner[1]==READY), (x_owner[0]==READY),
                         (x_owner[1]==FREE), (x_owner[0]==FREE), done, running, streaming};

    always @(posedge clk) begin
        if(host_valid && host_ready && !mem_write)
            host_read_padding <= streaming && y_host && {1'b0,mem_addr}>=y_length[mem_bank[0]];
        if(ctrl_fire && !mem_write) begin
            case(mem_addr)
                0: ctrl_rdata <= status;
                4: ctrl_rdata <= {47'b0,y_last[0],5'b0,y_length[0]};
                5: ctrl_rdata <= {47'b0,y_last[1],5'b0,y_length[1]};
                default: ctrl_rdata <= 0;
            endcase
        end
        if(ctrl_fire && mem_write && mem_wdata[63] && commit_ok) x_length[slot]<=commit_words;
        if(publish_y) y_length[y_write_slot]<={3'b0,y_word}+11'd1;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            streaming<=0; x_owner[0]<=FREE; x_owner[1]<=FREE;
            y_published<=0; y_last<=0; y_write_slot<=0; y_word<=0; ctrl_rvalid<=0;
        end else begin
            if(ctrl_rvalid && mem_rready) ctrl_rvalid<=0;
            if(ctrl_fire && !mem_write) ctrl_rvalid<=1;
            if(ctrl_fire && mem_write && mem_wdata[63]) begin
                if(config_ok) streaming<=mem_wdata[0];
                if(reserve_ok) x_owner[slot]<=FILLING;
                if(commit_ok) x_owner[slot]<=READY;
                if(release_ok) y_published[slot]<=0;
            end
            if(x_release) x_owner[x_slot]<=FREE;
            if(start) begin y_write_slot<=0; y_word<=0; end
            if(streaming && y_valid && y_ready) begin
                if(publish_y) begin
                    y_published[y_write_slot]<=1;
                    y_last[y_write_slot]<=out_last;
                    y_write_slot<=!y_write_slot;
                    y_word<=0;
                end else y_word<=y_word+1'b1;
            end
        end
    end
endmodule
`default_nettype wire
