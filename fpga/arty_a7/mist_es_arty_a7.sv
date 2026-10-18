// mist_es_arty_a7.sv — Digilent Arty A7-100T top for the MIST-ES SoC.
// Device: xc7a100tcsg324-1.
//
// Clock strategy:
//   BUFR ÷2 cannot drive BRAMs across multiple clock regions. With 128 KB
//   BRAM (32 tiles spanning multiple regions), we use PLLE2_BASE to generate
//   50 MHz, buffered by BUFG for global reach. This avoids any MMCM licence
//   issues (PLLE2_BASE is freely available on all Artix-7 devices) and gives
//   comfortable positive WNS at 50 MHz.
//
//   CLK100        E3   100 MHz board oscillator (input)
//   clk_50        ---  50 MHz after PLLE2_BASE + BUFG (used by SoC)
//   ck_rst        C2   reset push-button (ACTIVE-LOW on Arty)
//   led[3:0]      H5 J5 T9 T10
//   uart_txd_in   A9   host → FPGA RX
//   uart_rxd_out  D10  FPGA → host TX, 115200-8N1
//   jtag_*        PMOD JA
//
// After bitstream is loaded:
//   openFPGALoader -b arty_a7_100t mist_es_arty_a7.bit
//   python3 sw/run_hil_bench.py --port /dev/ttyUSB1 --freq 50 --bench coremark --no-flash
// ============================================================================
`default_nettype none

module mist_es_arty_a7 #(
  parameter bit SECURE = 1'b0
)(
  input  wire       CLK100,
  input  wire       ck_rst,        // active-low
  output wire [3:0] led,
  input  wire       uart_txd_in,   // RX
  output wire       uart_rxd_out,  // TX
  // RISC-V Debug (JTAG) on PMOD JA
  input  wire       jtag_tck,
  input  wire       jtag_tms,
  input  wire       jtag_tdi,
  output wire       jtag_tdo
);

  // ---- 100 MHz → 50 MHz via PLLE2_BASE + BUFG ------------------------------
  // PLLE2_BASE is available on all Artix-7 devices without additional licence.
  // Its CLKOUT0 drives a BUFG (global clock buffer), which unlike BUFR can
  // reach BRAMs placed in any clock region across the device.
  // VCO = 100 * 10 / 1 = 1000 MHz ; CLKOUT0 = 1000 / 20 = 50 MHz.
  wire pll_fb, pll_clk50_raw, clk_50, pll_locked;
  PLLE2_BASE #(
      .CLKIN1_PERIOD (10.0),   // 100 MHz
      .CLKFBOUT_MULT (10),     // VCO = 1000 MHz
      .DIVCLK_DIVIDE (1),
      .CLKOUT0_DIVIDE(20),     // 1000/20 = 50 MHz
      .STARTUP_WAIT  ("FALSE")
  ) u_pll (
      .CLKIN1  (CLK100),
      .CLKFBIN (pll_fb),
      .CLKFBOUT(pll_fb),
      .CLKOUT0 (pll_clk50_raw),
      .LOCKED  (pll_locked),
      .PWRDWN  (1'b0),
      .RST     (1'b0)
  );
  BUFG u_clkbuf (.I(pll_clk50_raw), .O(clk_50));

  // ---- Synchronous reset: deassert only after PLL locks --------------------
  wire sys_rst;
  common_reset_sync #(.DEPTH(3), .ACTIVE_HIGH(1'b1)) u_rst (
      .clk(clk_50), .async_rst_in(~ck_rst | ~pll_locked), .sync_rst_out(sys_rst));

  // ---- MIST-ES SoC at 50 MHz ----------------------------------------------
  // CLK_HZ must match the actual clock so the UART baud divisor is correct.
  wire [7:0] soc_leds;
  mist_es_fpga #(.CLK_HZ(50_000_000), .UART_BAUD(115_200),
                 .MEM_WORDS(32768), .MEMFILE("firmware.mem"),
                 .SECURE(SECURE)) u_soc (
      .clk(clk_50), .rst(sys_rst),
      .tck(jtag_tck), .tms(jtag_tms), .tdi(jtag_tdi), .tdo(jtag_tdo),
      .leds(soc_leds), .serial_tx(uart_rxd_out), .serial_rx(uart_txd_in),
      .tohost(), .tohost_we()
  );

  assign led = soc_leds[3:0];
endmodule

`default_nettype wire
