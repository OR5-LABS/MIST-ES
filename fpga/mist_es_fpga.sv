// ============================================================================
// mist_es_fpga.sv — Synthesizable FPGA SoC for MIST-ES (RV32IMC).
//
// Self-contained, board-independent SoC for real-hardware bring-up:
//   * Unified distributed-RAM (LUTRAM, async/combinational read) holding code +
//     data + stack, $readmemh-initialised from MEMFILE at synthesis. Distributed
//     RAM keeps the zero-latency read the core expects (block RAM would need the
//     mem_stall path); fine for a demo-sized image, bump MEM_WORDS as needed.
//   * Real synthesizable UART (synthesizable 8-N-1) @ 0x1000_0000.
//   * 8 user LEDs @ 0x2000_1000; tohost @ 0x2000_0000 (sim/bring-up handshake).
//   * Minimal CLINT (msip/mtime/mtimecmp) @ 0x0200_0000 for timer/soft IRQ.
//   * RISC-V Debug Module + JTAG DTM (mist_es_debug) — drive from OpenOCD.
//
// Address map:
//   0x0000_0000.. : RAM (MEM_WORDS words)
//   0x0200_0000   : CLINT
//   0x1000_0000   : UART (16 bytes)
//   0x2000_0000   : tohost
//   0x2000_1000   : LED register (low 8 bits)
// ============================================================================
`include "mist_es_pkg.sv"
`default_nettype none

module mist_es_fpga
  import mist_es_pkg::*;
#(
  parameter int CLK_HZ     = 50_000_000,
  parameter int UART_BAUD  = 115_200,
  parameter int MEM_WORDS  = 32768,         // 128 KB unified RAM (distributed)
  parameter     MEMFILE    = "",            // firmware .mem ($readmemh) for synthesis
  parameter bit SECURE     = 1'b0
)(
  input  wire        clk,
  input  wire        rst,
  // JTAG debug (tie low if unused)
  input  wire        tck,
  input  wire        tms,
  input  wire        tdi,
  output wire        tdo,
  // board I/O
  output reg  [7:0]  leds,
  output wire        serial_tx,
  input  wire        serial_rx,
  // optional bring-up handshake
  output reg  [31:0] tohost,
  output reg         tohost_we
);
  localparam int AW = $clog2(MEM_WORDS);

  // ---- unified program/data RAM (synchronous read, Block RAM) --------------
  (* ram_style = "block" *) reg [31:0] mem [0:MEM_WORDS-1];
  initial if (MEMFILE != "") $readmemh(MEMFILE, mem);

  // ---- core <-> bus --------------------------------------------------------
  wire [31:0] imem_addr, imem_rdata;
  wire [31:0] dmem_addr, dmem_wdata;
  wire        dmem_re, dmem_we;
  wire [3:0]  dmem_be;
  logic [31:0] dmem_rdata;

  // ---- debug module wires --------------------------------------------------
  wire        dbg_haltreq, dbg_resumereq, dbg_halted, ndmreset;
  wire        dbg_ar_valid, dbg_ar_write, dbg_ar_csr, dbg_ar_done;
  wire [11:0] dbg_ar_regno;
  wire [31:0] dbg_ar_wdata, dbg_ar_rdata;
  wire        dm_mem_valid, dm_mem_write;
  wire [31:0] dm_mem_addr, dm_mem_wdata;
  logic [31:0] dm_mem_rdata;
  logic        dm_mem_ready;

  wire core_rst = rst | ndmreset;

  // ---- 1-cycle memory stall logic ------------------------------------------
  wire mem_req;
  reg mem_stall_q;
  always_ff @(posedge clk) begin
    if (core_rst) mem_stall_q <= 1'b0;
    else if (mem_req && !mem_stall_q) mem_stall_q <= 1'b1;
    else mem_stall_q <= 1'b0;
  end
  wire mem_stall = (mem_req && !mem_stall_q);

  // ---- CLINT ---------------------------------------------------------------
  reg  [63:0] mtime, mtimecmp;
  reg         msip;
  wire        irq_timer = (mtime >= mtimecmp);
  wire        irq_soft  = msip;

  mist_es_core #(.SECURE(SECURE)) u_core (
    .clk(clk), .rst(core_rst),
    .imem_addr(imem_addr), .imem_rdata(imem_rdata),
    .dmem_addr(dmem_addr), .dmem_re(dmem_re), .dmem_we(dmem_we),
    .dmem_be(dmem_be), .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
    .irq_timer(irq_timer), .irq_soft(irq_soft), .irq_ext(1'b0),
    .mem_stall(mem_stall), .mem_req(mem_req),
    .retire_valid(), .retire_pc(), .retire_instr(),
    .retire_rd_we(), .retire_rd(), .retire_rd_val(),
    .dbg_haltreq(dbg_haltreq), .dbg_resumereq(dbg_resumereq), .dbg_halted(dbg_halted),
    .dbg_ar_valid(dbg_ar_valid), .dbg_ar_write(dbg_ar_write), .dbg_ar_csr(dbg_ar_csr),
    .dbg_ar_regno(dbg_ar_regno), .dbg_ar_wdata(dbg_ar_wdata),
    .dbg_ar_rdata(dbg_ar_rdata), .dbg_ar_done(dbg_ar_done)
  );

  mist_es_debug u_dbg (
    .clk(clk), .rst(rst), .tck(tck), .tms(tms), .tdi(tdi), .tdo(tdo),
    .dbg_haltreq(dbg_haltreq), .dbg_resumereq(dbg_resumereq),
    .ndmreset(ndmreset), .dbg_halted(dbg_halted),
    .dbg_ar_valid(dbg_ar_valid), .dbg_ar_write(dbg_ar_write), .dbg_ar_csr(dbg_ar_csr),
    .dbg_ar_regno(dbg_ar_regno), .dbg_ar_wdata(dbg_ar_wdata),
    .dbg_ar_rdata(dbg_ar_rdata), .dbg_ar_done(dbg_ar_done),
    .dm_mem_valid(dm_mem_valid), .dm_mem_write(dm_mem_write),
    .dm_mem_addr(dm_mem_addr), .dm_mem_wdata(dm_mem_wdata),
    .dm_mem_rdata(dm_mem_rdata), .dm_mem_ready(dm_mem_ready)
  );

  // ---- instruction fetch (synchronous read) --------------------------------
  reg [31:0] imem_rdata_q;
  always_ff @(posedge clk) begin
    imem_rdata_q <= mem[imem_addr[AW+1:2]];
    if (1'b0) begin
      mem[imem_addr[AW+1:2]][ 7: 0] <= 8'h0;
      mem[imem_addr[AW+1:2]][15: 8] <= 8'h0;
      mem[imem_addr[AW+1:2]][23:16] <= 8'h0;
      mem[imem_addr[AW+1:2]][31:24] <= 8'h0;
    end
  end
  assign imem_rdata = imem_rdata_q;

  // ---- data-bus decode -----------------------------------------------------
  wire in_ram    = (dmem_addr < MEM_WORDS*4);
  wire uart_sel  = (dmem_addr[31:16] == 16'h1000);
  wire clint_sel = (dmem_addr[31:16] == 16'h0200);
  wire led_sel   = (dmem_addr == 32'h2000_1000);
  wire tohost_sel= (dmem_addr == 32'h2000_0000);
  wire [AW-1:0] didx = dmem_addr[AW+1:2];

  // ---- UART ----------------------------------------------------------------
  wire [7:0] uart_rdata; wire uart_tx_irq, uart_rx_irq;
  mist_es_uart #(.CLK_HZ(CLK_HZ), .BAUD(UART_BAUD)) u_uart (
    .clk(clk), .rst(rst), .addr(dmem_addr[3:0]), .wdata(dmem_wdata[7:0]),
    .we(dmem_we && uart_sel), .re(dmem_re && uart_sel), .rdata(uart_rdata),
    .serial_tx(serial_tx), .serial_rx(serial_rx),
    .tx_irq(uart_tx_irq), .rx_irq(uart_rx_irq)
  );

  // ---- CLINT read words ----------------------------------------------------
  wire [31:0] clint_rdata =
        (dmem_addr[15:0]==16'h0000) ? {31'b0, msip}     :
        (dmem_addr[15:0]==16'h4000) ? mtimecmp[31:0]    :
        (dmem_addr[15:0]==16'h4004) ? mtimecmp[63:32]   :
        (dmem_addr[15:0]==16'hBFF8) ? mtime[31:0]       :
        (dmem_addr[15:0]==16'hBFFC) ? mtime[63:32]      : 32'h0;

  // ---- BRAM Port B (CPU Data + Debug Module) -------------------------------
  wire [AW-1:0] portB_addr  = dm_mem_valid ? dm_mem_addr[AW+1:2] : didx;
  wire          portB_we    = (dm_mem_valid && dm_mem_write && (dm_mem_addr < MEM_WORDS*4)) || (dmem_we && in_ram);
  wire [3:0]    portB_be    = dm_mem_valid ? 4'b1111 : dmem_be;
  wire [31:0]   portB_wdata = dm_mem_valid ? dm_mem_wdata : dmem_wdata;
  
  wire [3:0]    we          = {4{portB_we}} & portB_be;
  
  reg [31:0] portB_rdata_q;
  always_ff @(posedge clk) begin
    portB_rdata_q <= mem[portB_addr];
    if (we[0]) mem[portB_addr][ 7: 0] <= portB_wdata[ 7: 0];
    if (we[1]) mem[portB_addr][15: 8] <= portB_wdata[15: 8];
    if (we[2]) mem[portB_addr][23:16] <= portB_wdata[23:16];
    if (we[3]) mem[portB_addr][31:24] <= portB_wdata[31:24];
  end

  // ---- data read mux (synchronous RAM read) --------------------------------
  always_comb begin
    if      (uart_sel)  dmem_rdata = {24'h0, uart_rdata};
    else if (clint_sel) dmem_rdata = clint_rdata;
    else if (in_ram)    dmem_rdata = portB_rdata_q;
    else                dmem_rdata = 32'h0;
  end

  // ---- writes (core data port) + CLINT/LED/tohost --------------------------
  always_ff @(posedge clk) begin
    tohost_we <= 1'b0;
    if (rst) begin
      mtime <= 64'd0; mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF; msip <= 1'b0; leds <= 8'h0;
    end else begin
      mtime <= mtime + 64'd1;

      // CLINT / LED / tohost writes
      if (dmem_we) begin
        if (!in_ram) begin
          if (clint_sel) begin
            if (dmem_addr[15:0]==16'h0000) msip           <= dmem_wdata[0];
            if (dmem_addr[15:0]==16'h4000) mtimecmp[31:0] <= dmem_wdata;
            if (dmem_addr[15:0]==16'h4004) mtimecmp[63:32]<= dmem_wdata;
          end else if (led_sel)   leds <= dmem_wdata[7:0];
          else if (tohost_sel) begin tohost <= dmem_wdata; tohost_we <= 1'b1; end
        end
      end
    end
  end

  // ---- Debug-Module System-Bus read path (1-cycle) -------------------------
  assign dm_mem_rdata = portB_rdata_q;
  always_ff @(posedge clk) begin
    dm_mem_ready <= 1'b0;
    if (dm_mem_valid) dm_mem_ready <= 1'b1;
  end
endmodule

`default_nettype wire
