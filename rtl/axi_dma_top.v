// ----------------------------------------------------------------------------
// Module: axi_dma_top
// Description: Top-level AXI4 DMA controller.
//              Integrates the AXI4 slave register block and the DMA engine
//              with AXI4 master interface.
//              Fully synchronous, single clock domain design.
//
// Interfaces:
//   - AXI4 Slave  : Configuration port (host writes DMA registers)
//   - AXI4 Master : Data port (DMA reads/writes memory)
//   - IRQ         : Interrupt output
//
// Register Map (via AXI4 Slave):
//   0x00  SRC_ADDR   - Source address
//   0x04  DST_ADDR   - Destination address
//   0x08  XFER_LEN   - Transfer length in bytes
//   0x0C  CTRL       - Control (bit0: START, bit1: IRQ_EN, bit2: SOFT_RESET)
//   0x10  STATUS     - Status (bit0: BUSY, bit1: DONE, bit2: ERROR)
//   0x14  VERSION    - Version (read-only, 0x00010000)
// ----------------------------------------------------------------------------

module axi_dma_top #(
    parameter AXI_DATA_WIDTH = 32,
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_ID_WIDTH   = 4,
    parameter AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8,
    parameter FIFO_DEPTH     = 256,
    parameter MAX_BURST_LEN  = 256
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // -------------------------------------------------------
    // AXI4 Slave Interface (Configuration)
    // -------------------------------------------------------
    // Write Address Channel
    input  wire [AXI_ID_WIDTH-1:0]      s_axi_awid,
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire [7:0]                   s_axi_awlen,
    input  wire [2:0]                   s_axi_awsize,
    input  wire [1:0]                   s_axi_awburst,
    input  wire                         s_axi_awlock,
    input  wire [3:0]                   s_axi_awcache,
    input  wire [2:0]                   s_axi_awprot,
    input  wire [3:0]                   s_axi_awqos,
    input  wire                         s_axi_awvalid,
    output wire                         s_axi_awready,

    // Write Data Channel
    input  wire [AXI_DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [AXI_STRB_WIDTH-1:0]    s_axi_wstrb,
    input  wire                         s_axi_wlast,
    input  wire                         s_axi_wvalid,
    output wire                         s_axi_wready,

    // Write Response Channel
    output wire [AXI_ID_WIDTH-1:0]      s_axi_bid,
    output wire [1:0]                   s_axi_bresp,
    output wire                         s_axi_bvalid,
    input  wire                         s_axi_bready,

    // Read Address Channel
    input  wire [AXI_ID_WIDTH-1:0]      s_axi_arid,
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire [7:0]                   s_axi_arlen,
    input  wire [2:0]                   s_axi_arsize,
    input  wire [1:0]                   s_axi_arburst,
    input  wire                         s_axi_arlock,
    input  wire [3:0]                   s_axi_arcache,
    input  wire [2:0]                   s_axi_arprot,
    input  wire [3:0]                   s_axi_arqos,
    input  wire                         s_axi_arvalid,
    output wire                         s_axi_arready,

    // Read Data Channel
    output wire [AXI_ID_WIDTH-1:0]      s_axi_rid,
    output wire [AXI_DATA_WIDTH-1:0]    s_axi_rdata,
    output wire [1:0]                   s_axi_rresp,
    output wire                         s_axi_rlast,
    output wire                         s_axi_rvalid,
    input  wire                         s_axi_rready,

    // -------------------------------------------------------
    // AXI4 Master Interface (Data Transfer)
    // -------------------------------------------------------
    // Write Address Channel
    output wire [AXI_ID_WIDTH-1:0]      m_axi_awid,
    output wire [AXI_ADDR_WIDTH-1:0]    m_axi_awaddr,
    output wire [7:0]                   m_axi_awlen,
    output wire [2:0]                   m_axi_awsize,
    output wire [1:0]                   m_axi_awburst,
    output wire                         m_axi_awlock,
    output wire [3:0]                   m_axi_awcache,
    output wire [2:0]                   m_axi_awprot,
    output wire [3:0]                   m_axi_awqos,
    output wire                         m_axi_awvalid,
    input  wire                         m_axi_awready,

    // Write Data Channel
    output wire [AXI_DATA_WIDTH-1:0]    m_axi_wdata,
    output wire [AXI_STRB_WIDTH-1:0]    m_axi_wstrb,
    output wire                         m_axi_wlast,
    output wire                         m_axi_wvalid,
    input  wire                         m_axi_wready,

    // Write Response Channel
    input  wire [AXI_ID_WIDTH-1:0]      m_axi_bid,
    input  wire [1:0]                   m_axi_bresp,
    input  wire                         m_axi_bvalid,
    output wire                         m_axi_bready,

    // Read Address Channel
    output wire [AXI_ID_WIDTH-1:0]      m_axi_arid,
    output wire [AXI_ADDR_WIDTH-1:0]    m_axi_araddr,
    output wire [7:0]                   m_axi_arlen,
    output wire [2:0]                   m_axi_arsize,
    output wire [1:0]                   m_axi_arburst,
    output wire                         m_axi_arlock,
    output wire [3:0]                   m_axi_arcache,
    output wire [2:0]                   m_axi_arprot,
    output wire [3:0]                   m_axi_arqos,
    output wire                         m_axi_arvalid,
    input  wire                         m_axi_arready,

    // Read Data Channel
    input  wire [AXI_ID_WIDTH-1:0]      m_axi_rid,
    input  wire [AXI_DATA_WIDTH-1:0]    m_axi_rdata,
    input  wire [1:0]                   m_axi_rresp,
    input  wire                         m_axi_rlast,
    input  wire                         m_axi_rvalid,
    output wire                         m_axi_rready,

    // -------------------------------------------------------
    // Interrupt
    // -------------------------------------------------------
    output wire                         irq
);

    // -------------------------------------------------------
    // Internal wires between register block and engine
    // -------------------------------------------------------
    wire [31:0] reg_src_addr;
    wire [31:0] reg_dst_addr;
    wire [31:0] reg_xfer_len;
    wire        reg_start;
    wire        reg_irq_en;
    wire        reg_soft_reset;
    wire        dma_busy;
    wire        dma_done_pulse;
    wire        dma_error_pulse;
    wire        engine_irq;

    // Mask IRQ with enable bit from register
    assign irq = engine_irq & reg_irq_en;

    // -------------------------------------------------------
    // Register Block (AXI4 Slave)
    // -------------------------------------------------------
    axi_dma_reg #(
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH   (AXI_ID_WIDTH)
    ) u_reg (
        .clk              (clk),
        .rst_n            (rst_n),

        // AXI4 Slave
        .s_axi_awid       (s_axi_awid),
        .s_axi_awaddr     (s_axi_awaddr),
        .s_axi_awlen      (s_axi_awlen),
        .s_axi_awsize     (s_axi_awsize),
        .s_axi_awburst    (s_axi_awburst),
        .s_axi_awlock     (s_axi_awlock),
        .s_axi_awcache    (s_axi_awcache),
        .s_axi_awprot     (s_axi_awprot),
        .s_axi_awqos      (s_axi_awqos),
        .s_axi_awvalid    (s_axi_awvalid),
        .s_axi_awready    (s_axi_awready),

        .s_axi_wdata      (s_axi_wdata),
        .s_axi_wstrb      (s_axi_wstrb),
        .s_axi_wlast      (s_axi_wlast),
        .s_axi_wvalid     (s_axi_wvalid),
        .s_axi_wready     (s_axi_wready),

        .s_axi_bid        (s_axi_bid),
        .s_axi_bresp      (s_axi_bresp),
        .s_axi_bvalid     (s_axi_bvalid),
        .s_axi_bready     (s_axi_bready),

        .s_axi_arid       (s_axi_arid),
        .s_axi_araddr     (s_axi_araddr),
        .s_axi_arlen      (s_axi_arlen),
        .s_axi_arsize     (s_axi_arsize),
        .s_axi_arburst    (s_axi_arburst),
        .s_axi_arlock     (s_axi_arlock),
        .s_axi_arcache    (s_axi_arcache),
        .s_axi_arprot     (s_axi_arprot),
        .s_axi_arqos      (s_axi_arqos),
        .s_axi_arvalid    (s_axi_arvalid),
        .s_axi_arready    (s_axi_arready),

        .s_axi_rid        (s_axi_rid),
        .s_axi_rdata      (s_axi_rdata),
        .s_axi_rresp      (s_axi_rresp),
        .s_axi_rlast      (s_axi_rlast),
        .s_axi_rvalid     (s_axi_rvalid),
        .s_axi_rready     (s_axi_rready),

        // Register interface
        .reg_src_addr     (reg_src_addr),
        .reg_dst_addr     (reg_dst_addr),
        .reg_xfer_len     (reg_xfer_len),
        .reg_start        (reg_start),
        .reg_irq_en       (reg_irq_en),
        .reg_soft_reset   (reg_soft_reset),

        .dma_busy         (dma_busy),
        .dma_done_pulse   (dma_done_pulse),
        .dma_error_pulse  (dma_error_pulse)
    );

    // -------------------------------------------------------
    // DMA Engine (AXI4 Master)
    // -------------------------------------------------------
    axi_dma_engine #(
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .FIFO_DEPTH     (FIFO_DEPTH),
        .MAX_BURST_LEN  (MAX_BURST_LEN)
    ) u_engine (
        .clk              (clk),
        .rst_n            (rst_n),

        // AXI4 Master
        .m_axi_awid       (m_axi_awid),
        .m_axi_awaddr     (m_axi_awaddr),
        .m_axi_awlen      (m_axi_awlen),
        .m_axi_awsize     (m_axi_awsize),
        .m_axi_awburst    (m_axi_awburst),
        .m_axi_awlock     (m_axi_awlock),
        .m_axi_awcache    (m_axi_awcache),
        .m_axi_awprot     (m_axi_awprot),
        .m_axi_awqos      (m_axi_awqos),
        .m_axi_awvalid    (m_axi_awvalid),
        .m_axi_awready    (m_axi_awready),

        .m_axi_wdata      (m_axi_wdata),
        .m_axi_wstrb      (m_axi_wstrb),
        .m_axi_wlast      (m_axi_wlast),
        .m_axi_wvalid     (m_axi_wvalid),
        .m_axi_wready     (m_axi_wready),

        .m_axi_bid        (m_axi_bid),
        .m_axi_bresp      (m_axi_bresp),
        .m_axi_bvalid     (m_axi_bvalid),
        .m_axi_bready     (m_axi_bready),

        .m_axi_arid       (m_axi_arid),
        .m_axi_araddr     (m_axi_araddr),
        .m_axi_arlen      (m_axi_arlen),
        .m_axi_arsize     (m_axi_arsize),
        .m_axi_arburst    (m_axi_arburst),
        .m_axi_arlock     (m_axi_arlock),
        .m_axi_arcache    (m_axi_arcache),
        .m_axi_arprot     (m_axi_arprot),
        .m_axi_arqos      (m_axi_arqos),
        .m_axi_arvalid    (m_axi_arvalid),
        .m_axi_arready    (m_axi_arready),

        .m_axi_rid        (m_axi_rid),
        .m_axi_rdata      (m_axi_rdata),
        .m_axi_rresp      (m_axi_rresp),
        .m_axi_rlast      (m_axi_rlast),
        .m_axi_rvalid     (m_axi_rvalid),
        .m_axi_rready     (m_axi_rready),

        // Control / Status
        .reg_src_addr     (reg_src_addr),
        .reg_dst_addr     (reg_dst_addr),
        .reg_xfer_len     (reg_xfer_len),
        .reg_start        (reg_start),
        .reg_soft_reset   (reg_soft_reset),

        .dma_busy         (dma_busy),
        .dma_done_pulse   (dma_done_pulse),
        .dma_error_pulse  (dma_error_pulse),
        .irq              (engine_irq)
    );

endmodule
