`timescale 1ns/1ps
module tb_quantizer;
    reg [255:0] in_tile;
    reg [2:0] shift;
    wire [255:0] out_tile;
    wire [3:0] zero_rows;
    integer s,value,n,denom,expected,count=0;
    vgg_v8_quantizer dut(.*);
    initial begin
        for(s=0;s<8;s=s+1) begin
            shift=3'(s);
            for(value=-1020;value<=1020;value=value+1) begin
                in_tile={16{16'(value)}};
                denom=1<<s;
                n=value+denom/2;
                // Integer division with explicit floor for negative numerators.
                expected=n>=0 ? n/denom : -((-n+denom-1)/denom);
                if(expected>127) expected=127;
                if(expected < -127) expected=-127;
                #1;
                if(out_tile !== {16{16'(expected)}} || zero_rows !== (expected==0 ? 4'hf : 4'h0))
                    $fatal(1,"quantizer mismatch value=%0d shift=%0d got=%h expected=%0d",value,s,out_tile[15:0],expected);
                count++;
            end
        end
        $display("PASS QUANTIZER signed_values=-1020..1020 shifts=0..7 cases=%0d",count);
        $finish;
    end
endmodule
