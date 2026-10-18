// ============================================================================
// tb_mist_es_fpga.sv — sim check of the synthesizable FPGA SoC.
// Boots firmware.mem ($readmemh) and verifies the demo actually runs on the
// real SoC: UART transmits the banner and the LEDs are driven. The UART's
// $write (translate_off) echoes the banner to the console too.
//   vvp sim/tb_mist_es_fpga +MEM=../sw/firmware.mem
// ============================================================================
`timescale 1ns/1ps

module tb_mist_es_fpga;
  logic clk = 1'b0; always #5 clk = ~clk;
  logic rst;
  logic [7:0] leds; logic serial_tx; logic [31:0] tohost; logic tohost_we;
  string memf;

  // fast UART baud for sim (real boards use 115200); MEM defaults to firmware.mem
  initial if (!$value$plusargs("MEM=%s", memf)) memf = "sw/firmware.mem";

  mist_es_fpga #(.CLK_HZ(50_000_000), .UART_BAUD(12_500_000),
                 .MEM_WORDS(4096), .MEMFILE("sw/firmware.mem")) dut (
    .clk(clk), .rst(rst), .tck(1'b0), .tms(1'b0), .tdi(1'b0), .tdo(),
    .leds(leds), .serial_tx(serial_tx), .serial_rx(1'b1),
    .tohost(tohost), .tohost_we(tohost_we)
  );

  integer bytes = 0;
  always @(posedge clk) if (!rst && dut.u_uart.tx_load) bytes = bytes + 1;

  initial begin
    rst = 1'b1; repeat (6) @(posedge clk); rst = 1'b0;
    // wait for the banner (28 chars) to be transmitted
    while (bytes < 28) @(posedge clk);
    repeat (50) @(posedge clk);           // let the LED store land
    $display("\n[FPGA] uart bytes sent=%0d  leds=0x%02x", bytes, leds);
    if (bytes >= 28 && leds != 8'h00) $display("FPGA: PASS");
    else                              $display("FPGA: FAIL");
    $finish;
  end

  initial begin #2000000; $display("FPGA: FAIL (timeout)"); $finish; end
endmodule
