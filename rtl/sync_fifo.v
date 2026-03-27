// ----------------------------------------------------------------------------
// Module: sync_fifo
// Description: Synchronous FIFO with configurable data width and depth.
//              Single clock domain, fully synchronous design.
// ----------------------------------------------------------------------------

module sync_fifo #(
    parameter DATA_WIDTH = 32,
    parameter FIFO_DEPTH = 256,
    parameter ADDR_WIDTH = $clog2(FIFO_DEPTH)
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // Write interface
    input  wire                    wr_en,
    input  wire  [DATA_WIDTH-1:0]  wr_data,

    // Read interface
    input  wire                    rd_en,
    output wire  [DATA_WIDTH-1:0]  rd_data,

    // Status
    output wire                    full,
    output wire                    empty,
    output wire  [ADDR_WIDTH:0]    data_count
);

    // -------------------------------------------------------
    // Internal signals
    // -------------------------------------------------------
    reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];
    reg [ADDR_WIDTH:0]   wr_ptr;
    reg [ADDR_WIDTH:0]   rd_ptr;

    wire                  wr_valid;
    wire                  rd_valid;

    // -------------------------------------------------------
    // Status flags
    // -------------------------------------------------------
    assign full       = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) &&
                        (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
    assign empty      = (wr_ptr == rd_ptr);
    assign data_count = wr_ptr - rd_ptr;

    assign wr_valid = wr_en && !full;
    assign rd_valid = rd_en && !empty;

    // -------------------------------------------------------
    // Write logic
    // -------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {(ADDR_WIDTH+1){1'b0}};
        end else if (wr_valid) begin
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    always @(posedge clk) begin
        if (wr_valid) begin
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
        end
    end

    // -------------------------------------------------------
    // Read logic
    // -------------------------------------------------------
    assign rd_data = mem[rd_ptr[ADDR_WIDTH-1:0]];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= {(ADDR_WIDTH+1){1'b0}};
        end else if (rd_valid) begin
            rd_ptr <= rd_ptr + 1'b1;
        end
    end

endmodule
