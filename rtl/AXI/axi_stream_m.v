module AXI_STREAM_M(  
  input wire clk,
  input wire rst_n,
  
  input  wire        wr_tready,
  output reg         wr_tvalid,
  output wire [127:0] wr_tdata,
  output wire [3:0]  wr_tkeep,
  output wire [3:0]  wr_tstrb,
  output reg         wr_tlast,
  output wire        wr_tid,
  output wire        wr_tdest,
  output wire        wr_tuser,
  
  input  wire        cpu_tpu_en,
  input  wire        cpu_sw_rst,
  input  wire        wr_start,
  input  wire [31:0] wr_out_len,

  output reg         fifo_out_re,      //FIFO rd_en
  input  wire 		   fifo_pre_empty,   //FIFO pre_empty
  input  wire [31:0] fifo_out_rdata    //FIFO dout
);


reg [31:0] data_cnt;

assign wr_tkeep = 4'hF;
assign wr_tstrb = 4'hF;
assign wr_tid   = 1'b0;
assign wr_tdest = 1'b0;
assign wr_tuser = 1'b0;
assign wr_tdata = fifo_out_rdata;


//fifo_out_re update
always @(posedge clk or negedge rst_n) begin
  if(rst_n == 1'b0)begin
    fifo_out_re <= 1'b0;
  end 
  else if(cpu_sw_rst == 1'b1 || cpu_tpu_en == 1'b0)begin
    fifo_out_re <= 1'b0;
  end 
  else if(wr_start == 1'b1)begin 
    fifo_out_re <= 1'b1;
  end
  else if(fifo_pre_empty || (data_cnt == wr_out_len - 1))begin
    fifo_out_re <= 1'b0;
  end
end


//wr_tvalid update
always @(posedge clk or negedge rst_n) begin
  if(rst_n == 1'b0)begin
    wr_tvalid <= 1'b0;    
  end 
  else if(cpu_sw_rst == 1'b1 || cpu_tpu_en == 1'b0)begin
    wr_tvalid <= 1'b0;    
  end 
  else begin    
    wr_tvalid <= fifo_out_re;
  end
end


//data_cnt update
always @(posedge clk or negedge rst_n) begin
  if(rst_n == 1'b0)begin
    data_cnt <= 32'b0;
  end 
  else if(cpu_sw_rst == 1'b1 || cpu_tpu_en == 1'b0)begin
    data_cnt <= 32'b0;
  end 
  else if(wr_start == 1'b1)begin 
    data_cnt <= 32'b0;
  end
  else if(fifo_out_re)begin
    data_cnt <= data_cnt + 1'b1;
  end
end


//wr_tlast update
always @(posedge clk or negedge rst_n) begin
  if(rst_n == 1'b0)begin 
    wr_tlast <= 1'b0;
  end 
  else if(cpu_sw_rst == 1'b1 || cpu_tpu_en == 1'b0)begin  
    wr_tlast <= 1'b0;
  end 
  else if((fifo_out_re == 1'b1) && (data_cnt == wr_out_len - 1))begin
    wr_tlast <= 1'b1;
  end 
  else begin
    wr_tlast <= 1'b0;
  end
end
endmodule