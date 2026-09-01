`timescale 1ns/1ps

module winograd_sliding_window_generator_tb;
    reg clk;
    reg rst_n;
    integer errors;
    integer cycles;
    integer lane;
    integer expected_address;
    integer expected_value;
    integer tile_index;
    integer tile_row;
    integer tile_col;
    integer channel;

    reg a_start;
    wire a_start_ready;
    wire a_done;
    reg a_in_valid;
    wire a_in_ready;
    reg [7:0] a_pixel;
    wire a_out_valid;
    reg a_out_ready;
    wire [127:0] a_tile;
    wire [1:0] a_channel;
    wire [3:0] a_tile_row;
    wire [3:0] a_tile_col;
    wire a_last;
    integer a_address;
    integer a_transfer_count;

    reg b_start;
    wire b_start_ready;
    wire b_done;
    reg b_in_valid;
    wire b_in_ready;
    reg [23:0] b_pixel;
    wire b_out_valid;
    reg b_out_ready;
    wire [127:0] b_tile;
    wire [1:0] b_channel;
    wire [3:0] b_tile_row;
    wire [3:0] b_tile_col;
    wire b_last;
    integer b_address;
    integer b_transfer_count;

    reg a_stalled;
    reg [138:0] a_stalled_payload;
    reg b_stalled;
    reg [138:0] b_stalled_payload;

    winograd_sliding_window_generator #(
        .CHANNELS(1),
        .FEATURE_WIDTH(8),
        .FEATURE_HEIGHT(8),
        .POSITION_BITS(4),
        .TILE_ROWS(3),
        .TILE_COLS(3)
    ) dut_a (
        .clk(clk),
        .rst_n(rst_n),
        .start(a_start),
        .start_ready(a_start_ready),
        .busy(),
        .done(a_done),
        .in_valid(a_in_valid),
        .in_ready(a_in_ready),
        .pixel_vector(a_pixel),
        .out_valid(a_out_valid),
        .out_ready(a_out_ready),
        .activation_tile(a_tile),
        .output_input_channel(a_channel),
        .output_tile_row(a_tile_row),
        .output_tile_col(a_tile_col),
        .output_last(a_last)
    );

    winograd_sliding_window_generator #(
        .CHANNELS(3),
        .FEATURE_WIDTH(7),
        .FEATURE_HEIGHT(7),
        .POSITION_BITS(3),
        .TILE_ROWS(2),
        .TILE_COLS(2)
    ) dut_b (
        .clk(clk),
        .rst_n(rst_n),
        .start(b_start),
        .start_ready(b_start_ready),
        .busy(),
        .done(b_done),
        .in_valid(b_in_valid),
        .in_ready(b_in_ready),
        .pixel_vector(b_pixel),
        .out_valid(b_out_valid),
        .out_ready(b_out_ready),
        .activation_tile(b_tile),
        .output_input_channel(b_channel),
        .output_tile_row(b_tile_row),
        .output_tile_col(b_tile_col),
        .output_last(b_last)
    );

    always #5 clk = ~clk;

    always @(negedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            a_out_ready <= 1'b0;
            b_out_ready <= 1'b0;
        end else begin
            cycles <= cycles + 1;
            a_out_ready <= ((cycles % 5) != 1);
            b_out_ready <= ((cycles % 4) != 2);
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (a_out_valid && !a_out_ready) begin
                if (a_stalled
                    && {a_last, a_tile_row, a_tile_col, a_channel, a_tile}
                       !== a_stalled_payload) begin
                    $display("ERROR: A output changed under backpressure");
                    errors = errors + 1;
                end
                a_stalled = 1'b1;
                a_stalled_payload =
                    {a_last, a_tile_row, a_tile_col, a_channel, a_tile};
            end else begin
                a_stalled = 1'b0;
            end

            if (b_out_valid && !b_out_ready) begin
                if (b_stalled
                    && {b_last, b_tile_row, b_tile_col, b_channel, b_tile}
                       !== b_stalled_payload) begin
                    $display("ERROR: B output changed under backpressure");
                    errors = errors + 1;
                end
                b_stalled = 1'b1;
                b_stalled_payload =
                    {b_last, b_tile_row, b_tile_col, b_channel, b_tile};
            end else begin
                b_stalled = 1'b0;
            end

            if (a_out_valid && a_out_ready) begin
                tile_row = a_transfer_count / 3;
                tile_col = a_transfer_count % 3;
                if (a_channel !== 0 || a_tile_row !== tile_row
                    || a_tile_col !== tile_col) begin
                    $display("ERROR: A metadata n=%0d got=%0d/%0d/%0d",
                             a_transfer_count, a_channel,
                             a_tile_row, a_tile_col);
                    errors = errors + 1;
                end
                for (lane = 0; lane < 16; lane = lane + 1) begin
                    expected_address = (tile_row*2 + lane/4)*8
                                     + tile_col*2 + lane%4;
                    expected_value = expected_address & 255;
                    if (a_tile[lane*8 +: 8] !== expected_value) begin
                        $display("ERROR: A n=%0d lane=%0d got=%0d expected=%0d",
                                 a_transfer_count, lane,
                                 a_tile[lane*8 +: 8], expected_value);
                        errors = errors + 1;
                    end
                end
                if (a_last !== (a_transfer_count == 8)) begin
                    $display("ERROR: A last n=%0d", a_transfer_count);
                    errors = errors + 1;
                end
                a_transfer_count = a_transfer_count + 1;
            end

            if (b_out_valid && b_out_ready) begin
                tile_index = b_transfer_count / 3;
                channel = b_transfer_count % 3;
                tile_row = tile_index / 2;
                tile_col = tile_index % 2;
                if (b_channel !== channel || b_tile_row !== tile_row
                    || b_tile_col !== tile_col) begin
                    $display("ERROR: B metadata n=%0d got=%0d/%0d/%0d expected=%0d/%0d/%0d",
                             b_transfer_count, b_channel,
                             b_tile_row, b_tile_col,
                             channel, tile_row, tile_col);
                    errors = errors + 1;
                end
                for (lane = 0; lane < 16; lane = lane + 1) begin
                    expected_address = (tile_row*2 + lane/4)*7
                                     + tile_col*2 + lane%4;
                    expected_value = (expected_address + channel*64) & 255;
                    if (b_tile[lane*8 +: 8] !== expected_value) begin
                        $display("ERROR: B n=%0d lane=%0d got=%0d expected=%0d",
                                 b_transfer_count, lane,
                                 b_tile[lane*8 +: 8], expected_value);
                        errors = errors + 1;
                    end
                end
                if (b_last !== (b_transfer_count == 11)) begin
                    $display("ERROR: B last n=%0d", b_transfer_count);
                    errors = errors + 1;
                end
                b_transfer_count = b_transfer_count + 1;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        errors = 0;
        cycles = 0;
        a_start = 1'b0;
        a_in_valid = 1'b0;
        a_pixel = 0;
        a_out_ready = 1'b0;
        a_transfer_count = 0;
        a_stalled = 1'b0;
        b_start = 1'b0;
        b_in_valid = 1'b0;
        b_pixel = 0;
        b_out_ready = 1'b0;
        b_transfer_count = 0;
        b_stalled = 1'b0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        while (!a_start_ready) @(negedge clk);
        a_start = 1'b1;
        @(negedge clk);
        a_start = 1'b0;
        for (a_address = 0; a_address < 64; a_address = a_address + 1) begin
            @(negedge clk);
            a_in_valid = 1'b1;
            a_pixel = a_address;
            @(posedge clk);
            while (!a_in_ready) @(posedge clk);
        end
        @(negedge clk);
        a_in_valid = 1'b0;
        wait(a_done);
        @(posedge clk);
        if (a_transfer_count != 9) begin
            $display("ERROR: A transfer count=%0d", a_transfer_count);
            errors = errors + 1;
        end

        while (!b_start_ready) @(negedge clk);
        b_start = 1'b1;
        @(negedge clk);
        b_start = 1'b0;
        // The last required 4x4 window ends at row 5, column 5. Row 6 and
        // column 6 are intentionally not consumed by the floor-pooled model.
        for (b_address = 0; b_address <= 40; b_address = b_address + 1) begin
            @(negedge clk);
            b_in_valid = 1'b1;
            b_pixel[7:0] = b_address;
            b_pixel[15:8] = b_address + 64;
            b_pixel[23:16] = b_address + 128;
            @(posedge clk);
            while (!b_in_ready) @(posedge clk);
        end
        @(negedge clk);
        b_in_valid = 1'b0;
        wait(b_done);
        @(posedge clk);
        if (b_transfer_count != 12) begin
            $display("ERROR: B transfer count=%0d", b_transfer_count);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: winograd_sliding_window_generator");
        else
            $display("FAIL: winograd_sliding_window_generator errors=%0d",
                     errors);
        $finish;
    end
endmodule
