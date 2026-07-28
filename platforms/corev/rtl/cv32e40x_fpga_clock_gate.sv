module cv32e40x_clock_gate #(
  parameter LIB = 0
) (
  input  logic clk_i,
  input  logic en_i,
  input  logic scan_cg_en_i,
  output logic clk_o
);
  logic unused_enable;

  assign unused_enable = en_i | scan_cg_en_i;
  assign clk_o = clk_i;
endmodule
