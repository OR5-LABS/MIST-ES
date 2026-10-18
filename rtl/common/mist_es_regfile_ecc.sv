// ============================================================================
// mist_es_regfile_ecc.sv — 32x32 register file with SECDED ECC on the storage.
//
// Drop-in for mist_es_regfile (same read/write ports) that protects every GPR
// with a SECDED(39,32) Hamming code: single-bit storage errors are CORRECTED on
// read, double-bit errors are DETECTED (flagged uncorrectable). This provides
// register-file ECC hardening as a fault countermeasure.
//
//   ecc_cerr : a single-bit error was corrected on a read this cycle
//   ecc_uerr : a double-bit (uncorrectable) error was detected on a read
//
// 6 Hamming check bits (distinct nonzero, non-power-of-2 column codes per data
// bit) + 1 overall parity = 7 ECC bits per 32-bit word.
// ============================================================================
`include "mist_es_pkg.sv"

module mist_es_regfile_ecc
  import mist_es_pkg::*;
#(
  parameter bit WRITE_FIRST = 1
)(
  input  logic              clk,
  input  logic [4:0]        ra1,
  input  logic [4:0]        ra2,
  output logic [XLEN-1:0]   rd1,
  output logic [XLEN-1:0]   rd2,
  input  logic              we,
  input  logic [4:0]        wa,
  input  logic [XLEN-1:0]   wd,
  output logic              ecc_cerr,   // single-bit error corrected (this read)
  output logic              ecc_uerr    // double-bit error detected (uncorrectable)
);
  // per-data-bit Hamming column codes: 32 distinct nonzero non-power-of-2 6-bit values
  function automatic logic [5:0] hcol(input integer j);
    case (j)
      0:hcol=6'd3;  1:hcol=6'd5;  2:hcol=6'd6;  3:hcol=6'd7;  4:hcol=6'd9;
      5:hcol=6'd10; 6:hcol=6'd11; 7:hcol=6'd12; 8:hcol=6'd13; 9:hcol=6'd14;
      10:hcol=6'd15;11:hcol=6'd17;12:hcol=6'd18;13:hcol=6'd19;14:hcol=6'd20;
      15:hcol=6'd21;16:hcol=6'd22;17:hcol=6'd23;18:hcol=6'd24;19:hcol=6'd25;
      20:hcol=6'd26;21:hcol=6'd27;22:hcol=6'd28;23:hcol=6'd29;24:hcol=6'd30;
      25:hcol=6'd31;26:hcol=6'd33;27:hcol=6'd34;28:hcol=6'd35;29:hcol=6'd36;
      30:hcol=6'd37;31:hcol=6'd38; default:hcol=6'd0;
    endcase
  endfunction

  // encode: 6 check bits + 1 overall parity (total codeword parity even)
  function automatic logic [6:0] enc(input logic [31:0] d);
    logic [5:0] c; integer j;
    c = 6'd0;
    for (j = 0; j < 32; j = j + 1) c = c ^ (d[j] ? hcol(j) : 6'd0);
    enc = {(^d) ^ (^c), c};                       // {overall parity, check bits}
  endfunction

  // decode+correct: returns {uerr, cerr, corrected_data[31:0]}
  function automatic logic [33:0] dec(input logic [6:0] e, input logic [31:0] d);
    logic [5:0] c_re, s; logic perr; logic [31:0] dc; integer j;
    c_re = 6'd0;
    for (j = 0; j < 32; j = j + 1) c_re = c_re ^ (d[j] ? hcol(j) : 6'd0);
    s    = e[5:0] ^ c_re;                          // syndrome
    perr = (^e) ^ (^d);                            // total-parity mismatch (odd = single)
    dc   = d;
    for (j = 0; j < 32; j = j + 1)
      if (perr && (s == hcol(j))) dc[j] = ~d[j];   // correct the flipped data bit
    dec = {(~perr & (s != 6'd0)), perr, dc};       // {uncorrectable, corrected, data}
  endfunction

  // storage: {ecc[6:0], data[31:0]}
  logic [38:0] regs [1:31];
  integer ri;
  initial for (ri = 1; ri < 32; ri = ri + 1) regs[ri] = {enc(32'b0), 32'b0};

  wire fwd1 = WRITE_FIRST && we && (wa != 5'd0) && (wa == ra1);
  wire fwd2 = WRITE_FIRST && we && (wa != 5'd0) && (wa == ra2);

  wire [33:0] d1 = dec(regs[ra1][38:32], regs[ra1][31:0]);
  wire [33:0] d2 = dec(regs[ra2][38:32], regs[ra2][31:0]);

  assign rd1 = (ra1 == 5'd0) ? '0 : fwd1 ? wd : d1[31:0];
  assign rd2 = (ra2 == 5'd0) ? '0 : fwd2 ? wd : d2[31:0];
  // report errors on architecturally-visible reads (non-x0, non-forwarded)
  assign ecc_cerr = ((ra1 != 5'd0) && !fwd1 && d1[32]) ||
                    ((ra2 != 5'd0) && !fwd2 && d2[32]);
  assign ecc_uerr = ((ra1 != 5'd0) && !fwd1 && d1[33]) ||
                    ((ra2 != 5'd0) && !fwd2 && d2[33]);

  always_ff @(posedge clk)
    if (we && (wa != 5'd0)) regs[wa] <= {enc(wd), wd};
endmodule
