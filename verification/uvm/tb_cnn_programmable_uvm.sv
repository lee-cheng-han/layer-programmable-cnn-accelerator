`timescale 1ns/1ps

module tb_cnn_programmable_uvm;
  import uvm_pkg::*;
  import cnn_uvm_pkg::*;
  import cnn_uvm_tests_pkg::*;

  logic aclk = 1'b0;
  logic aresetn = 1'b0;
  always #4 aclk = ~aclk;

  cnn_axi_lite_if axi_if(aclk);
  cnn_axis_if input_if(aclk);
  cnn_axis_if output_if(aclk);
  cnn_status_if status_if(aclk);

  assign axi_if.aresetn = aresetn;
  assign input_if.aresetn = aresetn;
  assign output_if.aresetn = aresetn;
  assign status_if.aresetn = aresetn;

  cnn_programmable_system_top #(
    .PC(2), .PK(2), .MAX_CIN(2), .MAX_COUT(2),
    .MAX_LAYERS(2), .MAX_TENSORS(4), .MAX_QUANTIZATIONS(2),
    .MAX_TILE_WIDTH(2), .MAX_TILE_HEIGHT(2)
  ) dut (
    .aclk(aclk), .aresetn(aresetn),
    .s_axi_awaddr(axi_if.awaddr), .s_axi_awvalid(axi_if.awvalid),
    .s_axi_awready(axi_if.awready), .s_axi_wdata(axi_if.wdata),
    .s_axi_wstrb(axi_if.wstrb), .s_axi_wvalid(axi_if.wvalid),
    .s_axi_wready(axi_if.wready), .s_axi_bresp(axi_if.bresp),
    .s_axi_bvalid(axi_if.bvalid), .s_axi_bready(axi_if.bready),
    .s_axi_araddr(axi_if.araddr), .s_axi_arvalid(axi_if.arvalid),
    .s_axi_arready(axi_if.arready), .s_axi_rdata(axi_if.rdata),
    .s_axi_rresp(axi_if.rresp), .s_axi_rvalid(axi_if.rvalid),
    .s_axi_rready(axi_if.rready),
    .s_axis_tdata(input_if.tdata), .s_axis_tkeep(input_if.tkeep),
    .s_axis_tvalid(input_if.tvalid), .s_axis_tready(input_if.tready),
    .s_axis_tlast(input_if.tlast), .m_axis_tdata(output_if.tdata),
    .m_axis_tkeep(output_if.tkeep), .m_axis_tvalid(output_if.tvalid),
    .m_axis_tready(output_if.tready), .m_axis_tlast(output_if.tlast),
    .irq(status_if.irq), .busy(status_if.busy), .done(status_if.done),
    .error(status_if.error)
  );

  initial begin
    axi_if.reset_master();
    input_if.reset_source();
    repeat (6) @(posedge aclk);
    aresetn = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual cnn_axi_lite_if)::set(null, "uvm_test_top.env.axi_agent*",
                                                 "vif", axi_if);
    uvm_config_db#(virtual cnn_axis_if)::set(null, "uvm_test_top.env.input_agent*",
                                             "vif", input_if);
    uvm_config_db#(virtual cnn_axis_if)::set(null, "uvm_test_top.env.output_agent*",
                                             "vif", output_if);
    uvm_config_db#(virtual cnn_status_if)::set(null, "uvm_test_top*",
                                               "status_vif", status_if);
    run_test();
  end
endmodule
