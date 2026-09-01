`timescale 1ps/1ps

// Competition-interface regression for 1,000 raster-streamed MNIST images.
// Each RTL decision must match the exported integer-model prediction; label
// accuracy is reported separately.
module winograd_chip_1000_tb;
`ifdef FIFO_TRACE
    localparam integer TEST_IMAGE_COUNT = 1;
`elsif LIFETIME_TRACE
    localparam integer TEST_IMAGE_COUNT = 1;
`elsif POWER_TRACE
    localparam integer TEST_IMAGE_COUNT = 1;
`else
    localparam integer TEST_IMAGE_COUNT = 1000;
`endif
`ifdef TEST_CONV1_TILE_FIFO_DEPTH_1
    localparam integer CONV1_TILE_FIFO_DEPTH = 1;
`elsif TEST_CONV1_TILE_FIFO_DEPTH_2
    localparam integer CONV1_TILE_FIFO_DEPTH = 2;
`elsif TEST_CONV1_TILE_FIFO_DEPTH_4
    localparam integer CONV1_TILE_FIFO_DEPTH = 4;
`else
    localparam integer CONV1_TILE_FIFO_DEPTH = 2;
`endif
`ifdef TEST_V_REPLAY_GROUP_DEPTH_1
    localparam integer V_REPLAY_GROUP_DEPTH = 1;
`else
    localparam integer V_REPLAY_GROUP_DEPTH = 2;
`endif
`ifdef TEST_M_FIFO_DEPTH_1
    localparam integer M_FIFO_DEPTH = 1;
`else
    localparam integer M_FIFO_DEPTH = 2;
`endif
    reg clk;
    reg rst_n;
    reg [7:0] data_in;
    wire [3:0] decision;
    wire valid_out_6;

    reg [191:0]  conv1_u;
    reg [575:0]  conv2_u;
    reg [47:0]   conv1_bias;
    reg [47:0]   conv2_bias;
    reg [23:0]   conv1_requant_multiplier;
    reg [23:0]   conv2_requant_multiplier;
    reg [2999:0] fc_weight;
    reg [159:0]  fc_bias;

    reg [7:0] pixel_memory [0:783999];
    reg [3:0] label_memory [0:999];
    reg [3:0] prediction_memory [0:999];
    reg [3:0] conv1_u_memory [0:47];
    reg [3:0] conv2_u_memory [0:143];
    reg [15:0] conv1_bias_memory [0:2];
    reg [15:0] conv2_bias_memory [0:2];
    reg [3:0] fc_weight_memory [0:749];
    reg [15:0] fc_bias_memory [0:9];

    integer tensor_index;
    integer image_index;
    integer pixel_index;
    integer cycle_in_image;
    integer rtl_mismatches;
    integer correct;
    integer max_conv1_tile_fifo_occupancy;
    integer max_v_replay_group_occupancy;
    integer max_m_fifo_occupancy;
    integer input_backpressure_cycles;
    integer v_replay_backpressure_cycles;
    integer m_fifo_backpressure_cycles;
    integer total_tail_cycles;
    integer max_tail_cycles;
`ifdef FIFO_TRACE
    integer trace_file;
    integer trace_cycle;
`endif
`ifdef LIFETIME_TRACE
    integer lifetime_file;
    integer lifetime_cycle;
`endif

`ifdef GATE_LEVEL
    chip dut (
`else
    chip #(
        .CONV1_TILE_FIFO_DEPTH(CONV1_TILE_FIFO_DEPTH),
        .V_REPLAY_GROUP_DEPTH(V_REPLAY_GROUP_DEPTH),
        .M_FIFO_DEPTH(M_FIFO_DEPTH)
    ) dut (
`endif
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .decision(decision),
        .valid_out_6(valid_out_6),
        .conv1_u(conv1_u),
        .conv2_u(conv2_u),
        .conv1_bias(conv1_bias),
        .conv2_bias(conv2_bias),
        .conv1_requant_multiplier(conv1_requant_multiplier),
        .conv2_requant_multiplier(conv2_requant_multiplier),
        .fc_weight(fc_weight),
        .fc_bias(fc_bias)
    );

`ifndef GATE_LEVEL
    always @(posedge clk) begin
        if (rst_n
            && (dut.u_accelerator.u_conv1_tile_fifo.count
                > max_conv1_tile_fifo_occupancy))
            max_conv1_tile_fifo_occupancy =
                dut.u_accelerator.u_conv1_tile_fifo.count;
        if (rst_n
            && (dut.u_accelerator.u_core.u_v_buffer.group_count
                > max_v_replay_group_occupancy))
            max_v_replay_group_occupancy =
                dut.u_accelerator.u_core.u_v_buffer.group_count;
        if (rst_n
            && (dut.u_accelerator.u_core.u_m_fifo.u_fifo.count
                > max_m_fifo_occupancy))
            max_m_fifo_occupancy =
                dut.u_accelerator.u_core.u_m_fifo.u_fifo.count;
        if (rst_n
            && dut.u_accelerator.u_core.transform_valid
            && !dut.u_accelerator.u_core.transform_ready)
            v_replay_backpressure_cycles =
                v_replay_backpressure_cycles + 1;
        if (rst_n
            && dut.u_accelerator.u_core.mac_valid
            && !dut.u_accelerator.u_core.conv_mac_ready
            && !dut.u_accelerator.u_core.mode_fc)
            m_fifo_backpressure_cycles =
                m_fifo_backpressure_cycles + 1;
`ifdef FIFO_TRACE
        if (!rst_n) begin
            trace_cycle = 0;
        end else if ((image_index == 0) && (trace_file != 0)) begin
            $fwrite(trace_file,
                    "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                    trace_cycle,
                    dut.pixel_count,
                    dut.image_ready,
                    dut.u_accelerator.bank_a_raw_tile_valid,
                    dut.u_accelerator.bank_a_raw_tile_ready,
                    dut.u_accelerator.u_conv1_tile_fifo.count,
                    dut.u_accelerator.bank_a_tile_valid,
                    dut.u_accelerator.bank_a_tile_ready,
                    dut.u_accelerator.core_in_ready,
                    dut.u_accelerator.state);
            trace_cycle = trace_cycle + 1;
        end
`endif
`ifdef LIFETIME_TRACE
        if (!rst_n) begin
            lifetime_cycle = 0;
        end else if ((image_index == 0) && (lifetime_file != 0)) begin
            $fwrite(lifetime_file,
                    "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                    lifetime_cycle,
                    dut.u_accelerator.state,
                    dut.pixel_count,
                    dut.image_ready,
                    dut.u_accelerator.b_frame_write_valid,
                    dut.u_accelerator.b_frame_write_ready,
                    dut.u_accelerator.u_conv1_output_frame_buffer.write_pointer,
                    dut.u_accelerator.b_frame_full,
                    dut.u_accelerator.u_conv1_output_frame_buffer.read_active,
                    dut.u_accelerator.u_conv1_output_frame_buffer.read_pointer,
                    dut.u_accelerator.b_frame_read_valid,
                    dut.u_accelerator.b_frame_read_ready,
                    dut.u_accelerator.core_output_transfer,
                    dut.u_accelerator.core_output_channel,
                    dut.u_accelerator.spatial_index);
            lifetime_cycle = lifetime_cycle + 1;
        end
`endif
    end
`endif

`ifdef GATE_LEVEL
    // 1 ns target period for ASAP7 cell-level simulation.
    always #500 clk = ~clk;
`else
    // Delay-free RTL simulation uses a short period for faster wall time.
    always #5 clk = ~clk;
`endif

    initial begin
        max_conv1_tile_fifo_occupancy = 0;
        max_v_replay_group_occupancy = 0;
        max_m_fifo_occupancy = 0;
        input_backpressure_cycles = 0;
        v_replay_backpressure_cycles = 0;
        m_fifo_backpressure_cycles = 0;
        total_tail_cycles = 0;
        max_tail_cycles = 0;
`ifdef FIFO_TRACE
        trace_cycle = 0;
        trace_file = $fopen("fifo_depth_trace.csv", "w");
        $fwrite(trace_file,
                "cycle,pixel_count,image_ready,tile_in_valid,tile_in_ready,fifo_count,tile_out_valid,tile_out_ready,core_in_ready,state\n");
`endif
`ifdef LIFETIME_TRACE
        lifetime_cycle = 0;
        lifetime_file = $fopen("activation_lifetime_trace.csv", "w");
        $fwrite(lifetime_file,
                "cycle,state,pixel_count,image_ready,frame_write_valid,frame_write_ready,frame_write_pointer,frame_full,frame_read_active,frame_read_pointer,frame_read_valid,frame_read_ready,core_output_transfer,core_output_channel,spatial_index\n");
`endif
        $readmemh("../../../data/input_1000.txt", pixel_memory);
        $readmemh("../../../training/export/qat_winograd3x3_w4_frozen_aug/competition_labels_1000.txt",
                  label_memory);
        $readmemh("../../../training/export/qat_winograd3x3_w4_frozen_aug/competition_predictions_1000.txt",
                  prediction_memory);
        $readmemh("../../../training/export/qat_winograd3x3_w4_frozen_aug/conv1_u_twos_complement.hex",
                  conv1_u_memory);
        $readmemh("../../../training/export/qat_winograd3x3_w4_frozen_aug/conv2_u_twos_complement.hex",
                  conv2_u_memory);
        $readmemh("../../../training/export/qat_winograd3x3_w4_frozen_aug/conv1_bias_twos_complement.hex",
                  conv1_bias_memory);
        $readmemh("../../../training/export/qat_winograd3x3_w4_frozen_aug/conv2_bias_twos_complement.hex",
                  conv2_bias_memory);
        $readmemh("../../../training/export/qat_winograd3x3_w4_frozen_aug/fc_weight_twos_complement.hex",
                  fc_weight_memory);
        $readmemh("../../../training/export/qat_winograd3x3_w4_frozen_aug/fc_bias_twos_complement.hex",
                  fc_bias_memory);

        clk = 1'b0;
        // Start deasserted so every image, including image 0, receives an
        // explicit high-to-low asynchronous-reset edge.  This is important
        // for zero-delay functional standard-cell models whose flops begin X.
        rst_n = 1'b1;
        data_in = 8'd0;
        conv1_u = 0;
        conv2_u = 0;
        conv1_bias = 0;
        conv2_bias = 0;
        conv1_requant_multiplier = 24'd1616163;
        conv2_requant_multiplier = 24'd1827841;
        fc_weight = 0;
        fc_bias = 0;
        rtl_mismatches = 0;
        correct = 0;

        for (tensor_index = 0; tensor_index < 48;
             tensor_index = tensor_index + 1)
            conv1_u[tensor_index*4 +: 4] = conv1_u_memory[tensor_index];
        for (tensor_index = 0; tensor_index < 144;
             tensor_index = tensor_index + 1)
            conv2_u[tensor_index*4 +: 4] = conv2_u_memory[tensor_index];
        for (tensor_index = 0; tensor_index < 3;
             tensor_index = tensor_index + 1) begin
            conv1_bias[tensor_index*16 +: 16]
                = conv1_bias_memory[tensor_index];
            conv2_bias[tensor_index*16 +: 16]
                = conv2_bias_memory[tensor_index];
        end
        for (tensor_index = 0; tensor_index < 750;
             tensor_index = tensor_index + 1)
            fc_weight[tensor_index*4 +: 4] = fc_weight_memory[tensor_index];
        for (tensor_index = 0; tensor_index < 10;
             tensor_index = tensor_index + 1)
            fc_bias[tensor_index*16 +: 16] = fc_bias_memory[tensor_index];

        for (image_index = 0; image_index < TEST_IMAGE_COUNT;
             image_index = image_index + 1) begin
            @(negedge clk);
            rst_n = 1'b0;
            repeat (3) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;

            // Match the supplied reference harness: pixel 0 is already held
            // while START_CONV1 changes to RUN_CONV1, then the source advances
            // exactly once per cycle without observing ready.
            data_in = pixel_memory[image_index*784];
`ifndef GATE_LEVEL
            while (!dut.image_ready)
                @(negedge clk);
`else
            // START_CONV1 occupies exactly one clock in the synthesized FSM.
            @(negedge clk);
`endif
            for (pixel_index = 1; pixel_index < 784;
                 pixel_index = pixel_index + 1) begin
                @(negedge clk);
`ifndef GATE_LEVEL
                if (!dut.image_ready) begin
                    input_backpressure_cycles =
                        input_backpressure_cycles + 1;
                    $display("ERROR: input backpressure image=%0d pixel=%0d",
                             image_index, pixel_index);
                    rtl_mismatches = rtl_mismatches + 1;
                end
`endif
                data_in = pixel_memory[image_index*784 + pixel_index];
            end

            cycle_in_image = 0;
            while ((valid_out_6 !== 1'b1) && cycle_in_image < 3000) begin
                @(posedge clk);
                cycle_in_image = cycle_in_image + 1;
            end
            total_tail_cycles = total_tail_cycles + cycle_in_image;
            if (cycle_in_image > max_tail_cycles)
                max_tail_cycles = cycle_in_image;
            if (valid_out_6 !== 1'b1) begin
                $display("ERROR: timeout image=%0d", image_index);
                rtl_mismatches = rtl_mismatches + 1;
            end else begin
                if (decision !== prediction_memory[image_index]) begin
                    $display("ERROR: RTL/Python mismatch image=%0d rtl=%0d python=%0d",
                             image_index, decision,
                             prediction_memory[image_index]);
                    rtl_mismatches = rtl_mismatches + 1;
                end
                if (decision === label_memory[image_index])
                    correct = correct + 1;
            end

            if (((image_index + 1) % 100) == 0)
                $display("Progress: %0d/%0d, correct=%0d",
                         image_index + 1, TEST_IMAGE_COUNT,
                         correct);
        end

        $display("RTL mismatches: %0d", rtl_mismatches);
        $display("Correct: %0d/%0d", correct, TEST_IMAGE_COUNT);
        if (TEST_IMAGE_COUNT == 1000)
            $display("Accuracy: %0d.%0d%%", correct/10, correct%10);
        else
            $display("Accuracy: %0d%%", (100*correct)/TEST_IMAGE_COUNT);
`ifndef GATE_LEVEL
        $display("Conv1 tile FIFO depth: %0d", CONV1_TILE_FIFO_DEPTH);
        $display("Conv1 tile FIFO max occupancy: %0d",
                 max_conv1_tile_fifo_occupancy);
        $display("V replay group depth: %0d", V_REPLAY_GROUP_DEPTH);
        $display("V replay max group occupancy: %0d",
                 max_v_replay_group_occupancy);
        $display("V replay backpressure cycles: %0d",
                 v_replay_backpressure_cycles);
        $display("M FIFO depth: %0d", M_FIFO_DEPTH);
        $display("M FIFO max occupancy: %0d", max_m_fifo_occupancy);
        $display("M FIFO backpressure cycles: %0d",
                 m_fifo_backpressure_cycles);
        $display("Input backpressure cycles: %0d",
                 input_backpressure_cycles);
        $display("Average post-input cycles: %0d",
                 total_tail_cycles/TEST_IMAGE_COUNT);
        $display("Maximum post-input cycles: %0d", max_tail_cycles);
`endif
`ifdef FIFO_TRACE
        $fclose(trace_file);
        $display("TRACE: FIFO depth characterization complete");
`elsif LIFETIME_TRACE
        $fclose(lifetime_file);
        $display("TRACE: activation lifetime characterization complete");
`elsif POWER_TRACE
        if (rtl_mismatches == 0)
            $display("PASS: one-image power activity regression");
        else
            $display("FAIL: one-image power activity regression");
`else
        if ((rtl_mismatches == 0) && (correct == 970))
            $display("PASS: Winograd chip 1000-image regression");
        else
            $display("FAIL: Winograd chip 1000-image regression");
`endif
        $finish;
    end
endmodule
