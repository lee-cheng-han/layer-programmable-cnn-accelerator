interface cnn_axi_lite_if(input logic aclk);
  logic aresetn;
  logic [11:0] awaddr;
  logic awvalid;
  logic awready;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic wvalid;
  logic wready;
  logic [1:0] bresp;
  logic bvalid;
  logic bready;
  logic [11:0] araddr;
  logic arvalid;
  logic arready;
  logic [31:0] rdata;
  logic [1:0] rresp;
  logic rvalid;
  logic rready;

  task automatic reset_master();
    awaddr = '0;
    awvalid = 1'b0;
    wdata = '0;
    wstrb = '0;
    wvalid = 1'b0;
    bready = 1'b0;
    araddr = '0;
    arvalid = 1'b0;
    rready = 1'b0;
  endtask

  a_aw_stable_while_stalled: assert property (@(posedge aclk)
    disable iff (!aresetn)
    awvalid && !awready |=> awvalid && $stable(awaddr));

  a_w_stable_while_stalled: assert property (@(posedge aclk)
    disable iff (!aresetn)
    wvalid && !wready |=> wvalid && $stable({wdata, wstrb}));

  a_b_stable_while_stalled: assert property (@(posedge aclk)
    disable iff (!aresetn)
    bvalid && !bready |=> bvalid && $stable(bresp));

  a_ar_stable_while_stalled: assert property (@(posedge aclk)
    disable iff (!aresetn)
    arvalid && !arready |=> arvalid && $stable(araddr));

  a_r_stable_while_stalled: assert property (@(posedge aclk)
    disable iff (!aresetn)
    rvalid && !rready |=> rvalid && $stable({rdata, rresp}));

  a_bresp_legal: assert property (@(posedge aclk)
    disable iff (!aresetn)
    bvalid |-> bresp inside {2'b00, 2'b10});

  a_rresp_legal: assert property (@(posedge aclk)
    disable iff (!aresetn)
    rvalid |-> rresp inside {2'b00, 2'b10});

  covergroup axi_protocol_cg @(posedge aclk);
    option.per_instance = 1;
    write_response_stall_cp: coverpoint (bvalid && !bready) iff (aresetn) {
      bins observed = {1};
    }
    read_response_stall_cp: coverpoint (rvalid && !rready) iff (aresetn) {
      bins observed = {1};
    }
    error_response_cp: coverpoint (
      (bvalid && bready && bresp == 2'b10) ||
      (rvalid && rready && rresp == 2'b10)) iff (aresetn) {
      bins observed = {1};
    }
  endgroup
  axi_protocol_cg protocol_coverage = new;
endinterface
