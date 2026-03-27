// ----------------------------------------------------------------------------
// Module: axi_dma_engine
// Description: DMA engine with AXI4 Master interface.
//              Reads data from source address and writes to destination
//              address using AXI4 burst transfers.
//              Internal synchronous FIFO buffers data between read and write.
//              Fully synchronous, single clock domain design.
// ----------------------------------------------------------------------------

module axi_dma_engine #(
    parameter AXI_DATA_WIDTH = 32,
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_ID_WIDTH   = 4,
    parameter AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8,
    parameter FIFO_DEPTH     = 256,
    parameter MAX_BURST_LEN  = 256  // AXI4 max = 256
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // -------------------------------------------------------
    // AXI4 Master Interface
    // -------------------------------------------------------
    // Write Address Channel
    output reg  [AXI_ID_WIDTH-1:0]      m_axi_awid,
    output reg  [AXI_ADDR_WIDTH-1:0]    m_axi_awaddr,
    output reg  [7:0]                   m_axi_awlen,
    output reg  [2:0]                   m_axi_awsize,
    output reg  [1:0]                   m_axi_awburst,
    output wire                         m_axi_awlock,
    output wire [3:0]                   m_axi_awcache,
    output wire [2:0]                   m_axi_awprot,
    output wire [3:0]                   m_axi_awqos,
    output reg                          m_axi_awvalid,
    input  wire                         m_axi_awready,

    // Write Data Channel
    output reg  [AXI_DATA_WIDTH-1:0]    m_axi_wdata,
    output reg  [AXI_STRB_WIDTH-1:0]    m_axi_wstrb,
    output reg                          m_axi_wlast,
    output reg                          m_axi_wvalid,
    input  wire                         m_axi_wready,

    // Write Response Channel
    input  wire [AXI_ID_WIDTH-1:0]      m_axi_bid,
    input  wire [1:0]                   m_axi_bresp,
    input  wire                         m_axi_bvalid,
    output reg                          m_axi_bready,

    // Read Address Channel
    output reg  [AXI_ID_WIDTH-1:0]      m_axi_arid,
    output reg  [AXI_ADDR_WIDTH-1:0]    m_axi_araddr,
    output reg  [7:0]                   m_axi_arlen,
    output reg  [2:0]                   m_axi_arsize,
    output reg  [1:0]                   m_axi_arburst,
    output wire                         m_axi_arlock,
    output wire [3:0]                   m_axi_arcache,
    output wire [2:0]                   m_axi_arprot,
    output wire [3:0]                   m_axi_arqos,
    output reg                          m_axi_arvalid,
    input  wire                         m_axi_arready,

    // Read Data Channel
    input  wire [AXI_ID_WIDTH-1:0]      m_axi_rid,
    input  wire [AXI_DATA_WIDTH-1:0]    m_axi_rdata,
    input  wire [1:0]                   m_axi_rresp,
    input  wire                         m_axi_rlast,
    input  wire                         m_axi_rvalid,
    output reg                          m_axi_rready,

    // -------------------------------------------------------
    // Control / Status from register block
    // -------------------------------------------------------
    input  wire [31:0]                  reg_src_addr,
    input  wire [31:0]                  reg_dst_addr,
    input  wire [31:0]                  reg_xfer_len,
    input  wire                         reg_start,
    input  wire                         reg_soft_reset,

    output wire                         dma_busy,
    output reg                          dma_done_pulse,
    output reg                          dma_error_pulse,
    output wire                         irq
);

    // -------------------------------------------------------
    // Constants for AXI4 signals
    // -------------------------------------------------------
    assign m_axi_awlock  = 1'b0;       // Normal access
    assign m_axi_awcache = 4'b0011;    // Normal non-cacheable bufferable
    assign m_axi_awprot  = 3'b000;     // Unprivileged, secure, data
    assign m_axi_awqos   = 4'b0000;

    assign m_axi_arlock  = 1'b0;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arqos   = 4'b0000;

    // AXI size: log2(data_width/8)
    localparam [2:0] AXI_SIZE = (AXI_DATA_WIDTH == 32)  ? 3'b010 :
                                (AXI_DATA_WIDTH == 64)  ? 3'b011 :
                                (AXI_DATA_WIDTH == 128) ? 3'b100 :
                                (AXI_DATA_WIDTH == 256) ? 3'b101 : 3'b010;

    localparam BYTES_PER_BEAT = AXI_DATA_WIDTH / 8;
    localparam FIFO_ADDR_W   = $clog2(FIFO_DEPTH);

    // -------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------
    localparam ST_IDLE    = 4'd0;
    localparam ST_CALC    = 4'd1;
    localparam ST_RD_REQ  = 4'd2;
    localparam ST_RD_DATA = 4'd3;
    localparam ST_WR_REQ  = 4'd4;
    localparam ST_WR_DATA = 4'd5;
    localparam ST_WR_RESP = 4'd6;
    localparam ST_DONE    = 4'd7;
    localparam ST_WR_LOAD = 4'd8;

    reg [3:0] state;

    // -------------------------------------------------------
    // Transfer tracking
    // -------------------------------------------------------
    reg [AXI_ADDR_WIDTH-1:0]  rd_addr;      // Current read address
    reg [AXI_ADDR_WIDTH-1:0]  wr_addr;      // Current write address
    reg [31:0]                total_beats;   // Total beats to transfer
    reg [31:0]                rd_beats_rem;  // Remaining read beats
    reg [31:0]                wr_beats_rem;  // Remaining write beats
    reg [7:0]                 cur_burst_len; // Current burst length - 1 (AXI encoding)
    reg [8:0]                 beat_cnt;      // Beat counter within a burst
    reg                       error_flag;

    assign dma_busy = (state != ST_IDLE);

    // IRQ output (directly active when done or error)
    assign irq = dma_done_pulse | dma_error_pulse;

    // -------------------------------------------------------
    // Internal FIFO
    // -------------------------------------------------------
    wire                       fifo_wr_en;
    wire [AXI_DATA_WIDTH-1:0]  fifo_wr_data;
    wire                       fifo_rd_en;
    wire [AXI_DATA_WIDTH-1:0]  fifo_rd_data;
    wire                       fifo_full;
    wire                       fifo_empty;
    wire [FIFO_ADDR_W:0]       fifo_count;

    sync_fifo #(
        .DATA_WIDTH (AXI_DATA_WIDTH),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) u_fifo (
        .clk        (clk),
        .rst_n      (rst_n),
        .wr_en      (fifo_wr_en),
        .wr_data    (fifo_wr_data),
        .rd_en      (fifo_rd_en),
        .rd_data    (fifo_rd_data),
        .full       (fifo_full),
        .empty      (fifo_empty),
        .data_count (fifo_count)
    );

    // FIFO write: from AXI read data channel
    assign fifo_wr_en   = (state == ST_RD_DATA) && m_axi_rvalid && m_axi_rready && !fifo_full;
    assign fifo_wr_data = m_axi_rdata;

    // FIFO read: to AXI write data channel
    assign fifo_rd_en   = (state == ST_WR_DATA) && m_axi_wvalid && m_axi_wready;

    // -------------------------------------------------------
    // Burst length calculation
    // -------------------------------------------------------
    // Calculate the number of beats for the next burst.
    // Cannot exceed MAX_BURST_LEN (256 for AXI4).
    // Cannot exceed remaining beats.
    // Cannot cross a 4KB address boundary.
    function [8:0] calc_burst_len;
        input [31:0] remaining;
        input [AXI_ADDR_WIDTH-1:0] addr;
        reg [31:0] max_by_remaining;
        reg [31:0] max_by_boundary;
        reg [31:0] beats_to_boundary;
        begin
            max_by_remaining = (remaining > MAX_BURST_LEN) ? MAX_BURST_LEN : remaining;
            // 4KB boundary: number of beats until next 4KB boundary
            beats_to_boundary = (32'h1000 - {20'b0, addr[11:0]}) / BYTES_PER_BEAT;
            if (beats_to_boundary == 0)
                beats_to_boundary = MAX_BURST_LEN;
            max_by_boundary = (beats_to_boundary > MAX_BURST_LEN) ? MAX_BURST_LEN : beats_to_boundary;
            calc_burst_len = (max_by_remaining < max_by_boundary) ?
                             max_by_remaining[8:0] : max_by_boundary[8:0];
        end
    endfunction

    // -------------------------------------------------------
    // Main state machine
    // -------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            rd_addr         <= {AXI_ADDR_WIDTH{1'b0}};
            wr_addr         <= {AXI_ADDR_WIDTH{1'b0}};
            total_beats     <= 32'd0;
            rd_beats_rem    <= 32'd0;
            wr_beats_rem    <= 32'd0;
            cur_burst_len   <= 8'd0;
            beat_cnt        <= 9'd0;
            error_flag      <= 1'b0;
            dma_done_pulse  <= 1'b0;
            dma_error_pulse <= 1'b0;

            // AXI Master Read Channel
            m_axi_arid      <= {AXI_ID_WIDTH{1'b0}};
            m_axi_araddr    <= {AXI_ADDR_WIDTH{1'b0}};
            m_axi_arlen     <= 8'd0;
            m_axi_arsize    <= 3'd0;
            m_axi_arburst   <= 2'b01; // INCR
            m_axi_arvalid   <= 1'b0;
            m_axi_rready    <= 1'b0;

            // AXI Master Write Channel
            m_axi_awid      <= {AXI_ID_WIDTH{1'b0}};
            m_axi_awaddr    <= {AXI_ADDR_WIDTH{1'b0}};
            m_axi_awlen     <= 8'd0;
            m_axi_awsize    <= 3'd0;
            m_axi_awburst   <= 2'b01; // INCR
            m_axi_awvalid   <= 1'b0;
            m_axi_wdata     <= {AXI_DATA_WIDTH{1'b0}};
            m_axi_wstrb     <= {AXI_STRB_WIDTH{1'b0}};
            m_axi_wlast     <= 1'b0;
            m_axi_wvalid    <= 1'b0;
            m_axi_bready    <= 1'b0;
        end else if (reg_soft_reset) begin
            state           <= ST_IDLE;
            m_axi_arvalid   <= 1'b0;
            m_axi_rready    <= 1'b0;
            m_axi_awvalid   <= 1'b0;
            m_axi_wvalid    <= 1'b0;
            m_axi_bready    <= 1'b0;
            dma_done_pulse  <= 1'b0;
            dma_error_pulse <= 1'b0;
        end else begin
            // Default: clear pulses
            dma_done_pulse  <= 1'b0;
            dma_error_pulse <= 1'b0;

            case (state)
                // ====================================
                // IDLE: Wait for start command
                // ====================================
                ST_IDLE: begin
                    if (reg_start && (reg_xfer_len != 32'd0)) begin
                        rd_addr      <= reg_src_addr;
                        wr_addr      <= reg_dst_addr;
                        total_beats  <= reg_xfer_len / BYTES_PER_BEAT;
                        rd_beats_rem <= reg_xfer_len / BYTES_PER_BEAT;
                        wr_beats_rem <= reg_xfer_len / BYTES_PER_BEAT;
                        error_flag   <= 1'b0;
                        state        <= ST_CALC;
                    end
                end

                // ====================================
                // CALC: Calculate burst parameters for read
                // ====================================
                ST_CALC: begin
                    if (rd_beats_rem > 0) begin
                        cur_burst_len <= calc_burst_len(rd_beats_rem, rd_addr) - 1'b1;
                        state         <= ST_RD_REQ;
                    end else if (wr_beats_rem > 0) begin
                        // All reads done, wait for writes to complete
                        cur_burst_len <= calc_burst_len(wr_beats_rem, wr_addr) - 1'b1;
                        state         <= ST_WR_REQ;
                    end else begin
                        state <= ST_DONE;
                    end
                end

                // ====================================
                // RD_REQ: Issue AXI4 read request
                // ====================================
                ST_RD_REQ: begin
                    m_axi_arid    <= {AXI_ID_WIDTH{1'b0}};
                    m_axi_araddr  <= rd_addr;
                    m_axi_arlen   <= cur_burst_len;
                    m_axi_arsize  <= AXI_SIZE;
                    m_axi_arburst <= 2'b01; // INCR
                    m_axi_arvalid <= 1'b1;

                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        beat_cnt      <= 9'd0;
                        state         <= ST_RD_DATA;
                    end
                end

                // ====================================
                // RD_DATA: Receive read data, push to FIFO
                // ====================================
                ST_RD_DATA: begin
                    m_axi_rready <= !fifo_full;

                    if (m_axi_rvalid && m_axi_rready && !fifo_full) begin
                        beat_cnt     <= beat_cnt + 1'b1;
                        rd_beats_rem <= rd_beats_rem - 1'b1;
                        rd_addr      <= rd_addr + BYTES_PER_BEAT;

                        // Check for read errors
                        if (m_axi_rresp[1]) begin
                            error_flag <= 1'b1;
                        end

                        if (m_axi_rlast) begin
                            m_axi_rready <= 1'b0;
                            // Now issue write for the data in FIFO
                            cur_burst_len <= beat_cnt; // Number of beats received - 1
                            state         <= ST_WR_REQ;
                        end
                    end
                end

                // ====================================
                // WR_REQ: Issue AXI4 write request
                // ====================================
                ST_WR_REQ: begin
                    m_axi_awid    <= {AXI_ID_WIDTH{1'b0}};
                    m_axi_awaddr  <= wr_addr;
                    m_axi_awlen   <= cur_burst_len;
                    m_axi_awsize  <= AXI_SIZE;
                    m_axi_awburst <= 2'b01; // INCR

                    if (!fifo_empty) begin
                        m_axi_awvalid <= 1'b1;
                    end

                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        beat_cnt      <= 9'd0;
                        // Start writing data
                        m_axi_wdata   <= fifo_rd_data;
                        m_axi_wstrb   <= {AXI_STRB_WIDTH{1'b1}};
                        m_axi_wlast   <= (cur_burst_len == 8'd0);
                        m_axi_wvalid  <= 1'b1;
                        state         <= ST_WR_DATA;
                    end
                end

                // ====================================
                // WR_DATA: Send write data from FIFO
                // ====================================
                ST_WR_DATA: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        beat_cnt     <= beat_cnt + 1'b1;
                        wr_beats_rem <= wr_beats_rem - 1'b1;
                        wr_addr      <= wr_addr + BYTES_PER_BEAT;

                        if (m_axi_wlast) begin
                            m_axi_wvalid <= 1'b0;
                            m_axi_wlast  <= 1'b0;
                            m_axi_bready <= 1'b1;
                            state        <= ST_WR_RESP;
                        end else begin
                            // Need to wait one cycle for FIFO rd_ptr to update
                            m_axi_wvalid <= 1'b0;
                            state        <= ST_WR_LOAD;
                        end
                    end
                end

                // ====================================
                // WR_LOAD: Load next write data from FIFO
                // (FIFO rd_ptr has been updated from previous pop)
                // ====================================
                ST_WR_LOAD: begin
                    m_axi_wdata  <= fifo_rd_data;
                    m_axi_wstrb  <= {AXI_STRB_WIDTH{1'b1}};
                    m_axi_wlast  <= (beat_cnt == {1'b0, cur_burst_len});
                    m_axi_wvalid <= 1'b1;
                    state        <= ST_WR_DATA;
                end

                // ====================================
                // WR_RESP: Wait for write response
                // ====================================
                ST_WR_RESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;

                        // Check write response
                        if (m_axi_bresp[1]) begin
                            error_flag <= 1'b1;
                        end

                        // Check if more data to transfer
                        state <= ST_CALC;
                    end
                end

                // ====================================
                // DONE: Transfer complete
                // ====================================
                ST_DONE: begin
                    if (error_flag)
                        dma_error_pulse <= 1'b1;
                    else
                        dma_done_pulse <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
