`timescale 1ns/1ps
module tb_window_equivalence #(
    parameter integer H=6, W=6, C=3
);
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0;
    integer cycle=0;
    always @(posedge clk) cycle<=cycle+1;
    initial begin #100000000; $fatal(1,"Window watchdog"); end
    reg ref_start=0,ref_in_valid=0;
    wire ref_start_ready,ref_in_ready,ref_valid,ref_last;
    wire [127:0] ref_tile;
    wire [6:0] ref_c;
    wire [4:0] ref_y,ref_x;
    reg [C*8-1:0] pixel_vector=0;
    wire sink_ready=cycle%7!=2 && cycle%7!=3;
    winograd_window_ff_reference #(
        .CHANNELS(C),.CHANNEL_BITS(7),.FEATURE_WIDTH(W+2),.FEATURE_HEIGHT(H+2),
        .POSITION_BITS(6),.TILE_ROWS(H/2),.TILE_COLS(W/2),.TILE_INDEX_BITS(5)
    ) reference_window (
        .clk(clk),.rst_n(rst_n),.start(ref_start),.start_ready(ref_start_ready),.busy(),.done(),
        .in_valid(ref_in_valid),.in_ready(ref_in_ready),.pixel_vector(pixel_vector),
        .out_valid(ref_valid),.out_ready(sink_ready),.activation_tile(ref_tile),
        .output_input_channel(ref_c),.output_tile_row(ref_y),.output_tile_col(ref_x),.output_last(ref_last)
    );
    reg start=0,loading=1;
    wire start_ready,valid,last;
    wire [127:0] tile;
    wire [6:0] oc;
    wire [4:0] oy,ox;
    wire mv,mready,mwrite,rv,rr;
    wire [3:0] mb;
    wire [9:0] ma;
    wire [63:0] mw,rd;
    reg load_valid=0;
    reg [9:0] load_addr=0;
    reg [63:0] load_data=0;
    wire sp_ready;
    wire pixel_valid, pixel_ready;
    wire [1023:0] loaded_pixel;
    assign mwrite=0;
    assign mb=8;
    assign mw=0;
    vgg_activation_reader #(.HEIGHT(H),.WIDTH(W)) reader (
        .clk(clk),.rst_n(rst_n),.start(start),.channels(8'(C)),.streaming(1'b0),
        .pixel_valid(pixel_valid),.pixel_ready(pixel_ready),.pixel_vector(loaded_pixel),
        .mem_valid(mv),.mem_ready(mready),.mem_slot(),.mem_addr(ma),
        .mem_rvalid(rv),.mem_rready(rr),.mem_rdata(rd),
        .page_available(1'b0),.page_words(11'b0),.page_release(),.page_slot(),.done()
    );
    winograd_sliding_window_generator #(
        .CHANNELS(128),.CHANNEL_BITS(7),.RUNTIME_CHANNELS(1),
        .FEATURE_WIDTH(W+2),.FEATURE_HEIGHT(H+2),.POSITION_BITS(6),
        .TILE_ROWS(H/2),.TILE_COLS(W/2),.TILE_INDEX_BITS(5)
    ) dut (
        .clk(clk),.rst_n(rst_n),.start(start),.start_ready(start_ready),
        .channel_count_minus1(7'(C-1)),.busy(),.done(),
        .in_valid(pixel_valid),.in_ready(pixel_ready),.pixel_vector(loaded_pixel),
        .out_valid(valid),.out_ready(sink_ready),.activation_tile(tile),.output_input_channel(oc),
        .output_tile_row(oy),.output_tile_col(ox),.output_last(last)
    );
    // Real 1RW behavioral macros and the same registered response adapter as core.
    wire grant=cycle%5!=1;
    assign mready=!loading && grant && sp_ready;
    vgg_scratchpad_12bank memory (
        .clk(clk),.rst_n(rst_n),.compute_active(1'b0),.row_read(4'b0),
        .u_addr(40'b0),.v_addr(40'b0),.u_data(),.v_data(),
        .host_valid(loading ? load_valid : mv && grant),.host_ready(sp_ready),
        .host_write(loading ? 1'b1 : mwrite),.host_bank(loading ? 4'd8 : mb),
        .host_addr(loading ? load_addr : ma),.host_wdata(loading ? load_data : mw),
        .host_rvalid(rv),.host_rready(rr),.host_rdata(rd),.host_idle()
    );
    localparam N=H*W/4*C;
    reg [145:0] expected[0:N-1];
    integer ref_count=0,count=0,pass,i,y,x,c,b,idx;
    reg [145:0] held;
    reg stalled=0;
    function automatic [7:0] sample(input integer cc,yy,xx,epoch);
        sample=(cc*37+yy*11+xx*19+epoch*53)%256;
    endfunction
    always @(posedge clk) if(rst_n) begin
        if(ref_valid && sink_ready) begin
            expected[ref_count]={ref_last,ref_y,ref_x,ref_c,ref_tile};
            ref_count++;
        end
        if(valid && sink_ready) begin
            if(count>=N || {last,oy,ox,oc,tile}!==expected[count])
                $fatal(1,"FF/SRAM mismatch transaction=%0d C=%0d y=%0d x=%0d",count,oc,oy,ox);
            count++;
        end
        if(stalled && (!valid || {last,oy,ox,oc,tile}!==held)) $fatal(1,"Window hold changed");
        stalled=valid&&!sink_ready;
        held={last,oy,ox,oc,tile};
    end
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        for(pass=0;pass<2;pass++) begin
            loading=1;ref_count=0;count=0;
            for(i=0;i<(H*W*C+7)/8;i++) begin
                load_data=0;
                for(b=0;b<8;b++) begin
                    idx=i*8+b;
                    if(idx<H*W*C) load_data[b*8+:8]=sample(idx/(H*W),(idx/W)%H,idx%W,pass);
                end
                @(negedge clk);load_valid=1;load_addr=i;
                do @(posedge clk);while(!sp_ready);
                @(negedge clk);load_valid=0;
            end
            @(negedge clk);ref_start=1;
            @(negedge clk);ref_start=0;
            for(y=0;y<H+2;y++) for(x=0;x<W+2;x++) begin
                @(negedge clk);
                for(c=0;c<C;c++) pixel_vector[c*8+:8]=(y==0 || y==H+1 || x==0 || x==W+1) ? 0 : sample(c,y-1,x-1,pass);
                ref_in_valid=1;
                do @(posedge clk);while(!ref_in_ready);
                @(negedge clk);ref_in_valid=0;
            end
            wait(ref_count==N);
            @(negedge clk);loading=0;start=1;
            @(negedge clk);start=0;
            wait(count==N);
            @(negedge clk);
        end
        $display("PASS FF/SRAM window equivalence H=%0d W=%0d C=%0d transactions=%0d; original FF window, boundary reader, restart, padding, stalls",H,W,C,N*2);
        $finish;
    end
endmodule
