// ----------------------------------------------------------------------------
// Module: axi_dma_reg
// Description: AXI4 Slave interface with DMA configuration register file.
//              Provides register read/write access for the host processor.
//
// Register Map (32-bit registers):
//   0x00  SRC_ADDR   - Source address [31:0]
//   0x04  DST_ADDR   - Destination address [31:0]
//   0x08  XFER_LEN   - Transfer length in bytes [31:0]
//   0x0C  CTRL       - Control register
//                       bit[0]: START  (write 1 to start, auto-clear)
//                       bit[1]: IRQ_EN (interrupt enable)
//                       bit[2]: SOFT_RESET
//   0x10  STATUS     - Status register
//                       bit[0]: BUSY
//                       bit[1]: DONE   (write 1 to clear)
//                       bit[2]: ERROR  (write 1 to clear)
//   0x14  VERSION    - Version register (read-only) = 32'h0001_0000
// ----------------------------------------------------------------------------

module axi_dma_reg #(
    parameter AXI_DATA_WIDTH = 32,
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_ID_WIDTH   = 4,
    parameter AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // -------------------------------------------------------
    // AXI4 Slave Interface
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
    output reg                          s_axi_awready,

    // Write Data Channel
    input  wire [AXI_DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [AXI_STRB_WIDTH-1:0]    s_axi_wstrb,
    input  wire                         s_axi_wlast,
    input  wire                         s_axi_wvalid,
    output reg                          s_axi_wready,

    // Write Response Channel
    output reg  [AXI_ID_WIDTH-1:0]      s_axi_bid,
    output reg  [1:0]                   s_axi_bresp,
    output reg                          s_axi_bvalid,
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
    output reg                          s_axi_arready,

    // Read Data Channel
    output reg  [AXI_ID_WIDTH-1:0]      s_axi_rid,
    output reg  [AXI_DATA_WIDTH-1:0]    s_axi_rdata,
    output reg  [1:0]                   s_axi_rresp,
    output reg                          s_axi_rlast,
    output reg                          s_axi_rvalid,
    input  wire                         s_axi_rready,

    // -------------------------------------------------------
    // Register outputs to DMA engine
    // -------------------------------------------------------
    output wire [31:0]                  reg_src_addr,
    output wire [31:0]                  reg_dst_addr,
    output wire [31:0]                  reg_xfer_len,
    output wire                         reg_start,
    output wire                         reg_irq_en,
    output wire                         reg_soft_reset,

    // -------------------------------------------------------
    // Status inputs from DMA engine
    // -------------------------------------------------------
    input  wire                         dma_busy,
    input  wire                         dma_done_pulse,
    input  wire                         dma_error_pulse
);

    // -------------------------------------------------------
    // Register definitions
    // -------------------------------------------------------
    localparam ADDR_SRC     = 6'h00;
    localparam ADDR_DST     = 6'h04;
    localparam ADDR_LEN     = 6'h08;
    localparam ADDR_CTRL    = 6'h0C;
    localparam ADDR_STATUS  = 6'h10;
    localparam ADDR_VERSION = 6'h14;

    localparam VERSION_VAL  = 32'h0001_0000;

    reg [31:0] r_src_addr;
    reg [31:0] r_dst_addr;
    reg [31:0] r_xfer_len;
    reg        r_start;
    reg        r_irq_en;
    reg        r_soft_reset;
    reg        r_done;
    reg        r_error;

    assign reg_src_addr   = r_src_addr;
    assign reg_dst_addr   = r_dst_addr;
    assign reg_xfer_len   = r_xfer_len;
    assign reg_start      = r_start;
    assign reg_irq_en     = r_irq_en;
    assign reg_soft_reset = r_soft_reset;

    // -------------------------------------------------------
    // Write FSM
    // -------------------------------------------------------
    localparam WR_IDLE    = 2'd0;
    localparam WR_DATA    = 2'd1;
    localparam WR_RESP    = 2'd2;

    reg [1:0]                   wr_state;
    reg [AXI_ADDR_WIDTH-1:0]   wr_addr;
    reg [AXI_ID_WIDTH-1:0]     wr_id;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state      <= WR_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            s_axi_bid     <= {AXI_ID_WIDTH{1'b0}};
            wr_addr       <= {AXI_ADDR_WIDTH{1'b0}};
            wr_id         <= {AXI_ID_WIDTH{1'b0}};
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    s_axi_bvalid  <= 1'b0;
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b0;
                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_addr       <= s_axi_awaddr;
                        wr_id         <= s_axi_awid;
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b1;
                        wr_state      <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        // Register write happens in separate always block
                        if (s_axi_wlast) begin
                            s_axi_wready <= 1'b0;
                            s_axi_bvalid <= 1'b1;
                            s_axi_bresp  <= 2'b00; // OKAY
                            s_axi_bid    <= wr_id;
                            wr_state     <= WR_RESP;
                        end else begin
                            // For burst writes, increment address
                            wr_addr <= wr_addr + (AXI_DATA_WIDTH / 8);
                        end
                    end
                end

                WR_RESP: begin
                    if (s_axi_bready && s_axi_bvalid) begin
                        s_axi_bvalid <= 1'b0;
                        wr_state     <= WR_IDLE;
                    end
                end

                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------
    // Register write logic
    // -------------------------------------------------------
    wire wr_fire = (wr_state == WR_DATA) && s_axi_wvalid && s_axi_wready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_src_addr   <= 32'h0;
            r_dst_addr   <= 32'h0;
            r_xfer_len   <= 32'h0;
            r_start      <= 1'b0;
            r_irq_en     <= 1'b0;
            r_soft_reset <= 1'b0;
            r_done       <= 1'b0;
            r_error      <= 1'b0;
        end else begin
            // Auto-clear start pulse
            if (r_start)
                r_start <= 1'b0;

            // Auto-clear soft reset
            if (r_soft_reset)
                r_soft_reset <= 1'b0;

            // Capture done/error from engine
            if (dma_done_pulse)
                r_done <= 1'b1;
            if (dma_error_pulse)
                r_error <= 1'b1;

            // Register writes
            if (wr_fire) begin
                case (wr_addr[5:0])
                    ADDR_SRC: begin
                        if (s_axi_wstrb[0]) r_src_addr[ 7: 0] <= s_axi_wdata[ 7: 0];
                        if (s_axi_wstrb[1]) r_src_addr[15: 8] <= s_axi_wdata[15: 8];
                        if (s_axi_wstrb[2]) r_src_addr[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) r_src_addr[31:24] <= s_axi_wdata[31:24];
                    end
                    ADDR_DST: begin
                        if (s_axi_wstrb[0]) r_dst_addr[ 7: 0] <= s_axi_wdata[ 7: 0];
                        if (s_axi_wstrb[1]) r_dst_addr[15: 8] <= s_axi_wdata[15: 8];
                        if (s_axi_wstrb[2]) r_dst_addr[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) r_dst_addr[31:24] <= s_axi_wdata[31:24];
                    end
                    ADDR_LEN: begin
                        if (s_axi_wstrb[0]) r_xfer_len[ 7: 0] <= s_axi_wdata[ 7: 0];
                        if (s_axi_wstrb[1]) r_xfer_len[15: 8] <= s_axi_wdata[15: 8];
                        if (s_axi_wstrb[2]) r_xfer_len[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) r_xfer_len[31:24] <= s_axi_wdata[31:24];
                    end
                    ADDR_CTRL: begin
                        if (s_axi_wstrb[0]) begin
                            r_start      <= s_axi_wdata[0];
                            r_irq_en     <= s_axi_wdata[1];
                            r_soft_reset <= s_axi_wdata[2];
                        end
                    end
                    ADDR_STATUS: begin
                        // Write-1-to-clear for DONE and ERROR bits
                        if (s_axi_wstrb[0]) begin
                            if (s_axi_wdata[1]) r_done  <= 1'b0;
                            if (s_axi_wdata[2]) r_error <= 1'b0;
                        end
                    end
                    default: ; // no-op
                endcase
            end
        end
    end

    // -------------------------------------------------------
    // Read FSM
    // -------------------------------------------------------
    localparam RD_IDLE = 2'd0;
    localparam RD_PIPE = 2'd1;
    localparam RD_DATA = 2'd2;

    reg [1:0]                   rd_state;
    reg [AXI_ADDR_WIDTH-1:0]   rd_addr;
    reg [AXI_ID_WIDTH-1:0]     rd_id;
    reg [7:0]                   rd_len_cnt;

    // Combinational read data mux
    reg [31:0] reg_rd_data;
    always @(*) begin
        case (rd_addr[5:0])
            ADDR_SRC:     reg_rd_data = r_src_addr;
            ADDR_DST:     reg_rd_data = r_dst_addr;
            ADDR_LEN:     reg_rd_data = r_xfer_len;
            ADDR_CTRL:    reg_rd_data = {29'b0, r_soft_reset, r_irq_en, 1'b0};
            ADDR_STATUS:  reg_rd_data = {29'b0, r_error, r_done, dma_busy};
            ADDR_VERSION: reg_rd_data = VERSION_VAL;
            default:      reg_rd_data = 32'h0;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state      <= RD_IDLE;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= {AXI_DATA_WIDTH{1'b0}};
            s_axi_rresp   <= 2'b00;
            s_axi_rlast   <= 1'b0;
            s_axi_rid     <= {AXI_ID_WIDTH{1'b0}};
            rd_addr       <= {AXI_ADDR_WIDTH{1'b0}};
            rd_id         <= {AXI_ID_WIDTH{1'b0}};
            rd_len_cnt    <= 8'd0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    s_axi_rvalid  <= 1'b0;
                    s_axi_arready <= 1'b1;
                    if (s_axi_arvalid && s_axi_arready) begin
                        rd_addr       <= s_axi_araddr;
                        rd_id         <= s_axi_arid;
                        rd_len_cnt    <= s_axi_arlen;
                        s_axi_arready <= 1'b0;
                        rd_state      <= RD_PIPE;
                    end
                end

                // Pipeline stage: rd_addr is now valid, read data from mux
                RD_PIPE: begin
                    s_axi_rdata  <= reg_rd_data;
                    s_axi_rresp  <= 2'b00;
                    s_axi_rid    <= rd_id;
                    s_axi_rlast  <= (rd_len_cnt == 8'd0);
                    s_axi_rvalid <= 1'b1;
                    rd_state     <= RD_DATA;
                end

                RD_DATA: begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        if (s_axi_rlast) begin
                            s_axi_rvalid <= 1'b0;
                            s_axi_rlast  <= 1'b0;
                            rd_state     <= RD_IDLE;
                        end else begin
                            rd_addr    <= rd_addr + (AXI_DATA_WIDTH / 8);
                            rd_len_cnt <= rd_len_cnt - 1'b1;
                            s_axi_rvalid <= 1'b0;
                            rd_state   <= RD_PIPE;
                        end
                    end
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

endmodule
