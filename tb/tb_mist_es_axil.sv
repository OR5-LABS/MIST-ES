// tb_mist_es_axil.sv — run the smoke through a real AXI4-Lite master<->slave link.
`timescale 1ns/1ps
module tb_mist_es_axil;
  logic clk=1'b0; always #5 clk=~clk;
  logic rst; logic [31:0] tohost; logic tohost_we;

  mist_es_axil_soc dut (.clk(clk), .rst(rst), .tohost(tohost), .tohost_we(tohost_we));

  string hexf; integer i, cyc=0;
  initial begin
    if (!$value$plusargs("IMEM=%s", hexf)) begin $display("no IMEM"); $finish; end
    for (i=0;i<8192;i=i+1) begin dut.u_s.imem[i]=32'h13; dut.u_s.dram[i]=0; end
    $readmemh(hexf, dut.u_s.imem);
    rst=1; repeat(4) @(posedge clk); rst=0;
    $display("[TB] running smoke over AXI4-Lite");
  end

  always @(posedge clk) begin
    if (!rst) cyc <= cyc + 1;
    if (tohost_we) begin
      $display("[TB] tohost=0x%08x at cycle %0d", tohost, cyc);
      if (tohost==32'd1) $display("[TB] PASS (AXI4-Lite)"); else $display("[TB] FAIL");
      $finish;
    end
    if (cyc > 500000) begin $display("[TB] TIMEOUT"); $finish; end
  end
endmodule
