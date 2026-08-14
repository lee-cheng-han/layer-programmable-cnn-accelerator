interface cnn_reset_if(input logic aclk);
  logic aresetn;

  task automatic assert_reset(int unsigned cycles = 4);
    @(negedge aclk);
    aresetn <= 1'b0;
    repeat (cycles) @(posedge aclk);
    @(negedge aclk);
    aresetn <= 1'b1;
  endtask
endinterface
