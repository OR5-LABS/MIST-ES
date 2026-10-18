// ============================================================================
// tb_mist_es_debug.sv — self-checking JTAG / RISC-V Debug-Module testbench.
//
//   iverilog -g2012 ... rtl/mist_es_debug.sv ... tb/tb_mist_es_debug.sv
//   vvp sim/tb_mist_es_debug
//
// Bit-bangs the JTAG TAP exactly as OpenOCD would and exercises the full debug
// flow against a free-running counter loop in IMEM:
//   1. read IDCODE
//   2. dmactive, then haltreq  → poll dmstatus.allhalted
//   3. read GPR x1 (loop counter, must be progressing)
//   4. read CSR misa + dpc (local debug CSR)
//   5. write GPR x31, read back
//   6. write memory word via System Bus Access, read back
//   7. resume → poll dmstatus.allrunning, confirm the counter advanced
// Reports DEBUG: PASS / DEBUG: FAIL.
// ============================================================================
`timescale 1ns/1ps

module tb_mist_es_debug;
  logic clk = 1'b0; always #5 clk = ~clk;
  logic rst;
  logic tck = 1'b0, tms = 1'b0, tdi = 1'b0, tdo;

  logic [31:0] tohost; logic tohost_we;
  logic        rv; logic [31:0] rpc, rins, rval; logic rwe; logic [4:0] rrd;

  mist_es_soc dut (
    .clk(clk), .rst(rst), .tck(tck), .tms(tms), .tdi(tdi), .tdo(tdo),
    .tohost(tohost), .tohost_we(tohost_we),
    .retire_valid(rv), .retire_pc(rpc), .retire_instr(rins),
    .retire_rd_we(rwe), .retire_rd(rrd), .retire_rd_val(rval)
  );

  integer i, errors = 0;
  reg [63:0] dump, cap;

  // ---- one oversampled TCK cycle (held long enough for the 2-FF sync) ------
  task automatic tck_cyc(input bit tms_v, input bit tdi_v);
    begin
      tms = tms_v; tdi = tdi_v; @(posedge clk);
      tck = 1'b1; repeat (3) @(posedge clk);
      tck = 1'b0; repeat (3) @(posedge clk);
    end
  endtask

  task automatic jtag_reset; begin
    for (i=0;i<6;i++) tck_cyc(1,0);   // -> Test-Logic-Reset
    tck_cyc(0,0);                     // -> Run-Test/Idle
  end endtask

  // shift n bits through a DR scan (LSB first), returning the captured value
  task automatic scan_dr(input int n, input [63:0] din, output [63:0] dout);
    int k; begin
      dout = 0;
      tck_cyc(1,0); tck_cyc(0,0);                 // RTI->SEL_DR->CAP_DR
      while (dut.u_dbg.tap != 4) tck_cyc(0,0);    // ->SHIFT_DR (loads dr on entry)
      for (k=0;k<n;k++) begin
        dout[k] = tdo;
        tck_cyc((k==n-1)?1'b1:1'b0, din[k]);
      end
      tck_cyc(1,0); tck_cyc(0,0);                 // EXIT1->UPDATE->RTI
    end
  endtask

  task automatic scan_ir(input [4:0] irval);
    int k; begin
      tck_cyc(1,0); tck_cyc(1,0); tck_cyc(0,0);   // RTI->SEL_DR->SEL_IR->CAP_IR
      while (dut.u_dbg.tap != 11) tck_cyc(0,0);   // ->SHIFT_IR
      for (k=0;k<5;k++) tck_cyc((k==4)?1'b1:1'b0, irval[k]);
      tck_cyc(1,0); tck_cyc(0,0);                              // ->UPDATE_IR->RTI
    end
  endtask

  // DMI helpers (op: 1=read, 2=write)
  task automatic dmi_write(input [6:0] a, input [31:0] d);
    begin scan_dr(41, {23'd0, a, d, 2'd2}, dump); end
  endtask
  task automatic dmi_read(input [6:0] a, output [31:0] d);
    begin
      scan_dr(41, {23'd0, a, 32'd0, 2'd1}, dump);   // issue read
      scan_dr(41, {23'd0, 7'd0, 32'd0, 2'd0}, cap); // shift result out
      d = cap[33:2];
    end
  endtask

  // abstract Access-Register command words
  function [31:0] arcmd(input bit wr, input [15:0] regno);
    arcmd = (3'd2<<20) | (1<<17) | (wr<<16) | regno;  // aarsize=32, transfer
  endfunction

  task automatic check(input [255:0] name, input [31:0] got, input [31:0] exp);
    begin
      if (got !== exp) begin
        $display("[DBG] FAIL %0s: got %08x exp %08x", name, got, exp);
        errors = errors + 1;
      end else $display("[DBG] ok   %0s = %08x", name, got);
    end
  endtask

  localparam [6:0] DATA0=7'h04, DMCONTROL=7'h10, DMSTATUS=7'h11,
                   ABSTRACTCS=7'h16, COMMAND=7'h17, SBCS=7'h38,
                   SBADDR0=7'h39, SBDATA0=7'h3c;

  reg [31:0] v, idcode, x1_a, x1_b;
  integer halts;

  initial begin
    // counter loop in IMEM:  0: addi x1,x1,1 ; 4: jal x0,-4
    for (i=0;i<8192;i++) begin dut.imem[i]=32'h00000013; dut.dram[i]=32'h0; end
    dut.imem[0] = 32'h00108093;   // addi x1,x1,1
    dut.imem[1] = 32'hFFDFF06F;   // jal  x0,-4
    rst = 1'b1; repeat (6) @(posedge clk); rst = 1'b0;
    repeat (40) @(posedge clk);   // let the counter run a while

    jtag_reset;

    // (1) IDCODE
    scan_dr(32, 64'd0, cap); idcode = cap[31:0];
    check("idcode", idcode, 32'h4D49_5355);

    // (2) select DMI, activate DM, request halt
    scan_ir(5'h11);
    dmi_write(DMCONTROL, 32'h0000_0001);            // dmactive=1
    dmi_write(DMCONTROL, 32'h8000_0001);            // dmactive=1 | haltreq
    halts = 0;
    for (i=0;i<20;i++) begin
      dmi_read(DMSTATUS, v);
      if (v[9]) begin halts = 1; i = 20; end        // allhalted
    end
    if (!halts) begin $display("[DBG] FAIL: hart did not halt"); errors=errors+1; end
    else $display("[DBG] ok   hart halted (dmstatus=%08x)", v);

    // (3) read GPR x1 (must be nonzero — the loop has been counting)
    dmi_write(COMMAND, arcmd(1'b0, 16'h1001));
    dmi_read(DATA0, x1_a);
    if (x1_a == 32'd0) begin $display("[DBG] FAIL: x1==0 (no progress)"); errors=errors+1; end
    else $display("[DBG] ok   x1(halt#1) = %0d", x1_a);

    // (4) read CSR misa + dpc (local debug CSR)
    dmi_write(COMMAND, arcmd(1'b0, 16'h0301)); dmi_read(DATA0, v);
    check("misa", v, 32'h4000_1104);   // RV32IMC (default build: SECURE off)
    dmi_write(COMMAND, arcmd(1'b0, 16'h07b1)); dmi_read(DATA0, v);  // dpc
    if (v > 32'h8) begin $display("[DBG] FAIL: dpc=%08x out of loop", v); errors=errors+1; end
    else $display("[DBG] ok   dpc = %08x", v);

    // (5) write GPR x31, read back
    dmi_write(DATA0, 32'hDEAD_BEEF);
    dmi_write(COMMAND, arcmd(1'b1, 16'h101F));      // write x31
    dmi_write(COMMAND, arcmd(1'b0, 16'h101F));      // read x31
    dmi_read(DATA0, v);
    check("gpr x31 wr/rd", v, 32'hDEAD_BEEF);

    // (6) System Bus Access: write a DRAM word, read it back
    dmi_write(SBADDR0, 32'h8000_7000);
    dmi_write(SBDATA0, 32'hCAFE_F00D);              // triggers SB write
    dmi_write(SBCS,    32'h0010_0000);              // sbreadonaddr=1 (bit20)
    dmi_write(SBADDR0, 32'h8000_7000);              // triggers SB read
    dmi_read(SBDATA0, v);
    check("sba mem wr/rd", v, 32'hCAFE_F00D);

    // (7) resume and confirm the counter advances
    dmi_write(DMCONTROL, 32'h4000_0001);            // dmactive=1 | resumereq
    for (i=0;i<20;i++) begin
      dmi_read(DMSTATUS, v);
      if (v[11]) i = 20;                            // allrunning
    end
    if (!v[11]) begin $display("[DBG] FAIL: hart did not resume"); errors=errors+1; end
    else $display("[DBG] ok   hart resumed (dmstatus=%08x)", v);

    repeat (60) @(posedge clk);                     // let it count more
    // halt again and re-read x1 — must have advanced past x1_a
    dmi_write(DMCONTROL, 32'h8000_0001);
    for (i=0;i<20;i++) begin dmi_read(DMSTATUS, v); if (v[9]) i = 20; end
    dmi_write(COMMAND, arcmd(1'b0, 16'h1001));
    dmi_read(DATA0, x1_b);
    if (x1_b <= x1_a) begin
      $display("[DBG] FAIL: counter did not advance after resume (%0d -> %0d)", x1_a, x1_b);
      errors = errors + 1;
    end else $display("[DBG] ok   counter advanced %0d -> %0d after resume", x1_a, x1_b);

    // (8) single-step: set dcsr.step, resume → exactly one instruction retires,
    //     then the hart re-enters debug on its own (cause = step).
    dmi_write(DATA0, 32'h0000_0004);                // dcsr.step (bit2)
    dmi_write(COMMAND, arcmd(1'b1, 16'h07b0));      // write dcsr
    dmi_write(COMMAND, arcmd(1'b0, 16'h1001)); dmi_read(DATA0, x1_a);  // x1 before step
    dmi_write(DMCONTROL, 32'h4000_0001);            // resume (haltreq=0) → single step
    halts = 0;
    for (i=0;i<20;i++) begin dmi_read(DMSTATUS, v); if (v[9]) begin halts=1; i=20; end end
    if (!halts) begin $display("[DBG] FAIL: no re-halt after single-step"); errors=errors+1; end
    else begin
      dmi_write(COMMAND, arcmd(1'b0, 16'h1001)); dmi_read(DATA0, x1_b);  // x1 after one step
      if (x1_b != x1_a && x1_b != x1_a + 1)
        begin $display("[DBG] FAIL: step ran >1 instr (%0d -> %0d)", x1_a, x1_b); errors=errors+1; end
      else $display("[DBG] ok   single-step: one instruction (%0d -> %0d), re-halted", x1_a, x1_b);
    end
    dmi_write(DATA0, 32'h0); dmi_write(COMMAND, arcmd(1'b1, 16'h07b0)); // clear dcsr.step

    if (errors == 0) $display("DEBUG: PASS");
    else             $display("DEBUG: FAIL (%0d errors)", errors);
    $finish;
  end

  initial begin #500000; $display("DEBUG: FAIL (timeout)"); $finish; end
endmodule
