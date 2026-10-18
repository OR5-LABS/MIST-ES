// ============================================================================
// mist_es_axil.sv — AXI4-Lite bus integration for MIST-ES (standard-bus
// drop-in). Three modules:
//   * mist_es_axil_master : wraps mist_es_core, turns its fetch/load/store
//     requests into AXI4-Lite read/write transactions, and drives mem_stall
//     from the AXI handshake (so the core waits for the bus).
//   * axil_bram_slave     : an AXI4-Lite slave with unified IMEM/DRAM + tohost.
//   * mist_es_axil_soc    : connects master <-> slave over real AXI4-Lite wires.
//
// This lets the core talk a standard bus and drop into any AXI4-Lite fabric.
// ============================================================================
`include "mist_es_pkg.sv"

// ---------------------------------------------------------------------------
module mist_es_axil_master
  import mist_es_pkg::*;
#( parameter logic [XLEN-1:0] RESET_PC = 32'h0 )
( input logic clk, rst,
  // AXI4-Lite master
  output logic [31:0] awaddr, output logic awvalid, input logic awready,
  output logic [31:0] wdata,  output logic [3:0] wstrb, output logic wvalid, input logic wready,
  input  logic [1:0]  bresp,  input logic bvalid, output logic bready,
  output logic [31:0] araddr, output logic arvalid, input logic arready,
  input  logic [31:0] rdata,  input logic [1:0] rresp, input logic rvalid, output logic rready );

  // core <-> wrapper
  logic [31:0] imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_rdata;
  logic        dmem_re, dmem_we, mem_stall, mem_req;
  logic [3:0]  dmem_be;
  logic        rv, rwe; logic [4:0] rrd; logic [31:0] rpc,rin,rval;

  mist_es_core #(.RESET_PC(RESET_PC)) u_core (
    .clk(clk), .rst(rst), .imem_addr(imem_addr), .imem_rdata(imem_rdata),
    .dmem_addr(dmem_addr), .dmem_re(dmem_re), .dmem_we(dmem_we), .dmem_be(dmem_be),
    .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
    .irq_timer(1'b0), .irq_soft(1'b0), .irq_ext(1'b0),
    .mem_stall(mem_stall), .mem_req(mem_req),
    .retire_valid(rv), .retire_pc(rpc), .retire_instr(rin),
    .retire_rd_we(rwe), .retire_rd(rrd), .retire_rd_val(rval) );

  wire is_data  = dmem_re | dmem_we;
  wire [31:0] acc_addr = is_data ? dmem_addr : imem_addr;

  typedef enum logic [2:0] { AX_IDLE, AX_AR, AX_R, AX_AW, AX_B } st_e;
  st_e st;

  // address/data driven combinationally (core is held stable while mem_stall)
  assign araddr = acc_addr;
  assign awaddr = dmem_addr;
  assign wdata  = dmem_wdata;
  assign wstrb  = dmem_be;
  assign arvalid = (st==AX_AR);
  assign awvalid = (st==AX_AW);
  assign wvalid  = (st==AX_AW);
  assign bready  = (st==AX_B);
  assign rready  = (st==AX_R);

  // read data back to the core only on the completing cycle
  wire done = (st==AX_R && rvalid) || (st==AX_B && bvalid);
  assign imem_rdata = (st==AX_R) ? rdata : 32'h0;
  assign dmem_rdata = (st==AX_R) ? rdata : 32'h0;
  assign mem_stall  = mem_req && !done;

  always_ff @(posedge clk) begin
    if (rst) st <= AX_IDLE;
    else unique case (st)
      AX_IDLE: if (mem_req) begin
                 if (dmem_we) st <= AX_AW;
                 else         st <= AX_AR;
               end
      AX_AR:   if (arready) st <= AX_R;
      AX_R:    if (rvalid)  st <= AX_IDLE;
      AX_AW:   if (awready && wready) st <= AX_B;
      AX_B:    if (bvalid)  st <= AX_IDLE;
      default: st <= AX_IDLE;
    endcase
  end
endmodule

// ---------------------------------------------------------------------------
module axil_bram_slave
  import mist_es_pkg::*;
#( parameter int IMEM_WORDS=8192, parameter int DRAM_WORDS=8192,
   parameter logic [31:0] DRAM_BASE=32'h8000_0000, parameter logic [31:0] TOHOST=32'h2000_0000 )
( input logic clk, rst,
  input  logic [31:0] awaddr, input logic awvalid, output logic awready,
  input  logic [31:0] wdata,  input logic [3:0] wstrb, input logic wvalid, output logic wready,
  output logic [1:0]  bresp,  output logic bvalid, input logic bready,
  input  logic [31:0] araddr, input logic arvalid, output logic arready,
  output logic [31:0] rdata,  output logic [1:0] rresp, output logic rvalid, input logic rready,
  output logic [31:0] tohost_o, output logic tohost_we );

  logic [31:0] imem [0:IMEM_WORDS-1];
  logic [31:0] dram [0:DRAM_WORDS-1];

  typedef enum logic [1:0] { SL_IDLE, SL_R, SL_B } s_e;
  s_e s; logic [31:0] raddr_q;

  assign arready = (s==SL_IDLE);
  assign awready = (s==SL_IDLE);
  assign wready  = (s==SL_IDLE);
  assign rvalid  = (s==SL_R);
  assign bvalid  = (s==SL_B);
  assign rresp = 2'b00; assign bresp = 2'b00;

  wire in_dram_r = (raddr_q[31:28]==4'h8);
  assign rdata = in_dram_r ? dram[raddr_q[$clog2(DRAM_WORDS)+1:2]]
                           : imem[raddr_q[$clog2(IMEM_WORDS)+1:2]];

  wire in_dram_w = (awaddr[31:28]==4'h8);
  wire [$clog2(DRAM_WORDS)-1:0] widx = awaddr[$clog2(DRAM_WORDS)+1:2];
  wire [31:0] cur = dram[widx];
  wire [31:0] merged = { wstrb[3]?wdata[31:24]:cur[31:24], wstrb[2]?wdata[23:16]:cur[23:16],
                         wstrb[1]?wdata[15:8]:cur[15:8], wstrb[0]?wdata[7:0]:cur[7:0] };
  assign tohost_o = wdata;

  always_ff @(posedge clk) begin
    tohost_we <= 1'b0;
    if (rst) s <= SL_IDLE;
    else unique case (s)
      SL_IDLE: begin
        if (arvalid) begin raddr_q <= araddr; s <= SL_R; end
        else if (awvalid && wvalid) begin
          if (in_dram_w) dram[widx] <= merged;
          else if (awaddr==TOHOST) tohost_we <= 1'b1;
          s <= SL_B;
        end
      end
      SL_R: if (rready) s <= SL_IDLE;
      SL_B: if (bready) s <= SL_IDLE;
      default: s <= SL_IDLE;
    endcase
  end
endmodule

// ---------------------------------------------------------------------------
module mist_es_axil_soc
  import mist_es_pkg::*;
( input logic clk, rst, output logic [31:0] tohost, output logic tohost_we );
  logic [31:0] awaddr,wdata,araddr,rdata; logic [3:0] wstrb; logic [1:0] bresp,rresp;
  logic awvalid,awready,wvalid,wready,bvalid,bready,arvalid,arready,rvalid,rready;

  mist_es_axil_master #(.RESET_PC(32'h0)) u_m (.clk(clk),.rst(rst),
    .awaddr(awaddr),.awvalid(awvalid),.awready(awready),
    .wdata(wdata),.wstrb(wstrb),.wvalid(wvalid),.wready(wready),
    .bresp(bresp),.bvalid(bvalid),.bready(bready),
    .araddr(araddr),.arvalid(arvalid),.arready(arready),
    .rdata(rdata),.rresp(rresp),.rvalid(rvalid),.rready(rready));

  axil_bram_slave u_s (.clk(clk),.rst(rst),
    .awaddr(awaddr),.awvalid(awvalid),.awready(awready),
    .wdata(wdata),.wstrb(wstrb),.wvalid(wvalid),.wready(wready),
    .bresp(bresp),.bvalid(bvalid),.bready(bready),
    .araddr(araddr),.arvalid(arvalid),.arready(arready),
    .rdata(rdata),.rresp(rresp),.rvalid(rvalid),.rready(rready),
    .tohost_o(tohost),.tohost_we(tohost_we));
endmodule
