// ============================================================================
// mist_es_csr.sv — Machine-mode CSR file with trap/MRET support.
//
// Single read port (combinational) + single write port (CSR instructions),
// plus a trap interface used by the EX stage. Implements the minimal M-mode
// register set needed to take ECALL/EBREAK/illegal traps and return via MRET.
// ============================================================================
`include "mist_es_pkg.sv"

module mist_es_csr
  import mist_es_pkg::*;
#(
  // misa value advertised by this core. Default RV32IM; each core overrides to
  // reflect its true extensions (C, F, X-vector, ...). base=01 (32-bit) in
  // bits[31:30]; extension bit = (letter - 'A'): I=8, M=12, C=2, F=5, X=23.
  parameter logic [XLEN-1:0] MISA_VAL =
      (32'b01 << 30) | (1 << 8) /*I*/ | (1 << 12) /*M*/,
  // Security options (default OFF -> M-mode-only cores are byte-identical):
  parameter bit U_MODE      = 1'b0,   // add User privilege mode + misa[U]
  parameter int PMP_REGIONS = 0       // number of PMP regions (0 = no PMP)
)(
  input  logic              clk,
  input  logic              rst,

  // CSR instruction read/write (EX stage)
  input  logic [11:0]       csr_addr,
  output logic [XLEN-1:0]   csr_rdata,
  input  logic              csr_we,
  input  logic [XLEN-1:0]   csr_wdata,

  // ---- privilege + PMP (only meaningful when U_MODE / PMP_REGIONS set) ------
  output logic [1:0]        priv_o,      // current privilege (11=M, 00=U)
  output logic              fetch_m_o,   // instruction-fetch priv is M
  output logic              data_m_o,    // data-access priv is M (honours MPRV)
  output logic              mmwp_o,      // mseccfg.MMWP (Smepmp M-mode whitelist)
  output logic              mml_o,       // mseccfg.MML  (Smepmp machine mode lockdown)
  output logic [127:0]      pmpcfg_o,    // 16 pmpNcfg bytes
  output logic [511:0]      pmpaddr_o,   // 16 pmpaddrN words

  // Trap interface (EX stage)
  input  logic              trap_set,
  input  logic [3:0]        trap_cause,
  input  logic              trap_interrupt,   // 1 => mcause interrupt bit set
  input  logic [XLEN-1:0]   trap_epc,
  input  logic [XLEN-1:0]   trap_tval,
  input  logic              mret,
  input  logic              retire,     // an instruction committed this cycle

  // Interrupt pending lines (tie 0 if unused). Standard M-mode interrupts.
  input  logic              irq_timer,  // MTIP
  input  logic              irq_soft,   // MSIP
  input  logic              irq_ext,    // MEIP

  output logic [XLEN-1:0]   mtvec_o,
  output logic [XLEN-1:0]   mepc_o,
  output logic              irq_req,    // an enabled interrupt is pending+taken
  output logic [3:0]        irq_cause   // its cause code (11 ext / 7 timer / 3 soft)
);
  // Architectural registers
  logic [XLEN-1:0] mstatus;
  logic [XLEN-1:0] mtvec;
  logic [XLEN-1:0] mepc;
  logic [XLEN-1:0] mcause;
  logic [XLEN-1:0] mscratch;
  logic [XLEN-1:0] mtval;
  logic [XLEN-1:0] mie;
  logic [63:0]     mcycle;
  logic [63:0]     minstret;

  // ---- privilege + PMP state (active only when U_MODE / PMP_REGIONS set) ----
  logic [1:0]      priv;            // current privilege: 11=M, 00=U
  logic [127:0]    pmpcfg_r;        // 16 pmpNcfg bytes
  logic [511:0]    pmpaddr_r;       // 16 pmpaddrN words
  logic [2:0]      mseccfg;         // ePMP: {RLB[2], MMWP[1], MML[0]}
  integer          jb;              // pmpcfg byte loop index
  wire             rlb = mseccfg[2];

  // mstatus bit positions we model
  localparam int MIE_BIT  = 3;
  localparam int MPIE_BIT = 7;
  // MPP = bits [12:11]; MPRV = bit 17

  assign mtvec_o = mtvec;
  assign mepc_o  = mepc;

  // misa advertises U when User mode is configured (letter 'U' -> bit 20)
  wire [31:0] misa_eff = MISA_VAL | (U_MODE ? (32'd1 << 20) : 32'd0);

  assign priv_o    = priv;
  assign fetch_m_o = (priv == 2'b11);
  assign data_m_o  = (U_MODE && mstatus[17]) ? (mstatus[12:11]==2'b11) : (priv==2'b11);
  assign mmwp_o    = mseccfg[1];
  assign mml_o     = mseccfg[0];
  // Smepmp: with MML=1 and RLB=0, a pmpcfg write may not create a new executable
  // M-mode-only rule or a locked shared-code rule; such a write is ignored.
  function automatic logic mml_blocked(input logic [7:0] c);
    mml_blocked = c[7] && ((c[2] && !c[1]) || (!c[0] && c[1]));
  endfunction
  // Smepmp: RLB cannot be set while RLB=0 and any rule is locked.
  logic any_locked;
  always_comb begin
    any_locked = 1'b0;
    for (int k = 0; k < PMP_REGIONS; k++) any_locked |= pmpcfg_r[k*8 + 7];
  end
  assign pmpcfg_o  = pmpcfg_r;
  assign pmpaddr_o = pmpaddr_r;

  wire is_pmpaddr = (csr_addr[11:4] == 8'h3B);                 // 0x3B0..0x3BF
  wire is_pmpcfg  = (csr_addr[11:2] == 10'h0E8);               // 0x3A0..0x3A3

  // misa is supplied by the MISA_VAL parameter (per-core true ISA advertisement).

  // hoisted const part-selects (must be continuous assigns under iverilog 12)
  wire [31:0] mcycle_lo   = mcycle[31:0];
  wire [31:0] mcycle_hi   = mcycle[63:32];
  wire [31:0] minstret_lo = minstret[31:0];
  wire [31:0] minstret_hi = minstret[63:32];

  // mstatus is WARL: only MIE, MPIE, MPP (and MPRV with U-mode) exist; all
  // other bits read 0. MPP holds only implemented modes: M alone without
  // U-mode, M or U with it (a write of an unsupported mode keeps the old MPP).
  function automatic logic [XLEN-1:0] mstatus_wr(input logic [XLEN-1:0] v,
                                                 input logic [XLEN-1:0] old);
    mstatus_wr = '0;
    mstatus_wr[MIE_BIT]  = v[MIE_BIT];
    mstatus_wr[MPIE_BIT] = v[MPIE_BIT];
    if (!U_MODE) mstatus_wr[12:11] = 2'b11;
    else begin
      mstatus_wr[12:11] = (v[12:11] == 2'b00 || v[12:11] == 2'b11) ? v[12:11] : old[12:11];
      mstatus_wr[17]    = v[17];
    end
  endfunction

  // ---- interrupts ----------------------------------------------------------
  // mip is read-only here, driven by the pending lines (MEIP/MTIP/MSIP).
  wire [31:0] mip = (irq_ext   << 11) | (irq_timer << 7) | (irq_soft << 3);
  wire        glob_ie = mstatus[MIE_BIT];
  // priority: external > timer > software
  assign irq_req   = glob_ie & ( (mip[11] & mie[11]) | (mip[7] & mie[7]) | (mip[3] & mie[3]) );
  assign irq_cause = (mip[11] & mie[11]) ? 4'd11 :
                     (mip[7]  & mie[7])  ? 4'd7  : 4'd3;

  // ---- read ----------------------------------------------------------------
  always_comb begin
    if (PMP_REGIONS > 0 && is_pmpaddr)
      csr_rdata = pmpaddr_r[csr_addr[3:0]*32 +: 32];
    else if (PMP_REGIONS > 0 && is_pmpcfg)
      csr_rdata = pmpcfg_r[csr_addr[1:0]*32 +: 32];
    else if (PMP_REGIONS > 0 && csr_addr == 12'h747)   // mseccfg
      csr_rdata = {29'b0, mseccfg};
    else unique case (csr_addr)
      CSR_MSTATUS  : csr_rdata = mstatus;
      CSR_MISA     : csr_rdata = misa_eff;
      CSR_MIE      : csr_rdata = mie;
      CSR_MTVEC    : csr_rdata = mtvec;
      CSR_MSCRATCH : csr_rdata = mscratch;
      CSR_MEPC     : csr_rdata = mepc;
      CSR_MCAUSE   : csr_rdata = mcause;
      CSR_MTVAL    : csr_rdata = mtval;
      CSR_MIP      : csr_rdata = mip;
      CSR_MCYCLE   : csr_rdata = mcycle_lo;
      CSR_MCYCLEH  : csr_rdata = mcycle_hi;
      CSR_MINSTRET : csr_rdata = minstret_lo;
      CSR_MINSTRETH: csr_rdata = minstret_hi;
      12'hC00      : csr_rdata = mcycle_lo;    // cycle   (user-mode alias)
      12'hC80      : csr_rdata = mcycle_hi;    // cycleh  (user-mode alias)
      12'hC02      : csr_rdata = minstret_lo;  // instret (user-mode alias)
      12'hC82      : csr_rdata = minstret_hi;  // instreth (user-mode alias)
      CSR_MVENDORID: csr_rdata = '0;
      CSR_MARCHID  : csr_rdata = 32'h41535452;   // "ASTR"
      CSR_MHARTID  : csr_rdata = '0;
      default      : csr_rdata = '0;
    endcase
  end

  // ---- write / trap / counters --------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      mstatus  <= U_MODE ? '0 : (32'b11 << 11);   // MPP reads M without U-mode
      mtvec    <= '0;
      mepc     <= '0;
      mcause   <= '0;
      mscratch <= '0;
      mtval    <= '0;
      mie      <= '0;
      mcycle   <= '0;
      minstret <= '0;
      priv      <= 2'b11;                      // start in M-mode
      pmpcfg_r  <= '0;
      pmpaddr_r <= '0;
      mseccfg   <= 3'b0;
    end else begin
      mcycle <= mcycle + 1'b1;
      if (retire) minstret <= minstret + 1'b1;

      if (trap_set) begin
        // Enter trap: save context+priv, disable interrupts, vector to mtvec.
        mepc            <= trap_epc;
        mcause          <= {trap_interrupt, 27'd0, trap_cause};
        mtval           <= trap_tval;
        mstatus[MPIE_BIT] <= mstatus[MIE_BIT];
        mstatus[MIE_BIT]  <= 1'b0;
        mstatus[12:11]    <= U_MODE ? priv : 2'b11;   // MPP = interrupted priv
        if (U_MODE) priv  <= 2'b11;                    // traps run in M
      end else if (mret) begin
        mstatus[MIE_BIT]  <= mstatus[MPIE_BIT];
        mstatus[MPIE_BIT] <= 1'b1;
        if (U_MODE) begin
          priv           <= mstatus[12:11];            // restore interrupted priv
          mstatus[12:11] <= 2'b00;                      // MPP = U (least privilege)
          if (mstatus[12:11] != 2'b11) mstatus[17] <= 1'b0;  // MRET to <M clears MPRV
        end else mstatus[12:11] <= 2'b11;
      end else if (csr_we) begin
        if (PMP_REGIONS > 0 && is_pmpaddr) begin
          // a locked entry is immutable unless mseccfg.RLB (ePMP)
          if (!pmpcfg_r[csr_addr[3:0]*8 + 7] || rlb)
            pmpaddr_r[csr_addr[3:0]*32 +: 32] <= csr_wdata;
        end
        else if (PMP_REGIONS > 0 && is_pmpcfg) begin
          for (jb = 0; jb < 4; jb = jb + 1)
            if ((!pmpcfg_r[(csr_addr[1:0]*4 + jb)*8 + 7] || rlb) &&   // per-entry lock
                !(mseccfg[0] && !rlb && mml_blocked(csr_wdata[jb*8 +: 8])))
              pmpcfg_r[(csr_addr[1:0]*4 + jb)*8 +: 8] <= csr_wdata[jb*8 +: 8];
        end
        else if (PMP_REGIONS > 0 && csr_addr == 12'h747) begin    // mseccfg
          mseccfg[0] <= mseccfg[0] | csr_wdata[0];   // MML  sticky
          mseccfg[1] <= mseccfg[1] | csr_wdata[1];   // MMWP sticky
          if (rlb || !any_locked)                     // RLB (Smepmp lock rule)
            mseccfg[2] <= csr_wdata[2];
        end
        else unique case (csr_addr)
          CSR_MSTATUS  : mstatus  <= mstatus_wr(csr_wdata, mstatus);
          CSR_MIE      : mie      <= csr_wdata;
          CSR_MTVEC    : mtvec    <= csr_wdata;
          CSR_MSCRATCH : mscratch <= csr_wdata;
          CSR_MEPC     : mepc     <= csr_wdata;
          CSR_MCAUSE   : mcause   <= csr_wdata;
          CSR_MTVAL    : mtval    <= csr_wdata;
          // minstret is writable; the write replaces this instruction's increment
          CSR_MINSTRET : minstret <= {minstret_hi, csr_wdata};
          CSR_MINSTRETH: minstret <= {csr_wdata, minstret_lo};
          default      : /* read-only or unimplemented: ignore */ ;
        endcase
      end
    end
  end
endmodule
