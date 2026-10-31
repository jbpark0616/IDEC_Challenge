`timescale 1ns/1ps
module tb_cb_slots;
    wire [3:0] slot_limit=4'd8;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,clear=0,reserve_valid=0,commit_valid=0,acquire=0,release_valid=0;
    wire reserve_ready,commit_ready,available,release_ready;
    wire [2:0] producer_slot,consumer_slot;
    wire [3:0] occupancy;
    vgg_cb_slots dut(.*);
    integer i,round;
    task automatic reserve;
        begin
            @(negedge clk);reserve_valid=1;
            @(posedge clk);if(!reserve_ready) $fatal(1,"Expected free slot");
            @(negedge clk);reserve_valid=0;
            if(reserve_ready || !commit_ready) $fatal(1,"Reservation state");
        end
    endtask
    task automatic commit;
        begin
            @(negedge clk);commit_valid=1;
            @(posedge clk);if(!commit_ready) $fatal(1,"Expected reserved slot");
            @(negedge clk);commit_valid=0;
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        if(available || release_ready || commit_ready || occupancy!=0) $fatal(1,"Initial ownership");
        for(round=0;round<3;round=round+1) begin
            for(i=0;i<8;i=i+1) begin
                if(producer_slot!=i) $fatal(1,"Producer wrap order");
                reserve();
                if(i==0 && available) $fatal(1,"Uncommitted data visible");
                commit();
            end
            if(occupancy!=8 || reserve_ready) $fatal(1,"Full queue not blocking");
            reserve_valid=1;repeat(4) @(negedge clk);reserve_valid=0;
            if(occupancy!=8 || producer_slot!=0) $fatal(1,"Overflow changed state");
            for(i=0;i<8;i=i+1) begin
                if(!available || consumer_slot!=i) $fatal(1,"Consumer FIFO order");
                acquire=1;@(posedge clk);@(negedge clk);acquire=0;
                if(available || !release_ready || occupancy!=8-i) $fatal(1,"Acquire released early");
                repeat(3) @(negedge clk);
                release_valid=1;@(posedge clk);@(negedge clk);release_valid=0;
            end
            if(occupancy!=0 || available) $fatal(1,"Queue did not drain");
        end
        reserve();commit();acquire=1;@(posedge clk);@(negedge clk);acquire=0;
        reserve();
        rst_n=0;repeat(2) @(negedge clk);rst_n=1;
        if(occupancy!=0 || !reserve_ready || available || release_ready) $fatal(1,"Reset leaks ownership");
        reserve();clear=1;@(posedge clk);@(negedge clk);clear=0;
        if(occupancy!=0 || !reserve_ready || commit_ready) $fatal(1,"Layer clear leaks ownership");
        $display("PASS CB ownership: full/empty, unpublished data, wrap x3, acquired hold, reset/clear");
        $finish;
    end
    initial begin #100000; $fatal(1,"CB unit timeout");end
endmodule
