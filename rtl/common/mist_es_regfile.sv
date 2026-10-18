// ============================================================================
// mist_es_regfile.sv — 32x32 register file. x0 hard-wired to zero.
// Two async read ports, one sync write port. Write-first transparency is
// handled by forwarding in the core, not here.
// ============================================================================
`include "mist_es_pkg.sv"

module mist_es_regfile
  import mist_es_pkg::*;
#(
  // 1 = WB->ID transparency (needed by the pipelined cores). Multi-cycle cores
  // must set this 0: their write data is combinational, so transparency would
  // form a read->write->ALU->read combinational loop.
  parameter bit WRITE_FIRST = 1
)(
  input  logic              clk,
  input  logic [4:0]        ra1,
  input  logic [4:0]        ra2,
  output logic [XLEN-1:0]   rd1,
  output logic [XLEN-1:0]   rd2,
  input  logic              we,
  input  logic [4:0]        wa,
  input  logic [XLEN-1:0]   wd
);
  logic [XLEN-1:0] regs [1:31];

  // Deterministic power-up state: zero the architectural registers. Real
  // software (crt0/GCC prologues) may save/restore callee-saved registers
  // before first writing them; an X power-up would propagate. FPGA BRAM-based
  // register files initialise to 0 as well, so this matches hardware.
  integer ri;
  initial for (ri = 1; ri < 32; ri = ri + 1) regs[ri] = '0;

  // Write-first transparency: a register written in WB this cycle is visible
  // to an ID read in the same cycle (covers producer->consumer distances that
  // outrun the EX forwarding network).
  wire fwd1 = WRITE_FIRST && we && (wa != 5'd0) && (wa == ra1);
  wire fwd2 = WRITE_FIRST && we && (wa != 5'd0) && (wa == ra2);

  assign rd1 = (ra1 == 5'd0) ? '0 : fwd1 ? wd : regs[ra1];
  assign rd2 = (ra2 == 5'd0) ? '0 : fwd2 ? wd : regs[ra2];

  always_ff @(posedge clk) begin
    if (we && (wa != 5'd0))
      regs[wa] <= wd;
  end
endmodule
