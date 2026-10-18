// ============================================================================
// mist_es_muldiv.sv — RV32M multiply/divide unit (multi-cycle).
//
//   * MUL family : 1-cycle latched 64-bit product (picks hi/lo, signedness).
//   * DIV family : iterative shift-subtract over magnitudes (32 steps) plus a
//                  sign-fixup cycle. Implements RISC-V div-by-zero/overflow.
//
// Handshake: pulse `start` for one cycle with op/a/b valid. `busy` stays high
// while computing; `done` pulses for one cycle when `result` is valid.
// ============================================================================
`include "mist_es_pkg.sv"

module mist_es_muldiv
  import mist_es_pkg::*;
(
  input  logic              clk,
  input  logic              rst,
  input  logic              start,
  input  md_op_e            op,
  input  logic [XLEN-1:0]   a,
  input  logic [XLEN-1:0]   b,
  output logic              busy,
  output logic              done,
  output logic [XLEN-1:0]   result
);
  localparam logic [1:0] S_IDLE = 2'd0;
  localparam logic [1:0] S_MUL  = 2'd1;
  localparam logic [1:0] S_DIV  = 2'd2;
  localparam logic [1:0] S_FIN  = 2'd3;
  logic [1:0] state;


  md_op_e          op_q;
  logic [XLEN-1:0] a_q, b_q;

  // ---- multiply: combinational 64-bit product on latched operands ----------
  // We use exactly 33 bits for the multiplier operands. A 33x33 signed multiply 
  // maps directly to 4 DSP48E1 slices, reducing DSP usage from 12 to 4 and vastly
  // improving Fmax.
  logic is_signed_a, is_signed_b;
  always_comb begin
    unique case (op_q)
      MD_MUL, MD_MULH : begin is_signed_a = 1'b1; is_signed_b = 1'b1; end
      MD_MULHSU       : begin is_signed_a = 1'b1; is_signed_b = 1'b0; end
      default         : begin is_signed_a = 1'b0; is_signed_b = 1'b0; end
    endcase
  end
  
  wire signed [32:0] a_ext = {is_signed_a ? a_q[31] : 1'b0, a_q};
  wire signed [32:0] b_ext = {is_signed_b ? b_q[31] : 1'b0, b_q};
  
  // 66-bit signed product (upper 2 bits are safely ignored)
  wire signed [65:0] prod_full = a_ext * b_ext;
  wire [63:0] prod = prod_full[63:0];
  // hoisted const part-selects (iverilog 12 needs these in continuous assigns)
  wire [31:0] prod_lo = prod[31:0];
  wire [31:0] prod_hi = prod[63:32];

  // ---- division working state ----------------------------------------------
  logic [4:0]      bit_idx;       // current dividend bit (31 .. 0)
  logic [XLEN-1:0] dividend_mag;  // |dividend|
  logic [XLEN-1:0] divisor_mag;   // |divisor|
  logic [XLEN-1:0] quotient_q;
  logic [XLEN:0]   rem_q;         // 33-bit running remainder
  logic            neg_quot, neg_rem;
  logic            div_by_zero, div_overflow;
  logic [XLEN-1:0] dividend_raw;

  wire  [31:0]     rem_lo = rem_q[XLEN-1:0];
  wire  [XLEN:0]   rem_shifted = {rem_lo, dividend_mag[bit_idx]};

  assign busy = (state != S_IDLE);

  always_ff @(posedge clk) begin
    if (rst) begin
      state  <= S_IDLE;
      done   <= 1'b0;
      result <= '0;
    end else begin
      done <= 1'b0;
      case (state)
        // ---------------------------------------------------------------
        S_IDLE: if (start) begin
          op_q <= op;
          a_q  <= a;
          b_q  <= b;
          if ((op == MD_MUL) || (op == MD_MULH) ||
              (op == MD_MULHSU) || (op == MD_MULHU)) begin
            state <= S_MUL;
          end else begin
            div_by_zero  <= (b == 32'd0);
            div_overflow <= ((op == MD_DIV || op == MD_REM) &&
                             (a == 32'h8000_0000) && (b == 32'hFFFF_FFFF));
            dividend_raw <= a;
            dividend_mag <= ((op==MD_DIV || op==MD_REM) && a[31]) ? (~a + 1'b1) : a;
            divisor_mag  <= ((op==MD_DIV || op==MD_REM) && b[31]) ? (~b + 1'b1) : b;
            quotient_q   <= '0;
            rem_q        <= '0;
            neg_quot     <= (op==MD_DIV) && (a[31] ^ b[31]);
            neg_rem      <= (op==MD_REM) && a[31];
            bit_idx      <= 5'd31;
            state        <= S_DIV;
          end
        end
        // ---------------------------------------------------------------
        S_MUL: begin
          result <= (op_q == MD_MUL) ? prod_lo : prod_hi;
          done   <= 1'b1;
          state  <= S_IDLE;
        end
        // ---------------------------------------------------------------
        S_DIV: begin
          if (div_by_zero) begin
            result <= (op_q == MD_DIV)  ? 32'hFFFF_FFFF :
                      (op_q == MD_DIVU) ? 32'hFFFF_FFFF : dividend_raw;
            done   <= 1'b1;
            state  <= S_IDLE;
          end else if (div_overflow) begin
            result <= (op_q == MD_DIV) ? 32'h8000_0000 : 32'd0;
            done   <= 1'b1;
            state  <= S_IDLE;
          end else begin
            if (rem_shifted >= {1'b0, divisor_mag}) begin
              rem_q      <= rem_shifted - {1'b0, divisor_mag};
              quotient_q <= (quotient_q << 1) | 32'd1;
            end else begin
              rem_q      <= rem_shifted;
              quotient_q <= (quotient_q << 1);
            end
            if (bit_idx == 5'd0) state   <= S_FIN;
            else                 bit_idx <= bit_idx - 1'b1;
          end
        end
        // ---------------------------------------------------------------
        S_FIN: begin
          unique case (op_q)
            MD_DIV  : result <= neg_quot ? (~quotient_q + 1'b1) : quotient_q;
            MD_DIVU : result <= quotient_q;
            MD_REM  : result <= neg_rem  ? (~rem_lo + 1'b1) : rem_lo;
            default : result <= rem_lo;        // REMU
          endcase
          done  <= 1'b1;
          state <= S_IDLE;
        end
        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
