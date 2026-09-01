`timescale 1ns/1ps

module winograd_v_replay_buffer_tb;
    localparam integer V_TILE_BITS = 176;

    reg clk;
    reg rst_n;
    reg [1:0] input_channels_minus1;
    reg [1:0] output_channels_minus1;
    reg in_valid;
    wire in_ready;
    reg [V_TILE_BITS-1:0] in_v_tile;
    wire out_valid;
    reg out_ready;
    wire [V_TILE_BITS-1:0] out_v_tile;
    wire [1:0] input_channel;
    wire [1:0] output_channel;
    wire txn_first;
    wire txn_last;
    wire full;
    wire empty;

    integer errors;
    integer channel;
    integer kernel;
    integer group;

    winograd_v_replay_buffer dut (
        .clk(clk),
        .rst_n(rst_n),
        .input_channels_minus1(input_channels_minus1),
        .output_channels_minus1(output_channels_minus1),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_v_tile(in_v_tile),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .out_v_tile(out_v_tile),
        .input_channel(input_channel),
        .output_channel(output_channel),
        .txn_first(txn_first),
        .txn_last(txn_last),
        .full(full),
        .empty(empty)
    );

    always #5 clk = ~clk;

    function [V_TILE_BITS-1:0] tile_value;
        input integer group_id;
        input integer channel_id;
        reg [31:0] tag;
        begin
            tag = group_id*16 + channel_id;
            tile_value = {V_TILE_BITS{1'b0}};
            tile_value[31:0] = tag;
            tile_value[95:64] = tag ^ 32'h5a5aa5a5;
            tile_value[175:160] = ~tag[15:0];
        end
    endfunction

    task push_channel;
        input integer group_id;
        input integer channel_id;
        begin
            @(negedge clk);
            while (!in_ready)
                @(negedge clk);
            in_v_tile = tile_value(group_id, channel_id);
            in_valid = 1'b1;
            @(negedge clk);
            in_valid = 1'b0;
        end
    endtask

    task pop_channel;
        input integer group_id;
        input integer expected_kernel;
        input integer expected_channel;
        begin
            @(negedge clk);
            while (!out_valid)
                @(negedge clk);
            if (out_v_tile !== tile_value(group_id, expected_channel)
                || output_channel !== expected_kernel[1:0]
                || input_channel !== expected_channel[1:0]
                || txn_first !== (expected_channel == 0)
                || txn_last !== (expected_channel == input_channels_minus1)) begin
                $display("FAIL replay group=%0d k=%0d c=%0d got_k=%0d got_c=%0d first=%b last=%b",
                         group_id, expected_kernel, expected_channel,
                         output_channel, input_channel, txn_first, txn_last);
                errors = errors + 1;
            end
            out_ready = 1'b1;
            @(negedge clk);
            out_ready = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        input_channels_minus1 = 2;  // Conv2: C=3
        output_channels_minus1 = 2; // K=3
        in_valid = 1'b0;
        in_v_tile = 0;
        out_ready = 1'b0;
        errors = 0;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // A partial C=3 group must not be exposed to the consumer.
        push_channel(1, 0);
        push_channel(1, 1);
        if (out_valid || !empty) begin
            $display("FAIL replay exposed a partial input group");
            errors = errors + 1;
        end
        push_channel(1, 2);

        // The same three V channel tiles are replayed for k=0,1,2.
        for (kernel = 0; kernel < 3; kernel = kernel + 1)
            for (channel = 0; channel < 3; channel = channel + 1)
                pop_channel(1, kernel, channel);

        if (!empty) begin
            $display("FAIL replay did not release fully consumed group");
            errors = errors + 1;
        end

        // Fill both circular-buffer group slots and verify wrap/order.
        for (group = 2; group <= 3; group = group + 1)
            for (channel = 0; channel < 3; channel = channel + 1)
                push_channel(group, channel);
        if (!full || in_ready) begin
            $display("FAIL replay full signaling");
            errors = errors + 1;
        end
        for (group = 2; group <= 3; group = group + 1)
            for (kernel = 0; kernel < 3; kernel = kernel + 1)
                for (channel = 0; channel < 3; channel = channel + 1)
                    pop_channel(group, kernel, channel);

        // Conv1 uses C=1 but still replays its V tile for three output maps.
        input_channels_minus1 = 0;
        output_channels_minus1 = 2;
        push_channel(4, 0);
        for (kernel = 0; kernel < 3; kernel = kernel + 1)
            pop_channel(4, kernel, 0);

        // Hold output stable while the MAC is stalled.
        input_channels_minus1 = 2;
        for (channel = 0; channel < 3; channel = channel + 1)
            push_channel(5, channel);
        repeat (3) begin
            @(negedge clk);
            if (!out_valid || out_v_tile !== tile_value(5, 0)
                || input_channel !== 0 || output_channel !== 0) begin
                $display("FAIL replay output changed under backpressure");
                errors = errors + 1;
            end
        end
        for (kernel = 0; kernel < 3; kernel = kernel + 1)
            for (channel = 0; channel < 3; channel = channel + 1)
                pop_channel(5, kernel, channel);

        if (errors == 0)
            $display("PASS winograd_v_replay_buffer: all tests passed");
        else
            $display("FAIL winograd_v_replay_buffer: %0d error(s)", errors);
        $finish;
    end

endmodule
