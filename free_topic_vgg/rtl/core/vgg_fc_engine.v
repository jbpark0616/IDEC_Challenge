`default_nettype none
// CIFAR VGG classifier boundary: 512 inputs, 32 hidden outputs/core or
// 10 final outputs on core0. No multipliers/accumulators for dot products:
// the designated MAC array is shared with convolution through its FC mode.
// U banks: address group*256 + input/2, four INT8 output weights/channel/row.
// Metadata: U bank r, address 512+group*4+column = {8'b0,mult24,bias32}.
// V bank0 words 0..63 retain the input until both output groups finish.
module vgg_fc_engine (
    input wire clk, rst_n, start, final_layer,
    output wire start_ready, done,
    input wire done_ready,
    input wire input_valid,
    output wire input_ready,
    input wire [63:0] input_data,
    output wire [3:0] row_read, v_read_enable,
    input wire row_accept,
    output wire [39:0] u_addr, v_addr,
    input wire [255:0] u_data, v_data,
    output wire [3:0] write_rows,
    input wire [3:0] write_ready,
    output wire [9:0] write_addr,
    output wire [255:0] write_data,
    output wire mac_valid,
    input wire mac_ready,
    output wire mac_first, mac_last,
    output wire [7:0] mac_activation,
    output wire [255:0] mac_weights,
    output wire [511:0] mac_biases,
    input wire mac_result_valid,
    output wire mac_result_ready,
    input wire [767:0] mac_result,
    output reg word_valid,
    input wire word_ready,
    output reg [63:0] word_data,
    output reg [10:0] word_address,
    output reg word_last,
    output reg [3:0] class_index,
    output reg [31:0] cycles, feature_issues
);
    localparam [3:0] IDLE=0, META_REQUEST=1, META_RESPONSE=2,
        COMPUTE=3, WAIT_RESULT=4, POST=5, DRAIN=6, DONE=7;
    reg [3:0] state;
    reg final_mode, group_index;
    reg [1:0] meta_column;
    reg [6:0] filled_words;
    reg [8:0] feature_index, response_feature;
    reg response_valid;
    reg [511:0] biases;
    reg [383:0] multipliers;
    reg [3:0] post_lane;
    reg signed [63:0] best_score;
    wire active = state!=IDLE && state!=DONE;
    wire request_meta = state==META_REQUEST;
    wire request_feature = state==COMPUTE && (!response_valid || mac_ready)
                         && filled_words>{1'b0,feature_index[8:3]};
    wire feature_fire = request_feature && row_accept;
    wire word_fire = word_valid && word_ready;
    wire post_fire = state==POST && (!word_valid || word_ready);
    wire last_lane = post_lane==(final_mode ? 4'd9 : 4'd15);
    wire last_group = final_mode || group_index;

    assign start_ready = state==IDLE;
    assign done = state==DONE;
    assign write_rows = {3'b0,active && filled_words<7'd64 && input_valid};
    assign input_ready = active && filled_words<7'd64 && write_ready[0];
    assign write_addr = {3'b0,filled_words};
    assign write_data = {192'b0,input_data};
    assign row_read = {4{request_meta || request_feature}};
    assign v_read_enable = request_feature ? 4'b0001 : 4'b0000;
    assign u_addr = {4{request_meta ? (10'd512+{7'b0,group_index,meta_column})
                                  : {1'b0,group_index,feature_index[8:1]}}};
    assign v_addr = {4{{4'b0,feature_index[8:3]}}};
    assign mac_valid = response_valid;
    assign mac_first = response_feature==0;
    assign mac_last = response_feature==511;
    assign mac_activation = v_data[response_feature[2:0]*8 +: 8];
    assign mac_biases = biases;
    assign mac_result_ready = post_fire && last_lane;

    genvar r,c;
    generate for(r=0;r<4;r=r+1) begin : g_row
        wire [31:0] half_word = response_feature[0] ? u_data[r*64+32 +: 32] : u_data[r*64 +: 32];
        for(c=0;c<4;c=c+1) begin : g_lane
            wire [7:0] weight_byte=half_word[c*8 +: 8];
            assign mac_weights[(r*4+c)*16 +: 16]={{8{weight_byte[7]}},weight_byte};
            always @(posedge clk) if(state==META_RESPONSE && meta_column==c) begin
                biases[(r*4+c)*32 +: 32]<=u_data[r*64 +: 32];
                multipliers[(r*4+c)*24 +: 24]<=u_data[r*64+32 +: 24];
            end
        end
    end endgenerate

    // One scalar requantizer, reused across the sixteen completed outputs.
    // Preserve signed logits for FC3; hidden layers use ReLU and UINT8 clamp.
    wire signed [47:0] accumulator=mac_result[post_lane*48 +: 48];
    wire signed [47:0] post_value=(!final_mode && accumulator[47]) ? 48'sd0 : accumulator;
    wire signed [24:0] multiplier={1'b0,multipliers[post_lane*24 +: 24]};
    wire signed [72:0] product=post_value*multiplier;
    wire signed [73:0] rounded={product[72],product}+74'sd8388608;
    wire signed [73:0] shifted=rounded >>> 24;
    wire signed [63:0] score=shifted[63:0];
    wire [7:0] activation=shifted>74'sd255 ? 8'd255 : shifted[7:0];

    always @(posedge clk) begin
        if(start && start_ready) begin
            final_mode<=final_layer;
            word_data<=0;
        end
        if(feature_fire) response_feature<=feature_index;
        if(post_fire) begin
            word_address<=final_mode ? {7'b0,post_lane} : {9'b0,group_index,post_lane[3]};
            if(final_mode) word_data<=score;
            else if(post_lane[2:0]==0) word_data<={56'b0,activation};
            else word_data[post_lane[2:0]*8 +: 8]<=activation;
            if(final_mode && (post_lane==0 || score>best_score)) begin
                best_score<=score;
                class_index<=post_lane;
            end
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; group_index<=0; meta_column<=0; filled_words<=0;
            feature_index<=0; response_valid<=0; post_lane<=0;
            word_valid<=0; word_last<=0; cycles<=0; feature_issues<=0;
        end else begin
            if(active) cycles<=cycles+1'b1;
            if(input_valid && input_ready) filled_words<=filled_words+1'b1;
            if(!response_valid || mac_ready) response_valid<=feature_fire;
            if(feature_fire) begin
                feature_index<=feature_index+1'b1;
                feature_issues<=feature_issues+1'b1;
                if(feature_index==511) state<=WAIT_RESULT;
            end
            if(word_fire) word_valid<=0;
            case(state)
                IDLE: if(start) begin
                    state<=META_REQUEST; group_index<=0; meta_column<=0;
                    filled_words<=0; feature_index<=0; response_valid<=0;
                    word_valid<=0; word_last<=0; cycles<=0; feature_issues<=0;
                end
                META_REQUEST: if(row_accept) state<=META_RESPONSE;
                META_RESPONSE: begin
                    meta_column<=meta_column+1'b1;
                    state<=meta_column==3 ? COMPUTE : META_REQUEST;
                end
                WAIT_RESULT: if(mac_result_valid) begin state<=POST; post_lane<=0; end
                POST: if(post_fire) begin
                    if(final_mode || post_lane[2:0]==7) begin
                        word_valid<=1;
                        word_last<=last_lane && last_group;
                    end
                    post_lane<=post_lane+1'b1;
                    if(last_lane) state<=DRAIN;
                end
                DRAIN: if(word_fire) begin
                    if(last_group) state<=DONE;
                    else begin
                        group_index<=1; meta_column<=0; feature_index<=0;
                        state<=META_REQUEST;
                    end
                end
                DONE: if(done_ready) state<=IDLE;
                default: begin end
            endcase
        end
    end
endmodule
`default_nettype wire
