interface cnn_axis_if(input logic aclk);
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
endinterface
