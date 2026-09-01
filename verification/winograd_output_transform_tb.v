`timescale 1ns/1ps

module winograd_output_transform_tb;
    localparam integer ACC_BITS = 18;
    localparam integer ACC_MAX = 131071;
    localparam integer ACC_MIN = -131072;

    reg clk;
    reg rst_n;
    reg in_valid;
    wire in_ready;
    reg [16*ACC_BITS-1:0] m_tile;
    wire out_valid;
    reg out_ready;
    wire [4*ACC_BITS-1:0] y_tile;
    wire [1:0] out_user;

    integer m_value [0:15];
    integer left_value [0:7];
    integer expected [0:3];
    integer burst_expected [0:11];
    integer row;
    integer col;
    integer element;
    integer test_index;
    integer burst_drive;
    integer burst_receive;
    integer got;
    integer errors;
    reg [4*ACC_BITS-1:0] held_result;

    winograd_output_transform dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .m_tile(m_tile),
        .in_user(2'b00),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .y_tile(y_tile),
        .out_user(out_user)
    );

    always #5 clk = ~clk;

    function integer sat18;
        input integer value;
        begin
            if (value > ACC_MAX)
                sat18 = ACC_MAX;
            else if (value < ACC_MIN)
                sat18 = ACC_MIN;
            else
                sat18 = value;
        end
    endfunction

    task calculate_golden;
        integer first_value;
        begin
            for (col = 0; col < 4; col = col + 1) begin
                first_value = sat18(m_value[0*4+col] + m_value[1*4+col]);
                left_value[0*4+col] = sat18(first_value + m_value[2*4+col]);
                first_value = sat18(m_value[1*4+col] - m_value[2*4+col]);
                left_value[1*4+col] = sat18(first_value - m_value[3*4+col]);
            end
            for (row = 0; row < 2; row = row + 1) begin
                first_value = sat18(left_value[row*4+0] + left_value[row*4+1]);
                expected[row*2+0] = sat18(first_value + left_value[row*4+2]);
                first_value = sat18(left_value[row*4+1] - left_value[row*4+2]);
                expected[row*2+1] = sat18(first_value - left_value[row*4+3]);
            end
        end
    endtask

    task send_tile;
        begin
            calculate_golden();
            for (element = 0; element < 16; element = element + 1)
                m_tile[element*ACC_BITS +: ACC_BITS] = m_value[element];
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
            for (element = 0; element < 4; element = element + 1) begin
                got = $signed(y_tile[element*ACC_BITS +: ACC_BITS]);
                if (got !== expected[element]) begin
                    $display("FAIL %-40s element=%0d expected=%0d got=%0d",
                             test_name, element, expected[element], got);
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        in_valid = 1'b0;
        m_tile = 0;
        out_ready = 1'b1;
        errors = 0;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        for (element = 0; element < 16; element = element + 1)
            m_value[element] = 0;
        send_tile();
        check_tile("all-zero M tile");

        // Alternating extrema force saturation at multiple tree levels.
        for (row = 0; row < 4; row = row + 1)
            for (col = 0; col < 4; col = col + 1)
                m_value[row*4+col] = ((row+col) & 1) ? ACC_MIN : ACC_MAX;
        send_tile();
        check_tile("alternating INT18 extrema");

        // Asymmetric values catch transform orientation and packing errors.
        for (element = 0; element < 16; element = element + 1)
            m_value[element] = element*7919 - 60000;
        send_tile();
        check_tile("row-major asymmetric M tile");

        for (test_index = 0; test_index < 100; test_index = test_index + 1) begin
            for (element = 0; element < 16; element = element + 1)
                m_value[element] = ($random & 18'h3ffff) - 131072;
            send_tile();
            check_tile("random saturating golden");
        end

        // Verify one M tile can be accepted on each consecutive cycle.
        fork
            begin : burst_driver
                @(negedge clk);
                for (burst_drive = 0; burst_drive < 3; burst_drive = burst_drive + 1) begin
                    while (!in_ready)
                        @(negedge clk);
                    for (element = 0; element < 16; element = element + 1)
                        m_value[element] =
                            ((burst_drive*65537 + element*17011) & 18'h3ffff) - 131072;
                    calculate_golden();
                    for (element = 0; element < 16; element = element + 1)
                        m_tile[element*ACC_BITS +: ACC_BITS] = m_value[element];
                    for (element = 0; element < 4; element = element + 1)
                        burst_expected[burst_drive*4+element] = expected[element];
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
                    for (element = 0; element < 4; element = element + 1) begin
                        got = $signed(y_tile[element*ACC_BITS +: ACC_BITS]);
                        if (got !== burst_expected[burst_receive*4+element]) begin
                            $display("FAIL burst tile=%0d element=%0d expected=%0d got=%0d",
                                     burst_receive, element,
                                     burst_expected[burst_receive*4+element], got);
                            errors = errors + 1;
                        end
                    end
                end
            end
        join

        @(negedge clk);
        out_ready = 1'b0;
        for (element = 0; element < 16; element = element + 1)
            m_value[element] = element*12347 - 90000;
        send_tile();
        check_tile("backpressure result");
        held_result = y_tile;
        repeat (3) begin
            @(negedge clk);
            if (!out_valid || y_tile !== held_result) begin
                $display("FAIL output changed while out_ready=0");
                errors = errors + 1;
            end
        end
        out_ready = 1'b1;
        @(negedge clk);

        if (errors == 0)
            $display("PASS winograd_output_transform: all tests passed");
        else
            $display("FAIL winograd_output_transform: %0d error(s)", errors);

        $finish;
    end

endmodule
