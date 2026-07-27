module AXI_STREAM_S( 
  input wire clk,
  input wire rst_n,

  output wire        rd_tready,
  input  wire        rd_tvalid,
  input  wire [31:0] rd_tdata,
  input  wire [3:0]  rd_tkeep,
  input  wire [3:0]  rd_tstrb,
  input  wire        rd_tlast,
  input  wire        rd_tid,
  input  wire        rd_tdest,
  input  wire        rd_tuser,

  input  wire        cpu_tpu_en,
  input  wire        cpu_sw_rst,
  input  wire        rd_start,

  output reg         fifo_in_we,      //FIFO wr_en
  input  wire        fifo_pre_full,   //FIFO pre_full
  output reg  [31:0] fifo_in_wdata    //FIFO din
);

reg rd_active;

assign rd_tready = cpu_tpu_en && !cpu_sw_rst && !fifo_pre_full && (rd_start || rd_active); 


//rd_active update
always @(posedge clk or negedge rst_n) begin
  if(rst_n == 1'b0)begin
    rd_active <= 1'b0;
  end 
  else if(cpu_sw_rst == 1'b1 || cpu_tpu_en == 1'b0)begin
    rd_active <= 1'b0;
  end 
  else if(rd_tlast && rd_tvalid && rd_tready)begin
    rd_active <= 1'b0;
  end
  else if(rd_start == 1'b1)begin 
    rd_active <= 1'b1;
  end
end


//fifo_in_we update
always @(posedge clk or negedge rst_n) begin
  if(rst_n == 1'b0)begin
    fifo_in_we <= 1'b0;
  end 
  else if(cpu_sw_rst == 1'b1 || cpu_tpu_en == 1'b0)begin
    fifo_in_we <= 1'b0;
  end 
  else begin 
    fifo_in_we <= rd_tready && rd_tvalid;
  end
end

//fifo_in_wdata update
always @(posedge clk or negedge rst_n) begin
  if(rst_n == 1'b0)begin
    fifo_in_wdata <= 1'b0;
  end 
  else if(cpu_sw_rst == 1'b1 || cpu_tpu_en == 1'b0)begin
    fifo_in_wdata <= 1'b0;
  end 
  else if(rd_tready && rd_tvalid) begin 
    fifo_in_wdata <= rd_tdata;
  end
end
endmodule