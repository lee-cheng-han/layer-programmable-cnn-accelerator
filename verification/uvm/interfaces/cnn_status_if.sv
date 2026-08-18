interface cnn_status_if(input logic aclk);
  logic aresetn;
  logic irq;
  logic busy;
  logic done;
  logic error;

  a_status_known: assert property (@(posedge aclk)
    disable iff (!aresetn)
    !$isunknown({irq, busy, done, error}));

  a_reset_quiescent: assert property (@(posedge aclk)
    !aresetn |=> !irq && !busy && !done && !error);

  covergroup status_cg @(posedge aclk);
    option.per_instance = 1;
    busy_cp: coverpoint busy iff (aresetn) { bins observed = {1}; }
    done_cp: coverpoint done iff (aresetn) { bins observed = {1}; }
    error_cp: coverpoint error iff (aresetn) { bins observed = {1}; }
    irq_cp: coverpoint irq iff (aresetn) { bins observed = {1}; }
  endgroup
  status_cg status_coverage = new;
endinterface
