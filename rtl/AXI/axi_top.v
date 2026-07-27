module AXI_TOP(
  input wire clk,
  input wire rst_n,
  
  //AXI master  
  input  wire        wr_tready,
  output wire        wr_tvalid,
  output wire [31:0] wr_tdata,
  output wire [3:0]  wr_tkeep,
  output wire [3:0]  wr_tstrb,
  output wire        wr_tlast,
  output wire        wr_tid,
  output wire        wr_tdest,
  output wire        wr_tuser,
  
  //AXI slave  
  output wire        rd_tready,
  input  wire        rd_tvalid,
  input  wire [31:0] rd_tdata,
  input  wire [3:0]  rd_tkeep,
  input  wire [3:0]  rd_tstrb,
  input  wire        rd_tlast,
  input  wire        rd_tid,
  input  wire        rd_tdest,
  input  wire        rd_tuser,
  
  //CTRL interface
  input  wire        cpu_tpu_en,
  input  wire        cpu_sw_rst,
  input  wire        rd_start,
  input  wire        wr_start,
  input  wire [31:0] wr_out_len,
  
  //FIFO interface
  output wire        fifo_in_we,
  input  wire        fifo_pre_full,
  output wire [31:0] fifo_in_wdata,
  output wire        fifo_out_re,
  input  wire        fifo_pre_empty,
  input  wire [31:0] fifo_out_rdata
);


AXI_STREAM_M write(
  .clk            (clk),
  .rst_n          (rst_n),
  
  .wr_tready      (wr_tready),      
  .wr_tvalid      (wr_tvalid),     
  .wr_tdata       (wr_tdata),        
  .wr_tkeep       (wr_tkeep),      
  .wr_tstrb       (wr_tstrb),       
  .wr_tlast       (wr_tlast),       
  .wr_tid         (wr_tid),         
  .wr_tdest       (wr_tdest),      
  .wr_tuser       (wr_tuser),       

  .cpu_tpu_en     (cpu_tpu_en),    
  .cpu_sw_rst     (cpu_sw_rst),     
  .wr_start       (wr_start),       
  .wr_out_len     (wr_out_len),      

  .fifo_out_re    (fifo_out_re),     
  .fifo_pre_empty (fifo_pre_empty),   
  .fifo_out_rdata (fifo_out_rdata)   
);


AXI_STREAM_S read(
  .clk           (clk),
  .rst_n         (rst_n),

  .rd_tready     (rd_tready),    
  .rd_tvalid     (rd_tvalid),   
  .rd_tdata      (rd_tdata),    
  .rd_tkeep      (rd_tkeep),    
  .rd_tstrb      (rd_tstrb),    
  .rd_tlast      (rd_tlast),    
  .rd_tid        (rd_tid),      
  .rd_tdest      (rd_tdest),    
  .rd_tuser      (rd_tuser),    
  
  .cpu_tpu_en    (cpu_tpu_en),    
  .cpu_sw_rst    (cpu_sw_rst),   
  .rd_start      (rd_start),      

  .fifo_in_we    (fifo_in_we),     
  .fifo_pre_full (fifo_pre_full),   
  .fifo_in_wdata (fifo_in_wdata)   
);

endmodule
