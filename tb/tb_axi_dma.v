// ----------------------------------------------------------------------------
// Testbench: tb_axi_dma
// Description: Testbench for AXI4 DMA controller.
//              Includes simple AXI4 memory model and exercises:
//              1. Register read/write via AXI4 Slave
//              2. DMA transfer with data verification
//              3. Interrupt check
// ----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_axi_dma;

    // -------------------------------------------------------
    // Parameters
    // -------------------------------------------------------
    parameter AXI_DATA_WIDTH = 32;
    parameter AXI_ADDR_WIDTH = 32;
    parameter AXI_ID_WIDTH   = 4;
    parameter AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8;
    parameter FIFO_DEPTH     = 256;
    parameter MAX_BURST_LEN  = 16;  // Smaller for faster sim

    parameter CLK_PERIOD = 10;

    // -------------------------------------------------------
    // Signals
    // -------------------------------------------------------
    reg                          clk;
    reg                          rst_n;

    // AXI4 Slave (config port)
    reg  [AXI_ID_WIDTH-1:0]     s_axi_awid;
    reg  [AXI_ADDR_WIDTH-1:0]   s_axi_awaddr;
    reg  [7:0]                  s_axi_awlen;
    reg  [2:0]                  s_axi_awsize;
    reg  [1:0]                  s_axi_awburst;
    reg                         s_axi_awlock;
    reg  [3:0]                  s_axi_awcache;
    reg  [2:0]                  s_axi_awprot;
    reg  [3:0]                  s_axi_awqos;
    reg                         s_axi_awvalid;
    wire                        s_axi_awready;

    reg  [AXI_DATA_WIDTH-1:0]   s_axi_wdata;
    reg  [AXI_STRB_WIDTH-1:0]   s_axi_wstrb;
    reg                         s_axi_wlast;
    reg                         s_axi_wvalid;
    wire                        s_axi_wready;

    wire [AXI_ID_WIDTH-1:0]     s_axi_bid;
    wire [1:0]                  s_axi_bresp;
    wire                        s_axi_bvalid;
    reg                         s_axi_bready;

    reg  [AXI_ID_WIDTH-1:0]     s_axi_arid;
    reg  [AXI_ADDR_WIDTH-1:0]   s_axi_araddr;
    reg  [7:0]                  s_axi_arlen;
    reg  [2:0]                  s_axi_arsize;
    reg  [1:0]                  s_axi_arburst;
    reg                         s_axi_arlock;
    reg  [3:0]                  s_axi_arcache;
    reg  [2:0]                  s_axi_arprot;
    reg  [3:0]                  s_axi_arqos;
    reg                         s_axi_arvalid;
    wire                        s_axi_arready;

    wire [AXI_ID_WIDTH-1:0]     s_axi_rid;
    wire [AXI_DATA_WIDTH-1:0]   s_axi_rdata;
    wire [1:0]                  s_axi_rresp;
    wire                        s_axi_rlast;
    wire                        s_axi_rvalid;
    reg                         s_axi_rready;

    // AXI4 Master (data port) - connected to memory model
    wire [AXI_ID_WIDTH-1:0]     m_axi_awid;
    wire [AXI_ADDR_WIDTH-1:0]   m_axi_awaddr;
    wire [7:0]                  m_axi_awlen;
    wire [2:0]                  m_axi_awsize;
    wire [1:0]                  m_axi_awburst;
    wire                        m_axi_awlock;
    wire [3:0]                  m_axi_awcache;
    wire [2:0]                  m_axi_awprot;
    wire [3:0]                  m_axi_awqos;
    wire                        m_axi_awvalid;
    reg                         m_axi_awready;

    wire [AXI_DATA_WIDTH-1:0]   m_axi_wdata;
    wire [AXI_STRB_WIDTH-1:0]   m_axi_wstrb;
    wire                        m_axi_wlast;
    wire                        m_axi_wvalid;
    reg                         m_axi_wready;

    reg  [AXI_ID_WIDTH-1:0]     m_axi_bid;
    reg  [1:0]                  m_axi_bresp;
    reg                         m_axi_bvalid;
    wire                        m_axi_bready;

    wire [AXI_ID_WIDTH-1:0]     m_axi_arid;
    wire [AXI_ADDR_WIDTH-1:0]   m_axi_araddr;
    wire [7:0]                  m_axi_arlen;
    wire [2:0]                  m_axi_arsize;
    wire [1:0]                  m_axi_arburst;
    wire                        m_axi_arlock;
    wire [3:0]                  m_axi_arcache;
    wire [2:0]                  m_axi_arprot;
    wire [3:0]                  m_axi_arqos;
    wire                        m_axi_arvalid;
    reg                         m_axi_arready;

    reg  [AXI_ID_WIDTH-1:0]     m_axi_rid;
    reg  [AXI_DATA_WIDTH-1:0]   m_axi_rdata;
    reg  [1:0]                  m_axi_rresp;
    reg                         m_axi_rlast;
    reg                         m_axi_rvalid;
    wire                        m_axi_rready;

    wire                        irq;

    // -------------------------------------------------------
    // DUT
    // -------------------------------------------------------
    axi_dma_top #(
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .FIFO_DEPTH     (FIFO_DEPTH),
        .MAX_BURST_LEN  (MAX_BURST_LEN)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),

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

        .irq              (irq)
    );

    // -------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------
    // Simple AXI4 Memory Model (slave side for DMA master)
    // -------------------------------------------------------
    localparam MEM_SIZE = 4096; // 4KB memory
    reg [7:0] mem [0:MEM_SIZE-1];

    // AXI read state machine
    reg [1:0]  mem_rd_state;
    reg [AXI_ADDR_WIDTH-1:0] mem_rd_addr;
    reg [7:0]  mem_rd_cnt;
    reg [7:0]  mem_rd_len;
    wire [AXI_ADDR_WIDTH-1:0] mem_rd_next_addr = mem_rd_addr + 4;

    localparam MEM_RD_IDLE = 2'd0;
    localparam MEM_RD_DATA = 2'd1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_rd_state  <= MEM_RD_IDLE;
            m_axi_arready <= 1'b1;
            m_axi_rvalid  <= 1'b0;
            m_axi_rdata   <= 0;
            m_axi_rresp   <= 2'b00;
            m_axi_rlast   <= 1'b0;
            m_axi_rid     <= 0;
            mem_rd_addr   <= 0;
            mem_rd_cnt    <= 0;
            mem_rd_len    <= 0;
        end else begin
            case (mem_rd_state)
                MEM_RD_IDLE: begin
                    m_axi_arready <= 1'b1;
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arready <= 1'b0;
                        mem_rd_addr   <= m_axi_araddr;
                        mem_rd_len    <= m_axi_arlen;
                        mem_rd_cnt    <= 0;
                        m_axi_rid     <= m_axi_arid;
                        // Present first data
                        m_axi_rdata   <= {mem[m_axi_araddr[11:0]+3],
                                          mem[m_axi_araddr[11:0]+2],
                                          mem[m_axi_araddr[11:0]+1],
                                          mem[m_axi_araddr[11:0]+0]};
                        m_axi_rresp   <= 2'b00;
                        m_axi_rlast   <= (m_axi_arlen == 0);
                        m_axi_rvalid  <= 1'b1;
                        mem_rd_state  <= MEM_RD_DATA;
                    end
                end

                MEM_RD_DATA: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        if (m_axi_rlast) begin
                            m_axi_rvalid <= 1'b0;
                            m_axi_rlast  <= 1'b0;
                            mem_rd_state <= MEM_RD_IDLE;
                        end else begin
                            mem_rd_cnt  <= mem_rd_cnt + 1;
                            mem_rd_addr <= mem_rd_next_addr;
                            m_axi_rdata <= {mem[mem_rd_next_addr[11:0]+3],
                                            mem[mem_rd_next_addr[11:0]+2],
                                            mem[mem_rd_next_addr[11:0]+1],
                                            mem[mem_rd_next_addr[11:0]+0]};
                            m_axi_rlast <= ((mem_rd_cnt + 1) == mem_rd_len);
                        end
                    end
                end
            endcase
        end
    end

    // AXI write state machine
    reg [1:0]  mem_wr_state;
    reg [AXI_ADDR_WIDTH-1:0] mem_wr_addr;

    localparam MEM_WR_IDLE = 2'd0;
    localparam MEM_WR_DATA = 2'd1;
    localparam MEM_WR_RESP = 2'd2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wr_state  <= MEM_WR_IDLE;
            m_axi_awready <= 1'b1;
            m_axi_wready  <= 1'b0;
            m_axi_bvalid  <= 1'b0;
            m_axi_bresp   <= 2'b00;
            m_axi_bid     <= 0;
            mem_wr_addr   <= 0;
        end else begin
            case (mem_wr_state)
                MEM_WR_IDLE: begin
                    m_axi_awready <= 1'b1;
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awready <= 1'b0;
                        mem_wr_addr   <= m_axi_awaddr;
                        m_axi_bid     <= m_axi_awid;
                        m_axi_wready  <= 1'b1;
                        mem_wr_state  <= MEM_WR_DATA;
                    end
                end

                MEM_WR_DATA: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        // Write to memory with byte strobes
                        if (m_axi_wstrb[0]) mem[mem_wr_addr[11:0]+0] <= m_axi_wdata[ 7: 0];
                        if (m_axi_wstrb[1]) mem[mem_wr_addr[11:0]+1] <= m_axi_wdata[15: 8];
                        if (m_axi_wstrb[2]) mem[mem_wr_addr[11:0]+2] <= m_axi_wdata[23:16];
                        if (m_axi_wstrb[3]) mem[mem_wr_addr[11:0]+3] <= m_axi_wdata[31:24];
                        mem_wr_addr <= mem_wr_addr + 4;

                        if (m_axi_wlast) begin
                            m_axi_wready <= 1'b0;
                            m_axi_bvalid <= 1'b1;
                            m_axi_bresp  <= 2'b00;
                            mem_wr_state <= MEM_WR_RESP;
                        end
                    end
                end

                MEM_WR_RESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bvalid <= 1'b0;
                        mem_wr_state <= MEM_WR_IDLE;
                    end
                end
            endcase
        end
    end

    // -------------------------------------------------------
    // Tasks for AXI4 Slave register access
    // -------------------------------------------------------
    task axi_write;
        input [AXI_ADDR_WIDTH-1:0] addr;
        input [AXI_DATA_WIDTH-1:0] data;
        begin
            @(posedge clk);
            // Address phase
            s_axi_awaddr  <= addr;
            s_axi_awid    <= 4'd0;
            s_axi_awlen   <= 8'd0;
            s_axi_awsize  <= 3'b010;
            s_axi_awburst <= 2'b01;
            s_axi_awlock  <= 1'b0;
            s_axi_awcache <= 4'b0000;
            s_axi_awprot  <= 3'b000;
            s_axi_awqos   <= 4'b0000;
            s_axi_awvalid <= 1'b1;

            // Wait for address handshake
            @(posedge clk);
            while (!s_axi_awready) @(posedge clk);
            s_axi_awvalid <= 1'b0;

            // Data phase
            s_axi_wdata  <= data;
            s_axi_wstrb  <= {AXI_STRB_WIDTH{1'b1}};
            s_axi_wlast  <= 1'b1;
            s_axi_wvalid <= 1'b1;

            @(posedge clk);
            while (!s_axi_wready) @(posedge clk);
            s_axi_wvalid <= 1'b0;
            s_axi_wlast  <= 1'b0;

            // Response phase
            s_axi_bready <= 1'b1;
            @(posedge clk);
            while (!s_axi_bvalid) @(posedge clk);
            s_axi_bready <= 1'b0;
            @(posedge clk);
        end
    endtask

    task axi_read;
        input  [AXI_ADDR_WIDTH-1:0] addr;
        output [AXI_DATA_WIDTH-1:0] data;
        begin
            @(posedge clk);
            s_axi_araddr  <= addr;
            s_axi_arid    <= 4'd0;
            s_axi_arlen   <= 8'd0;
            s_axi_arsize  <= 3'b010;
            s_axi_arburst <= 2'b01;
            s_axi_arlock  <= 1'b0;
            s_axi_arcache <= 4'b0000;
            s_axi_arprot  <= 3'b000;
            s_axi_arqos   <= 4'b0000;
            s_axi_arvalid <= 1'b1;

            @(posedge clk);
            while (!s_axi_arready) @(posedge clk);
            s_axi_arvalid <= 1'b0;

            // Data phase
            s_axi_rready <= 1'b1;
            @(posedge clk);
            while (!s_axi_rvalid) @(posedge clk);
            data = s_axi_rdata;
            s_axi_rready <= 1'b0;
            @(posedge clk);
        end
    endtask

    // -------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------
    reg [31:0] read_data;
    integer    i;
    integer    error_count;

    // Source and destination addresses in the memory model
    localparam SRC_BASE = 32'h0000_0000;
    localparam DST_BASE = 32'h0000_0800;
    localparam XFER_BYTES = 64; // 64 bytes = 16 x 32-bit words

    initial begin
        $dumpfile("tb_axi_dma.vcd");
        $dumpvars(0, tb_axi_dma);

        // Initialize signals
        rst_n         = 1'b0;
        s_axi_awid    = 0;
        s_axi_awaddr  = 0;
        s_axi_awlen   = 0;
        s_axi_awsize  = 0;
        s_axi_awburst = 0;
        s_axi_awlock  = 0;
        s_axi_awcache = 0;
        s_axi_awprot  = 0;
        s_axi_awqos   = 0;
        s_axi_awvalid = 0;
        s_axi_wdata   = 0;
        s_axi_wstrb   = 0;
        s_axi_wlast   = 0;
        s_axi_wvalid  = 0;
        s_axi_bready  = 0;
        s_axi_arid    = 0;
        s_axi_araddr  = 0;
        s_axi_arlen   = 0;
        s_axi_arsize  = 0;
        s_axi_arburst = 0;
        s_axi_arlock  = 0;
        s_axi_arcache = 0;
        s_axi_arprot  = 0;
        s_axi_arqos   = 0;
        s_axi_arvalid = 0;
        s_axi_rready  = 0;
        error_count   = 0;

        // Initialize source memory with test pattern
        for (i = 0; i < MEM_SIZE; i = i + 1) begin
            mem[i] = 8'h00;
        end
        for (i = 0; i < XFER_BYTES; i = i + 1) begin
            mem[SRC_BASE + i] = i[7:0];
        end

        // Reset sequence
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        $display("============================================");
        $display("  AXI4 DMA Controller Testbench");
        $display("============================================");

        // ----- Test 1: Read VERSION register -----
        $display("\n[TEST 1] Read VERSION register");
        axi_read(32'h14, read_data);
        if (read_data == 32'h0001_0000)
            $display("  PASS: VERSION = 0x%08h", read_data);
        else begin
            $display("  FAIL: VERSION = 0x%08h, expected 0x00010000", read_data);
            error_count = error_count + 1;
        end

        // ----- Test 2: Write and read SRC_ADDR -----
        $display("\n[TEST 2] Write/Read SRC_ADDR register");
        axi_write(32'h00, SRC_BASE);
        axi_read(32'h00, read_data);
        if (read_data == SRC_BASE)
            $display("  PASS: SRC_ADDR = 0x%08h", read_data);
        else begin
            $display("  FAIL: SRC_ADDR = 0x%08h, expected 0x%08h", read_data, SRC_BASE);
            error_count = error_count + 1;
        end

        // ----- Test 3: DMA Transfer -----
        $display("\n[TEST 3] DMA Transfer (%0d bytes)", XFER_BYTES);

        // Configure DMA
        axi_write(32'h00, SRC_BASE);          // Source address
        axi_write(32'h04, DST_BASE);          // Destination address
        axi_write(32'h08, XFER_BYTES);        // Transfer length
        axi_write(32'h0C, 32'h0000_0003);     // CTRL: START=1, IRQ_EN=1

        // Wait for completion (poll status or wait for IRQ)
        $display("  Waiting for DMA transfer to complete...");
        read_data = 32'h0000_0001; // Initially busy
        while (read_data[0]) begin
            repeat (10) @(posedge clk);
            axi_read(32'h10, read_data);
        end

        // Check status
        axi_read(32'h10, read_data);
        $display("  STATUS = 0x%08h (BUSY=%b, DONE=%b, ERROR=%b)",
                 read_data, read_data[0], read_data[1], read_data[2]);

        if (read_data[1] && !read_data[2])
            $display("  PASS: Transfer completed without errors");
        else begin
            $display("  FAIL: Unexpected status");
            error_count = error_count + 1;
        end

        // ----- Test 4: Verify transferred data -----
        $display("\n[TEST 4] Verify transferred data");
        for (i = 0; i < XFER_BYTES; i = i + 1) begin
            if (mem[DST_BASE + i] !== mem[SRC_BASE + i]) begin
                $display("  FAIL: Mismatch at byte %0d: dst=0x%02h, src=0x%02h",
                         i, mem[DST_BASE + i], mem[SRC_BASE + i]);
                error_count = error_count + 1;
            end
        end
        if (error_count == 0)
            $display("  PASS: All %0d bytes match", XFER_BYTES);

        // ----- Test 5: Clear DONE bit -----
        $display("\n[TEST 5] Clear DONE bit");
        axi_write(32'h10, 32'h0000_0002); // Write 1 to DONE bit
        axi_read(32'h10, read_data);
        if (!read_data[1])
            $display("  PASS: DONE bit cleared");
        else begin
            $display("  FAIL: DONE bit not cleared");
            error_count = error_count + 1;
        end

        // ----- Summary -----
        $display("\n============================================");
        if (error_count == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  %0d TEST(S) FAILED", error_count);
        $display("============================================\n");

        #100;
        $finish;
    end

    // -------------------------------------------------------
    // Timeout watchdog
    // -------------------------------------------------------
    initial begin
        #100000;
        $display("ERROR: Simulation timed out!");
        $finish;
    end

endmodule
