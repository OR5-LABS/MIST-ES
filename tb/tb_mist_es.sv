// ============================================================================
// tb_mist_es.sv — Self-checking testbench for mist_es_soc.
//
//   vvp sim/tb_mist_es +IMEM=programs/build/smoke.hex
//   vvp sim/tb_mist_es +IMEM=... +TRACE=1   (emit retire trace for co-sim)
//   vvp sim/tb_mist_es +IMEM=... +DRAM=<hex>  (also preload DRAM @0x8000_0000)
//   vvp sim/tb_mist_es +IMEM=... +MAXCYC=<n>  (cycle limit, default 200000)
//   vvp sim/tb_mist_es +IMEM=... +IMEM_WRITABLE
//       testbench memory model only: data stores into the IMEM window also
//       update IMEM (the SoC's IMEM is fetch + read-only data). run_isa.sh uses
//       it because riscv-tests expect one read/write memory (rv32uc/rvc stores
//       into data placed in its own code section).
//
// Exit protocol: a store to tohost (0x2000_0000) ends the run.
//   tohost == 1  -> PASS
//   tohost != 1  -> FAIL
// ============================================================================
`timescale 1ns/1ps

module tb_mist_es;
  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst;

  logic [31:0] tohost;
  logic        tohost_we;
  logic        retire_valid;
  logic [31:0] retire_pc, retire_instr, retire_rd_val;
  logic        retire_rd_we;
  logic [4:0]  retire_rd;

`ifndef IMEM_WORDS
  `define IMEM_WORDS 8192
`endif
`ifndef DRAM_WORDS
  `define DRAM_WORDS 8192
`endif

  mist_es_soc #(
    .IMEM_WORDS(`IMEM_WORDS),
    .DRAM_WORDS(`DRAM_WORDS)
  ) dut (
    .clk(clk), .rst(rst),
    .tck(1'b0), .tms(1'b0), .tdi(1'b0), .tdo(),
    .tohost(tohost), .tohost_we(tohost_we),
    .retire_valid(retire_valid), .retire_pc(retire_pc),
    .retire_instr(retire_instr), .retire_rd_we(retire_rd_we),
    .retire_rd(retire_rd), .retire_rd_val(retire_rd_val)
  );

  string imem_file, dram_file;
  integer trace_en;
  integer max_cyc = 200000;
  integer i;

  initial begin
    if (!$value$plusargs("IMEM=%s", imem_file)) begin
      $display("FATAL: no +IMEM=<file> given");
      $finish;
    end
    trace_en = 0;
    if ($value$plusargs("TRACE=%d", trace_en)) ;
    if ($value$plusargs("MAXCYC=%d", max_cyc)) ;

    // clear memories (small default window to avoid startup lag on large test models)
    for (i = 0; i < 8192; i = i + 1) begin
      dut.imem[i] = 32'h0000_0013;
      dut.dram[i] = 32'h0;
    end

    $display("[TB] Loading IMEM from: %s", imem_file);
    $readmemh(imem_file, dut.imem);
    if ($value$plusargs("DRAM=%s", dram_file)) begin
      $display("[TB] Loading DRAM from: %s", dram_file);
      $readmemh(dram_file, dut.dram);
    end

    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_mist_es.vcd");
      $dumpvars(0, tb_mist_es);
    end

    rst = 1'b1;
    repeat (4) @(posedge clk);
    rst = 1'b0;
    $display("[TB] Reset released");
  end

  // retire trace for co-simulation
  always @(posedge clk) begin
    if (!rst && trace_en && retire_valid) begin
      $display("RETIRE pc=%08x instr=%08x rdwe=%0d rd=%0d rdval=%08x",
               retire_pc, retire_instr, retire_rd_we, retire_rd, retire_rd_val);
    end
  end

  // optional writable IMEM (see header)
  integer imem_wr = 0;
  integer b;
  initial if ($test$plusargs("IMEM_WRITABLE")) imem_wr = 1;
  always @(posedge clk) begin
    if (imem_wr != 0 && !rst && dut.dmem_we && dut.in_imem)
      for (b = 0; b < 4; b = b + 1)
        if (dut.dmem_be[b]) dut.imem[dut.imem_didx][b*8 +: 8] <= dut.dmem_wdata[b*8 +: 8];
  end

  // optional signature dumping for architectural tests
  string sig_file;
  logic [31:0] sig_begin, sig_end;
  integer sig_fd, sig_addr;

  // exit on tohost
  integer cycle = 0;
  always @(posedge clk) begin
    if (!rst) cycle <= cycle + 1;
    if (tohost_we) begin
      $display("[TB] tohost write: 0x%08x at cycle %0d", tohost, cycle);
      if ($value$plusargs("SIG_FILE=%s", sig_file) &&
          $value$plusargs("SIG_BEGIN=%h", sig_begin) &&
          $value$plusargs("SIG_END=%h", sig_end)) begin
        sig_fd = $fopen(sig_file, "w");
        if (sig_fd != 0) begin
          for (sig_addr = sig_begin; sig_addr < sig_end; sig_addr = sig_addr + 4) begin
            if (sig_addr >= 32'h8000_0000)
              $fdisplay(sig_fd, "%08x", dut.dram[(sig_addr - 32'h8000_0000) >> 2]);
            else
              $fdisplay(sig_fd, "%08x", dut.imem[sig_addr >> 2]);
          end
          $fclose(sig_fd);
          $display("[TB] Signature dumped to %s (%0d words)", sig_file, (sig_end - sig_begin) >> 2);
        end
      end
      if (tohost == 32'd1) $display("[TB] PASS");
      else                 $display("[TB] FAIL (code %0d)", tohost);
      $finish;
    end
    if (cycle > max_cyc) begin
      $display("[TB] TIMEOUT — no tohost write");
      $finish;
    end
  end
endmodule
