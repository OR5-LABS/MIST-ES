// ============================================================================
// mist_es_branch.sv — conditional-branch comparator (shared leaf cell).
// Given a decoded branch op and the two (already-forwarded) operands, decides
// whether the branch is taken. Purely combinational.
// ============================================================================
`include "mist_es_pkg.sv"

module mist_es_branch
  import mist_es_pkg::*;
(
  input  br_op_e          br_op,
  input  logic [XLEN-1:0] a,
  input  logic [XLEN-1:0] b,
  output logic            taken
);
  always_comb unique case (br_op)
    BR_EQ : taken = (a == b);
    BR_NE : taken = (a != b);
    BR_LT : taken = ($signed(a) <  $signed(b));
    BR_GE : taken = ($signed(a) >= $signed(b));
    BR_LTU: taken = (a <  b);
    BR_GEU: taken = (a >= b);
    default: taken = 1'b0;
  endcase
endmodule
