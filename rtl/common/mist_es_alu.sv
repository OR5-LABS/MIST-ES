// ============================================================================
// mist_es_alu.sv — Combinational RV32I ALU.
// ============================================================================
`include "mist_es_pkg.sv"

module mist_es_alu
  import mist_es_pkg::*;
(
  input  alu_op_e          op,
  input  logic [XLEN-1:0]  a,
  input  logic [XLEN-1:0]  b,
  output logic [XLEN-1:0]  y
);
  logic [4:0] shamt;
  assign shamt = b[4:0];

  always_comb begin
    unique case (op)
      ALU_ADD:    y = a + b;
      ALU_SUB:    y = a - b;
      ALU_SLL:    y = a << shamt;
      ALU_SLT:    y = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
      ALU_SLTU:   y = (a < b)                   ? 32'd1 : 32'd0;
      ALU_XOR:    y = a ^ b;
      ALU_SRL:    y = a >> shamt;
      ALU_SRA:    y = $unsigned($signed(a) >>> shamt);
      ALU_OR:     y = a | b;
      ALU_AND:    y = a & b;
      ALU_PASS_B: y = b;
      default:    y = '0;
    endcase
  end
endmodule
