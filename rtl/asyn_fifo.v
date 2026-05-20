module ASYN_FIFO#( 
  parameter WDATA_WIDTH = 128,   
  parameter RDATA_WIDTH = 128, 
  parameter FIFO_DEPTH = 1024   //FIFO 深度，注：定义的是小位宽数据的深度
)(
 //写端口
  input wr_clk,    //写时钟
  input wr_rstn,   //写复位
  input wr_en,     //写使能
  input [WDATA_WIDTH - 1:0] din,  //写数据
 
  //读端口 
  input rd_clk,    //读时钟
  input rd_rstn,   //读复位
  input rd_en,     //读使能
  output reg [RDATA_WIDTH - 1:0] dout,  //读数据
 
  //满空
  output pre_empty,  //预读空
  output empty,      //读空
  output pre_full,   //预写满
  output full        //写满
);


localparam WR_BURST_LEN = (WDATA_WIDTH>RDATA_WIDTH) ? (WDATA_WIDTH/RDATA_WIDTH) : 1'b1; 
localparam RD_BURST_LEN = (RDATA_WIDTH>WDATA_WIDTH) ? (RDATA_WIDTH/WDATA_WIDTH) : 1'b1; 
localparam DATA_WIDTH = (WDATA_WIDTH>RDATA_WIDTH) ? RDATA_WIDTH : WDATA_WIDTH;


	//用二维数组实现 RAM
	reg [DATA_WIDTH - 1 : 0] fifo_buffer [FIFO_DEPTH - 1 : 0];
	reg [$clog2(FIFO_DEPTH) : 0]wr_ptr;//二进制 ram 写地址,位宽拓展一位
	reg [$clog2(FIFO_DEPTH) : 0]rd_ptr;//二进制 ram 读地址
	reg [$clog2(FIFO_DEPTH) : 0]wr_ptr_g;//处理后的二进制写地址指针
	reg [$clog2(FIFO_DEPTH) : 0]rd_ptr_g;//处理后的二进制读地址指针
	reg [$clog2(FIFO_DEPTH) : 0]wr_ptr_gray1;//格雷码写指针
	reg [$clog2(FIFO_DEPTH) : 0]rd_ptr_gray1;//格雷码读指针
	reg [$clog2(FIFO_DEPTH) : 0]rd_ptr_d0;//读地址同步寄存器 1 
	reg [$clog2(FIFO_DEPTH) : 0]rd_ptr_d1;//读地址同步寄存器 2 
	reg [$clog2(FIFO_DEPTH) : 0]wr_ptr_d0;//写地址同步寄存器 1 
	reg [$clog2(FIFO_DEPTH) : 0]wr_ptr_d1;//写地址同步寄存器 2 
	
	// ====================== wire define ========================== //
	wire [$clog2(FIFO_DEPTH) : 0]wr_ptr_gray0;//格雷码写地址指针
	wire [$clog2(FIFO_DEPTH) : 0]rd_ptr_gray0;//格雷码读地址指针
	wire [$clog2(FIFO_DEPTH) - 1 : 0]wr_ptr_ram;//写地址指针，未扩展的真实地址
	wire [$clog2(FIFO_DEPTH) - 1 : 0]rd_ptr_ram;//读地址指针
	
	//真实地址
	assign wr_ptr_ram = wr_ptr[$clog2(FIFO_DEPTH) - 1 : 0];
	assign rd_ptr_ram = rd_ptr[$clog2(FIFO_DEPTH) - 1 : 0];
	//二进制地址转格雷码
	assign wr_ptr_gray0 = wr_ptr_g^(wr_ptr_g >> 1);
	assign rd_ptr_gray0 = rd_ptr_g^(rd_ptr_g >> 1);
  
  
//写指针和写数据更新
integer w = 0; 
always@(posedge wr_clk or negedge wr_rstn)begin 
	if(!wr_rstn)begin 
		wr_ptr <= 0; 
		wr_ptr_g <= 0; 
	end
	else if(!full&&wr_en)begin
		wr_ptr <= wr_ptr + WR_BURST_LEN;
		wr_ptr_g <= (wr_ptr + WR_BURST_LEN)/RD_BURST_LEN*RD_BURST_LEN;
		for(w = 0;w<WR_BURST_LEN;w = w + 1)begin 
			fifo_buffer[wr_ptr_ram + w] <= din[w*DATA_WIDTH +: DATA_WIDTH];
		end
	end
	else begin 
		wr_ptr <= wr_ptr;
		wr_ptr_g <= wr_ptr_g; 
	end
end


//格雷码写指针先在写时钟域打一拍
always@(posedge wr_clk or negedge wr_rstn)begin 
	if(!wr_rstn)begin 
		wr_ptr_gray1 <= 0; 
	end
	else begin 
		wr_ptr_gray1 <= wr_ptr_gray0; 
	end
end


//写地址同步到读时钟域
always@(posedge rd_clk or negedge rd_rstn)begin 
	if(!rd_rstn)begin 
		wr_ptr_d0 <= 0; 
		wr_ptr_d1 <= 0; 
	end
	else begin 
		wr_ptr_d0 <= wr_ptr_gray1; 
		wr_ptr_d1 <= wr_ptr_d0; 
	end
end


//读指针和读数据更新
integer r = 0; 
always@(posedge rd_clk or negedge rd_rstn)begin 
	if(!rd_rstn)begin 
		rd_ptr <= 0; 
		rd_ptr_g <= 0; 
		dout <= 0; 
	end
	else if(!empty&&rd_en)begin 
		rd_ptr <= rd_ptr + RD_BURST_LEN;
		rd_ptr_g <= (rd_ptr + RD_BURST_LEN)/WR_BURST_LEN*WR_BURST_LEN;
		for(r = 0;r<RD_BURST_LEN;r = r + 1)begin 
			dout[r*DATA_WIDTH +: DATA_WIDTH] <= fifo_buffer[rd_ptr_ram + r];
		end
	end
	else begin 
		rd_ptr <= rd_ptr; 
		rd_ptr_g <= rd_ptr_g; 
		dout <= 0; 
	end
end


//格雷码读指针先在读时钟域打一拍
always@(posedge rd_clk or negedge rd_rstn)begin 
	if(!rd_rstn)begin 
		rd_ptr_gray1 <= 0; 
	end
	else begin 
		rd_ptr_gray1 <= rd_ptr_gray0; 
	end
end


//读地址同步到写时钟域
always@(posedge wr_clk or negedge wr_rstn)begin 
	if(!wr_rstn)begin 
		rd_ptr_d0 <= 0; 
		rd_ptr_d1 <= 0; 
	end
	else begin 
		rd_ptr_d0 <= rd_ptr_gray1; 
		rd_ptr_d1 <= rd_ptr_d0; 
	end
end


//读空判断
assign empty = (wr_ptr_d1 == rd_ptr_gray0)?1:0; 
//写满判断
assign full = ({~rd_ptr_d1[$clog2(FIFO_DEPTH):$clog2(FIFO_DEPTH) - 1],rd_ptr_d1[$clog2(FIFO_DEPTH) - 2:0]} == wr_ptr_gray0)?1:0; 


// 预读空判断：下一拍读指针追上写指针，或已经空了
wire [$clog2(FIFO_DEPTH) : 0] rd_ptr_next;
wire [$clog2(FIFO_DEPTH) : 0] rd_ptr_gray_next;
assign rd_ptr_next      = rd_ptr_g + RD_BURST_LEN; 
assign rd_ptr_gray_next = rd_ptr_next ^ (rd_ptr_next >> 1); 
assign pre_empty        = (wr_ptr_d1 == rd_ptr_gray_next) || empty;


// 预写满判断：下一拍写指针撞上读指针，或已经满了
wire [$clog2(FIFO_DEPTH) : 0] wr_ptr_next;
wire [$clog2(FIFO_DEPTH) : 0] wr_ptr_gray_next;
assign wr_ptr_next      = wr_ptr_g + WR_BURST_LEN; 
assign wr_ptr_gray_next = wr_ptr_next ^ (wr_ptr_next >> 1); 
assign pre_full         = ({~rd_ptr_d1[$clog2(FIFO_DEPTH):$clog2(FIFO_DEPTH)-1], rd_ptr_d1[$clog2(FIFO_DEPTH)-2:0]} == wr_ptr_gray_next) || full;

endmodule