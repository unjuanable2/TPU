module asyn_FIFO#( 
  parameter WDATA_WIDTH = 128,   
  parameter RDATA_WIDTH = 128, 
  parameter FIFO_DEPTH = 1024 // FIFO 深度，注：定义的是小位宽数据的深度
)(
	// 写端口
	input wire wr_clk,  // 写时钟
	input wire wr_rstn, // 写复位
	input wire wr_en,   // 写使能
	input wire [WDATA_WIDTH - 1:0] wr_data, // 写数据

	// 读端口 
	input wire rd_clk,  // 读时钟
		// 两时钟频率不同且相位关系未知
	input wire rd_rstn, // 读复位
	input wire rd_en,   // 读使能
	output reg [RDATA_WIDTH - 1:0] rd_data,  // 读数据

	// 满空
	output wire pre_empty,// 预空
	output wire empty,    // 空
	output wire pre_full, // 预满
	output wire full      // 满
);

// 为了处理读写位宽不一致
localparam WR_BURST_LEN = (WDATA_WIDTH>RDATA_WIDTH) ? (WDATA_WIDTH / RDATA_WIDTH) : 1'b1; 
			// 写一次，需要占用几个小单元
localparam RD_BURST_LEN = (RDATA_WIDTH>WDATA_WIDTH) ? (RDATA_WIDTH / WDATA_WIDTH) : 1'b1; 
			// 读一次，需要取几个小单元
localparam DATA_WIDTH = (WDATA_WIDTH>RDATA_WIDTH) ? RDATA_WIDTH : WDATA_WIDTH;
			// 取读写宽度中较小的那个

///////////////////////////////////////////////////
// 中间变量声明
///////////////////////////////////////////////////

// 用二维数组实现 RAM
reg [DATA_WIDTH - 1 : 0] fifo_buffer [FIFO_DEPTH - 1 : 0];

// 写指针、读指针
reg [$clog2(FIFO_DEPTH) : 0] wr_ptr, rd_ptr; 
	// 位宽拓展一位

// 访问 RAM 只用低位 (真实地址)
wire [$clog2(FIFO_DEPTH) - 1 : 0] wr_ptr_ram, rd_ptr_ram;
	// 未扩展的真实地址
assign wr_ptr_ram = wr_ptr[$clog2(FIFO_DEPTH) - 1 : 0];
assign rd_ptr_ram = rd_ptr[$clog2(FIFO_DEPTH) - 1 : 0];

// 处理一下
reg [$clog2(FIFO_DEPTH) : 0] wr_ptr_g; // 向下取整到 RD_BURST_LEN 的倍数
reg [$clog2(FIFO_DEPTH) : 0] rd_ptr_g; 

// 处理后的二进制地址转格雷码
wire [$clog2(FIFO_DEPTH) : 0] wr_ptr_gray0, rd_ptr_gray0;

// [打拍] 格雷码指针在自己时钟域打一拍
reg [$clog2(FIFO_DEPTH) : 0] wr_ptr_gray1, rd_ptr_gray1;

// 格雷码指针同步到对方时钟域
reg [$clog2(FIFO_DEPTH) : 0] wr_ptr_gray_d0, wr_ptr_gray_d1;
reg [$clog2(FIFO_DEPTH) : 0] rd_ptr_gray_d0, rd_ptr_gray_d1;

///////////////////////////////////////////////////////////////////
// 写读指针更新逻辑
///////////////////////////////////////////////////////////////////
  
// 写指针和写数据更新
integer w = 0; 
always @(posedge wr_clk or negedge wr_rstn)begin 
	if (!wr_rstn)begin 
		wr_ptr <= 0; 
		wr_ptr_g <= 0; 
	end else if(!full && wr_en) begin // 写使能有效且 FIFO 未满
		wr_ptr <= wr_ptr + WR_BURST_LEN;
		wr_ptr_g <= (wr_ptr + WR_BURST_LEN) / RD_BURST_LEN * RD_BURST_LEN; // 向下取整到 RD_BURST_LEN 的倍数
		// e.g. 写端一次写 8-bit，读端一次读 32-bit
		// 则 DATA_WIDTH = 8, WR_BURST_LEN = 1, RD_BURST_LEN = 4
		// 写了 1 个小单元 -> 对读端来说还是 0 个完整数据
		// 写了 2 个小单元 -> 对读端来说还是 0 个完整数据
		// 写了 3 个小单元 -> 对读端来说还是 0 个完整数据
		// 写了 4 个小单元 -> 对读端来说有 1 个完整 32-bit 数据

		// 写数据到 FIFO
		for(w = 0; w < WR_BURST_LEN; w = w + 1)begin 
			fifo_buffer[wr_ptr_ram + w] <= wr_data[w*DATA_WIDTH +: DATA_WIDTH];
		end
	end else begin 
		wr_ptr <= wr_ptr;
		wr_ptr_g <= wr_ptr_g; 
	end
end

// 二进制地址转格雷码
assign wr_ptr_gray0 = wr_ptr_g^(wr_ptr_g >> 1);

// 格雷码写指针先在写时钟域打一拍
always @(posedge wr_clk or negedge wr_rstn)begin 
	if (!wr_rstn)begin 
		wr_ptr_gray1 <= 0; 
	end
	else begin 
		wr_ptr_gray1 <= wr_ptr_gray0; 
	end
end

// 写地址同步到读时钟域
always @(posedge rd_clk or negedge rd_rstn)begin 
	if(!rd_rstn)begin 
		wr_ptr_gray_d0 <= 0; 
		wr_ptr_gray_d1 <= 0; 
	end
	else begin 
		wr_ptr_gray_d0 <= wr_ptr_gray1; 
		wr_ptr_gray_d1 <= wr_ptr_gray_d0; 
	end
end


// 读指针和读数据更新
integer r = 0; 
always @(posedge rd_clk or negedge rd_rstn)begin 
	if (!rd_rstn) begin 
		// 读指针清零
		rd_ptr <= 0; 
		rd_ptr_g <= 0; 
		// 读数据清零
		rd_data <= 0; 
	end else if (!empty && rd_en) begin // 读使能有效且 FIFO 非空
		rd_ptr <= rd_ptr + RD_BURST_LEN;
		rd_ptr_g <= (rd_ptr + RD_BURST_LEN) / WR_BURST_LEN * WR_BURST_LEN; // 向下取整到 WR_BURST_LEN 的倍数

		// 从 FIFO buffer 中读数据到 rd_data
		for(r = 0;r < RD_BURST_LEN;r = r + 1)begin 
			rd_data[r*DATA_WIDTH +: DATA_WIDTH] <= fifo_buffer[rd_ptr_ram + r];
		end
	end else begin 
		rd_ptr <= rd_ptr; 
		rd_ptr_g <= rd_ptr_g; 
		// 读数据清零
		rd_data <= 0; 
	end
end

// 二进制地址转格雷码
assign rd_ptr_gray0 = rd_ptr_g^(rd_ptr_g >> 1);

// 格雷码读指针先在读时钟域打一拍
always@(posedge rd_clk or negedge rd_rstn)begin 
	if(!rd_rstn)begin 
		rd_ptr_gray1 <= 0; 
	end
	else begin 
		rd_ptr_gray1 <= rd_ptr_gray0; 
	end
end

// 读地址同步到写时钟域
always@(posedge wr_clk or negedge wr_rstn)begin 
	if(!wr_rstn)begin 
		rd_ptr_gray_d0 <= 0; 
		rd_ptr_gray_d1 <= 0; 
	end
	else begin 
		rd_ptr_gray_d0 <= rd_ptr_gray1; 
		rd_ptr_gray_d1 <= rd_ptr_gray_d0; 
	end
end

//////////////////////////////////////////////////////////////////
// 满空判断逻辑
//////////////////////////////////////////////////////////////////

// 读空判断: 同步过来的写指针 == 当前读指针
assign empty = (wr_ptr_gray_d1 == rd_ptr_gray0) ? 1 : 0; 

// 写满判断: 写指针 Gray == 同步过来的读指针 Gray 的最高两位取反，低位不变
assign full = ({~rd_ptr_gray_d1[$clog2(FIFO_DEPTH) : $clog2(FIFO_DEPTH) - 1], 
				rd_ptr_gray_d1[$clog2(FIFO_DEPTH) - 2:0]} == wr_ptr_gray0) ? 1 : 0; 

// 预读空判断：下一拍读指针追上写指针，或已经空了
wire [$clog2(FIFO_DEPTH) : 0] rd_ptr_next;
assign rd_ptr_next = rd_ptr_g + RD_BURST_LEN; 

wire [$clog2(FIFO_DEPTH) : 0] rd_ptr_next_gray;
assign rd_ptr_next_gray = rd_ptr_next ^ (rd_ptr_next >> 1); 

assign pre_empty = (wr_ptr_gray_d1 == rd_ptr_gray_next) || empty;

// 预写满判断：下一拍写指针撞上读指针，或已经满了
wire [$clog2(FIFO_DEPTH) : 0] wr_ptr_next;
assign wr_ptr_next = wr_ptr_g + WR_BURST_LEN; 

wire [$clog2(FIFO_DEPTH) : 0] wr_ptr_gray_next;
assign wr_ptr_gray_next = wr_ptr_next ^ (wr_ptr_next >> 1); 

assign pre_full = ({~rd_ptr_gray_d1[$clog2(FIFO_DEPTH) : $clog2(FIFO_DEPTH)-1], 
					rd_ptr_gray_d1[$clog2(FIFO_DEPTH) - 2 : 0]} == wr_ptr_gray_next) || full;

endmodule