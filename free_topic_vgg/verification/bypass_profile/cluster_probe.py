"""Read-only cycle accounting for the frozen Conv5 cluster."""
def instrument(tb):
    counters='''
    integer audit_cycles=0, build_hit=0, build_pad=0, build_miss=0, build_block=0;
    integer req_cycles=0, req_stall=0, rsp_cycles=0, rsp_stall=0, drain_cycles=0, other_cycles=0;
    integer feed_words=0, last_feed=0, unique_reads=0;
    bit [2047:0] seen_words=0;
    integer cs[0:15][0:8];
    integer accepted_mac[0:15], v_missing[0:15], row_blocked[0:15], mac_blocked[0:15];
    integer busy_other[0:15], rx_missing[0:15], rx_blocked[0:15], core_finish[0:15];
    integer producer_no_tile[0:15];
    always @(posedge clk) if(rst_n && dut.u_cluster.state==2) begin
        audit_cycles++;
        case(dut.u_cluster.u_feed.state)
            1: if(!dut.u_cluster.u_feed.word_room) build_block++;
               else if(dut.u_cluster.u_feed.padding) build_pad++;
               else if(dut.u_cluster.u_feed.cache_hit) build_hit++;
               else build_miss++;
            2: begin
                req_cycles++;
                if(!( |(dut.u_cluster.read_valid & dut.u_cluster.read_ready))) req_stall++;
                else if(!seen_words[dut.u_cluster.u_feed.request_word]) begin
                    seen_words[dut.u_cluster.u_feed.request_word]=1;unique_reads++;
                end
            end
            3: begin rsp_cycles++; if(!dut.u_cluster.u_feed.response_fire) rsp_stall++;end
            4: drain_cycles++;
            default: other_cycles++;
        endcase
        if(dut.u_cluster.feed_valid && dut.u_cluster.feed_ready) begin
            feed_words++;last_feed=audit_cycles;
        end
    end
    genvar p;
    generate for(p=0;p<16;p++) begin: probe
        initial begin
            for(integer z=0;z<9;z++) cs[p][z]=0;
            accepted_mac[p]=0;v_missing[p]=0;row_blocked[p]=0;mac_blocked[p]=0;
            busy_other[p]=0;rx_missing[p]=0;rx_blocked[p]=0;core_finish[p]=0;
            producer_no_tile[p]=0;
        end
        always @(posedge clk) if(rst_n && dut.u_cluster.state==2) begin
            cs[p][dut.u_cluster.g_core[p].u_compute.consumer_state]++;
            if(!dut.u_cluster.core_done[p]) core_finish[p]=audit_cycles;
            if(dut.u_cluster.g_core[p].rx_ready && !dut.u_cluster.g_core[p].rx_valid) rx_missing[p]++;
            if(dut.u_cluster.g_core[p].rx_valid && !dut.u_cluster.g_core[p].rx_ready) rx_blocked[p]++;
            if(dut.u_cluster.g_core[p].u_compute.producer_state==3 &&
               !dut.u_cluster.g_core[p].u_compute.window_valid) producer_no_tile[p]++;
            if(dut.u_cluster.g_core[p].u_compute.u_core.u_engine.response_valid &&
               dut.u_cluster.g_core[p].u_compute.u_core.u_engine.mac_ready) accepted_mac[p]++;
            else if(dut.u_cluster.g_core[p].u_compute.u_core.u_engine.busy) begin
                if(dut.u_cluster.g_core[p].u_compute.u_core.u_engine.response_valid &&
                   !dut.u_cluster.g_core[p].u_compute.u_core.u_engine.mac_ready) mac_blocked[p]++;
                else if(!dut.u_cluster.g_core[p].u_compute.u_core.u_engine.last_requested &&
                        !(|dut.u_cluster.g_core[p].u_compute.u_core.u_engine.remaining_valid) &&
                        !(&dut.u_cluster.g_core[p].u_compute.u_core.u_engine.last_in_row)) v_missing[p]++;
                else if((|dut.u_cluster.g_core[p].u_compute.u_core.row_read) &&
                        !dut.u_cluster.g_core[p].u_compute.u_core.row_accept) row_blocked[p]++;
                else busy_other[p]++;
            end
        end
    end endgenerate
'''
    tb=tb.replace('    integer chosen_stage=0,',counters+'\n    integer chosen_stage=0,')
    report='''
            if(audit_cycles!=build_hit+build_pad+build_miss+build_block+req_cycles+rsp_cycles+drain_cycles+other_cycles)
                $fatal(1,"Feed cycle partition mismatch");
            $display("FEED_AUDIT cycles=%0d hit=%0d pad=%0d miss=%0d blocked=%0d request=%0d request_stall=%0d response=%0d response_stall=%0d drain=%0d other=%0d words=%0d last_feed=%0d unique_reads=%0d",audit_cycles,build_hit,build_pad,build_miss,build_block,req_cycles,req_stall,rsp_cycles,rsp_stall,drain_cycles,other_cycles,feed_words,last_feed,unique_reads);
            for(integer z=0;z<16;z++) begin
                $display("CORE_AUDIT core=%0d wait_v_slot=%0d job=%0d mac_state=%0d weights=%0d done=%0d mac_beats=%0d v_missing=%0d row_blocked=%0d mac_blocked=%0d busy_other=%0d rx_missing=%0d rx_blocked=%0d producer_no_tile=%0d finish=%0d",z,cs[z][0],cs[z][1],cs[z][2],cs[z][3],cs[z][8],accepted_mac[z],v_missing[z],row_blocked[z],mac_blocked[z],busy_other[z],rx_missing[z],rx_blocked[z],producer_no_tile[z],core_finish[z]);
            end
'''
    tb=tb.replace('            sum_beats=0;sum_lanes=0;',report+'\n            sum_beats=0;sum_lanes=0;')
    return tb
