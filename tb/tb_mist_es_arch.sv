// ============================================================================
// tb_mist_es_arch.sv — architecture-test testbench for the MIST-ES SoC (RV32IMC).
//
//   sim/tb_mist_es_arch +IMEM=<imem.hex> +DMEM=<dram.hex> +SIGNATURE=<sig_out> \
//          +SIG_BEGIN=0x... +SIG_END=0x...
//
// Loads the code image into IMEM (0x0000_0000) and the data image into DRAM
// (0x8000_0000). On the tohost store (0x2000_0000) it writes the words between
// SIG_BEGIN and SIG_END to the signature file and prints the verdict.
// ============================================================================
`timescale 1ns/1ps

module tb_mist_es_arch;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst;

  localparam int IMEM_WORDS = 524288;
  localparam int DRAM_WORDS = 65536;

  logic [31:0] tohost;
  logic        tohost_we;
  logic        retire_valid, retire_rd_we;
  logic [31:0] retire_pc, retire_instr, retire_rd_val;
  logic [4:0]  retire_rd;

  mist_es_soc #(.IMEM_WORDS(IMEM_WORDS), .DRAM_WORDS(DRAM_WORDS)) dut (
    .clk(clk), .rst(rst),
    .tck(1'b0), .tms(1'b0), .tdi(1'b0), .tdo(),
    .tohost(tohost), .tohost_we(tohost_we),
    .retire_valid(retire_valid), .retire_pc(retire_pc),
    .retire_instr(retire_instr), .retire_rd_we(retire_rd_we),
    .retire_rd(retire_rd), .retire_rd_val(retire_rd_val)
  );

  string imem_file, dmem_file, sig_file;
  logic [31:0] sig_begin, sig_end;
  integer sig_fd, sig_addr;
  integer i, cycle = 0;
  integer max_cycles = 2000000;

  initial begin
    if (!$value$plusargs("IMEM=%s", imem_file)) begin
      $display("FATAL: no +IMEM=<file> given");
      $finish;
    end
    void'($value$plusargs("MAXCYCLES=%d", max_cycles));
    for (i = 0; i < IMEM_WORDS; i = i + 1) dut.imem[i] = 32'h0000_0013;  // NOP fill
    for (i = 0; i < DRAM_WORDS; i = i + 1) dut.dram[i] = 32'h0;
    $readmemh(imem_file, dut.imem);
    if ($value$plusargs("DMEM=%s", dmem_file)) $readmemh(dmem_file, dut.dram);
    rst = 1'b1;
    repeat (4) @(posedge clk);
    rst = 1'b0;
  end

  always @(posedge clk) begin
    if (!rst) cycle <= cycle + 1;

    if (tohost_we) begin
      if ($value$plusargs("SIGNATURE=%s", sig_file) &&
          $value$plusargs("SIG_BEGIN=0x%x", sig_begin) &&
          $value$plusargs("SIG_END=0x%x", sig_end)) begin
        sig_fd = $fopen(sig_file, "w");
        if (sig_fd != 0) begin
          for (sig_addr = sig_begin; sig_addr < sig_end; sig_addr = sig_addr + 4)
            $fdisplay(sig_fd, "%08x", dut.dram[(sig_addr - 32'h8000_0000) >> 2]);
          $fclose(sig_fd);
        end else begin
          $display("ERROR: could not open signature file: %s", sig_file);
        end
      end
      if (tohost == 32'd1) $display("RESULT: PASS");
      else                     $display("RESULT: FAIL code=%0d", tohost);
      $finish;
    end

    if (cycle > max_cycles) begin
      $display("RESULT: FAIL timeout");
      $finish;
    end
  end
endmodule
