interface cnn_axis_if(input logic aclk,
                      input logic three_byte_terminal_reachable);
  logic aresetn;
  logic [31:0] tdata;
  logic [3:0] tkeep;
  logic tvalid;
  logic tready;
  logic tlast;

  task automatic reset_source();
    tdata = '0;
    tkeep = '0;
    tvalid = 1'b0;
    tlast = 1'b0;
  endtask

  a_payload_stable_while_stalled: assert property (@(posedge aclk)
    disable iff (!aresetn)
    tvalid && !tready |=> tvalid && $stable({tdata, tkeep, tlast}));

  a_tkeep_is_contiguous_low: assert property (@(posedge aclk)
    disable iff (!aresetn)
    tvalid |-> tkeep inside {4'b0001, 4'b0011, 4'b0111, 4'b1111});

  a_tlast_requires_valid: assert property (@(posedge aclk)
    disable iff (!aresetn)
    tlast |-> tvalid);

  covergroup axis_protocol_cg(bit cover_three_byte_terminal) @(posedge aclk);
    option.per_instance = 1;
    backpressure_cp: coverpoint (tvalid && !tready) iff (aresetn) {
      bins observed = {1};
    }
    terminal_keep_cp: coverpoint tkeep
      iff (aresetn && tvalid && tready && tlast) {
      bins partial[] = {4'b0001, 4'b0011, 4'b0111};
      bins full = {4'b1111};
      ignore_bins unreachable_three_byte = {4'b0111}
        with (!cover_three_byte_terminal);
    }
  endgroup
  axis_protocol_cg protocol_coverage = new(three_byte_terminal_reachable);
endinterface
