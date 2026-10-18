// ============================================================================
// mist_es_immgen.sv — RISC-V immediate generator (shared leaf cell).
// Extracts the five immediate formats from a 32-bit instruction. Purely
// combinational; sign-extension logic lives in exactly one place.
// ============================================================================
`include "mist_es_pkg.sv"

module mist_es_immgen
  import mist_es_pkg::*;
(
  input  logic [31:0] instr,
  output logic [XLEN-1:0] imm_i,   // I-type  (loads, OP-IMM, JALR)
  output logic [XLEN-1:0] imm_s,   // S-type  (stores)
  output logic [XLEN-1:0] imm_b,   // B-type  (branches)
  output logic [XLEN-1:0] imm_u,   // U-type  (LUI, AUIPC)
  output logic [XLEN-1:0] imm_j    // J-type  (JAL)
);
  assign imm_i = {{20{instr[31]}}, instr[31:20]};
  assign imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
  assign imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
  assign imm_u = {instr[31:12], 12'b0};
  assign imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
endmodule
