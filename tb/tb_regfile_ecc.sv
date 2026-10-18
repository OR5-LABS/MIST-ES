// tb_regfile_ecc.sv — unit test for mist_es_regfile_ecc (SECDED).
//   * write a known value, inject a SINGLE-bit storage flip -> read is CORRECTED
//     and ecc_cerr pulses.
//   * inject a DOUBLE-bit flip -> ecc_uerr (uncorrectable) is detected.
`timescale 1ns/1ps
module tb_regfile_ecc;
  logic clk = 0; always #5 clk = ~clk;
  logic [4:0] ra1, ra2, wa;
  logic [31:0] rd1, rd2, wd;
  logic we, cerr, uerr;

  mist_es_regfile_ecc #(.WRITE_FIRST(0)) dut (
    .clk(clk), .ra1(ra1), .ra2(ra2), .rd1(rd1), .rd2(rd2),
    .we(we), .wa(wa), .wd(wd), .ecc_cerr(cerr), .ecc_uerr(uerr));

  integer errors = 0;
  reg [38:0] tmp;
  task chk(input [255:0] n, input v, input e);
    begin if (v!==e) begin $display("FAIL %0s got=%b exp=%b",n,v,e); errors++; end
          else $display("ok   %0s = %b", n, v); end
  endtask

  initial begin
    ra1=0; ra2=0; wa=0; wd=0; we=0;
    @(posedge clk);
    // write x5 = 0xDEADBEEF
    wa=5; wd=32'hDEAD_BEEF; we=1; @(posedge clk); we=0;
    ra1=5; #1;
    chk("clean read", rd1===32'hDEAD_BEEF, 1'b1);
    chk("clean cerr", cerr, 1'b0);

    // inject ONE stored bit flip in x5's data field -> must be corrected
    tmp = dut.regs[5]; tmp[3] = ~tmp[3]; dut.regs[5] = tmp; #1;
    chk("SEC corrected data",    rd1===32'hDEAD_BEEF, 1'b1);
    chk("SEC cerr pulse",        cerr, 1'b1);
    chk("SEC not uncorrectable", uerr, 1'b0);

    // inject a SECOND flip (now 2 bits corrupt) -> uncorrectable, DETECTED
    tmp = dut.regs[5]; tmp[10] = ~tmp[10]; dut.regs[5] = tmp; #1;
    chk("DED detected", uerr, 1'b1);

    // repair both, back to clean
    tmp = dut.regs[5]; tmp[3] = ~tmp[3]; tmp[10] = ~tmp[10]; dut.regs[5] = tmp; #1;
    chk("post clean read", rd1===32'hDEAD_BEEF, 1'b1);
    chk("post clean uerr", uerr, 1'b0);

    if (errors==0) $display("ECC: PASS"); else $display("ECC: FAIL (%0d)", errors);
    $finish;
  end
endmodule
