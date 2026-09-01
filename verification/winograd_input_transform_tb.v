`timescale 1ns/1ps

module winograd_input_transform_tb;
    localparam integer TILE_SIZE = 4;
    localparam integer ACT_BITS = 8;
    localparam integer V_BITS = 11;

    reg clk;
    reg rst_n;
    reg in_valid;
    wire in_ready;
    reg [TILE_SIZE*TILE_SIZE*ACT_BITS-1:0] activation_tile;
    wire out_valid;
    reg out_ready;
    wire [TILE_SIZE*TILE_SIZE*V_BITS-1:0] v_tile;

    integer pixel [0:15];
    integer temp [0:15];
    integer expected [0:15];
    integer got;
    integer row;
    integer col;
    integer test_index;
    integer burst_drive;
    integer burst_receive;
    integer drive_element;
    integer receive_element;
    integer errors;
    integer burst_expected [0:47];
    reg [TILE_SIZE*TILE_SIZE*V_BITS-1:0] held_result;

    winograd_input_transform dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .activation_tile(activation_tile),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .v_tile(v_tile)
    );

    always #5 clk = ~clk;

    task calculate_golden;
        begin
            for (col = 0; col < 4; col = col + 1) begin
                temp[0*4+col] = pixel[0*4+col] - pixel[2*4+col];
                temp[1*4+col] = pixel[1*4+col] + pixel[2*4+col];
                temp[2*4+col] = pixel[2*4+col] - pixel[1*4+col];
                temp[3*4+col] = pixel[1*4+col] - pixel[3*4+col];
            end
            for (row = 0; row < 4; row = row + 1) begin
                expected[row*4+0] = temp[row*4+0] - temp[row*4+2];
                expected[row*4+1] = temp[row*4+1] + temp[row*4+2];
                expected[row*4+2] = temp[row*4+2] - temp[row*4+1];
                expected[row*4+3] = temp[row*4+1] - temp[row*4+3];
            end
        end
    endtask

    task send_tile;
        begin
            calculate_golden();
            for (row = 0; row < 4; row = row + 1)
                for (col = 0; col < 4; col = col + 1)
                    activation_tile[(row*4+col)*ACT_BITS +: ACT_BITS]
                        = pixel[row*4+col];

            @(negedge clk);
            while (!in_ready)
                @(negedge clk);
            in_valid = 1'b1;
            @(negedge clk);
            in_valid = 1'b0;
        end
    endtask

    task check_tile;
        input [8*40-1:0] test_name;
        begin
            while (!out_valid)
                @(negedge clk);
            for (row = 0; row < 4; row = row + 1) begin
                for (col = 0; col < 4; col = col + 1) begin
                    got = $signed(v_tile[(row*4+col)*V_BITS +: V_BITS]);
                    if (got !== expected[row*4+col]) begin
                        $display("FAIL %-40s row=%0d col=%0d expected=%0d got=%0d",
                                 test_name, row, col, expected[row*4+col], got);
                        errors = errors + 1;
                    end
                end
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        in_valid = 1'b0;
        activation_tile = 0;
        out_ready = 1'b1;
        errors = 0;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // Zero tile.
        for (row = 0; row < 16; row = row + 1)
            pixel[row] = 0;
        send_tile();
        check_tile("all-zero tile");

        // Maximum checkerboard exercises the theoretical +/-1020 range.
        for (row = 0; row < 4; row = row + 1)
            for (col = 0; col < 4; col = col + 1)
                pixel[row*4+col] = ((row+col) & 1) ? 0 : 255;
        send_tile();
        check_tile("UINT8 checkerboard extremes");

        // Position-dependent ramp catches row/column and packing mistakes.
        for (row = 0; row < 4; row = row + 1)
            for (col = 0; col < 4; col = col + 1)
                pixel[row*4+col] = row*61 + col*13;
        send_tile();
        check_tile("row-major packing ramp");

        // Random regression against the same integer equation as PyTorch.
        for (test_index = 0; test_index < 100; test_index = test_index + 1) begin
            for (row = 0; row < 16; row = row + 1)
                pixel[row] = $random & 8'hff;
            send_tile();
            check_tile("random integer golden");
        end

        // Three consecutive valid cycles verify one-tile-per-cycle throughput.
        fork
            begin : burst_driver
                @(negedge clk);
                for (burst_drive = 0; burst_drive < 3; burst_drive = burst_drive + 1) begin
                    while (!in_ready)
                        @(negedge clk);
                    for (drive_element = 0; drive_element < 16;
                         drive_element = drive_element + 1)
                        pixel[drive_element] =
                            (burst_drive*73 + drive_element*29 + 7) & 8'hff;
                    calculate_golden();
                    for (drive_element = 0; drive_element < 16;
                         drive_element = drive_element + 1) begin
                        activation_tile[drive_element*ACT_BITS +: ACT_BITS]
                            = pixel[drive_element];
                        burst_expected[burst_drive*16+drive_element]
                            = expected[drive_element];
                    end
                    in_valid = 1'b1;
                    @(negedge clk);
                end
                in_valid = 1'b0;
            end
            begin : burst_monitor
                for (burst_receive = 0; burst_receive < 3;
                     burst_receive = burst_receive + 1) begin
                    @(negedge clk);
                    while (!out_valid)
                        @(negedge clk);
                    for (receive_element = 0; receive_element < 16;
                         receive_element = receive_element + 1) begin
                        got = $signed(v_tile[receive_element*V_BITS +: V_BITS]);
                        if (got !== burst_expected[burst_receive*16+receive_element]) begin
                            $display("FAIL burst tile=%0d element=%0d expected=%0d got=%0d",
                                     burst_receive, receive_element,
                                     burst_expected[burst_receive*16+receive_element], got);
                            errors = errors + 1;
                        end
                    end
                end
            end
        join

        // Hold the final output stable while the consumer is stalled.
        @(negedge clk);
        out_ready = 1'b0;
        for (row = 0; row < 16; row = row + 1)
            pixel[row] = (row*47 + 19) & 8'hff;
        send_tile();
        check_tile("backpressure result");
        held_result = v_tile;
        repeat (3) begin
            @(negedge clk);
            if (!out_valid || v_tile !== held_result) begin
                $display("FAIL output changed while out_ready=0");
                errors = errors + 1;
            end
        end
        out_ready = 1'b1;
        @(negedge clk);

        if (errors == 0)
            $display("PASS winograd_input_transform: all tests passed");
        else
            $display("FAIL winograd_input_transform: %0d error(s)", errors);

        $finish;
    end

endmodule
