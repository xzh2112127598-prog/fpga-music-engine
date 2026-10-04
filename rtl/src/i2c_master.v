`timescale 1ns/1ps
////////////////////////////////////////////////////////////////////////////////
// i2c_master.v —— I2C 主机（7 bit 地址，支持重复起始，突发读写最多 8 字节）
//
// 面向 MPU6050 / SPL06 / MPR121 / SSD1306 共用一条总线（地址互不冲突）。
// 典型事务：  [START][ADDR+W][REG][RESTART][ADDR+R][D0][D1]...[Dn][STOP]
//
// 使用方式：
//   1) 拉高 start 一个周期，同时给出 dev_addr / rw / reg_addr / data_wr / nbytes
//   2) busy 变高；事务结束 done 拉高一个周期
//   3) 读事务结果在 data_rd（第 1 个字节在最低 8 bit）
//   4) ack_err=1 表示从机无应答（接线/地址/上拉问题）
//
// SCL 由本模块产生，SDA 为开漏三态（外部必须接 4.7k 上拉）。
////////////////////////////////////////////////////////////////////////////////
module i2c_master #(
    parameter CLK_FREQ = 27_000_000,   // Tang Nano 20K 是 27MHz，不是 24MHz！
    parameter I2C_FREQ = 400_000       // 400kHz 快速模式
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- 事务级接口 ----
    input  wire        start,          // 1 周期脉冲：启动一次事务
    input  wire [6:0]  dev_addr,       // 7 bit 器件地址
    input  wire        rw,             // 0=写 1=读
    input  wire [7:0]  reg_addr,       // 寄存器地址（先写后读）
    input  wire [7:0]  data_wr,        // 写数据（nbytes=1 时有效）
    input  wire [3:0]  nbytes,         // 读写字节数 1..8
    output reg  [63:0] data_rd,        // 读到的数据，字节 0 在最低位
    output reg         done,           // 完成脉冲
    output reg         ack_err,        // 从机无应答
    output reg         busy,

    // ---- I2C 物理口 ----
    output wire        scl,
    inout  wire        sda
);

    // 一个 SCL 周期分 4 个相位，故分频系数 = CLK/(4*I2C_FREQ)
    localparam integer DIV = (CLK_FREQ / (4 * I2C_FREQ) > 1) ?
                             (CLK_FREQ / (4 * I2C_FREQ)) : 2;

    localparam S_IDLE   = 4'd0,
               S_START  = 4'd1,
               S_ADDR   = 4'd2,   // 发 器件地址+W
               S_AACK   = 4'd3,   // 等 ACK
               S_REG    = 4'd4,   // 发 寄存器地址
               S_RACK   = 4'd5,
               S_WR     = 4'd6,   // 发 写数据
               S_WACK   = 4'd7,
               S_RSTA   = 4'd8,   // 重复起始
               S_ADDRR  = 4'd9,   // 发 器件地址+R
               S_ARACK  = 4'd10,
               S_RD     = 4'd11,  // 收 读数据
               S_RACKB  = 4'd12,  // 主机应答（最后一字节 NACK）
               S_STOP   = 4'd13;

    reg [15:0] div_cnt;
    reg        tick;
    reg [1:0]  phase;
    reg [3:0]  state;
    reg [3:0]  nstate;          // ACK 之后要去的下一个状态
    reg [2:0]  bit_cnt;         // 7..0
    reg [7:0]  sh_reg;          // 移位发送寄存器
    reg [63:0] rd_sh;           // 移位接收寄存器
    reg [3:0]  nleft;           // 剩余字节数
    reg        sda_o, scl_o, sda_oe;
    reg        rw_r;
    reg [6:0]  addr_r;
    reg [7:0]  reg_r;
    reg [7:0]  wdata_r;
    reg [3:0]  nbytes_r;

    assign scl = scl_o;
    assign sda = sda_oe ? sda_o : 1'bz;   // 开漏：输出 0 或高阻（靠外部上拉）

    // ---- SCL 分频：产生 4 倍频 tick ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt <= 16'd0;
            tick    <= 1'b0;
        end else if (div_cnt == DIV - 1) begin
            div_cnt <= 16'd0;
            tick    <= 1'b1;
        end else begin
            div_cnt <= div_cnt + 16'd1;
            tick    <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) phase <= 2'd0;
        else if (tick) phase <= phase + 2'd1;
    end

    // ---- 主状态机 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; nstate <= S_IDLE;
            bit_cnt <= 3'd0; sh_reg <= 8'd0; rd_sh <= 64'd0; nleft <= 4'd0;
            sda_o <= 1'b1; scl_o <= 1'b1; sda_oe <= 1'b0;
            busy <= 1'b0; done <= 1'b0; ack_err <= 1'b0;
            data_rd <= 64'd0;
            rw_r <= 1'b0; addr_r <= 7'd0; reg_r <= 8'd0;
            wdata_r <= 8'd0; nbytes_r <= 4'd1;
        end else begin
            done <= 1'b0;

            if (state == S_IDLE) begin
                scl_o  <= 1'b1;
                sda_o  <= 1'b1;
                sda_oe <= 1'b0;
                if (start) begin
                    addr_r   <= dev_addr;
                    rw_r     <= rw;
                    reg_r    <= reg_addr;
                    wdata_r  <= data_wr;
                    nbytes_r <= (nbytes == 4'd0) ? 4'd1 : nbytes;
                    busy     <= 1'b1;
                    ack_err  <= 1'b0;
                    data_rd  <= 64'd0;
                    rd_sh    <= 64'd0;
                    state    <= S_START;
                    phase    <= 2'd0;
                end
            end else if (tick) begin
                case (state)

                // ---- 起始条件：SCL 高时 SDA 由 1 变 0 ----
                S_START: begin
                    case (phase)
                        2'd0: begin sda_oe <= 1'b1; sda_o <= 1'b1; scl_o <= 1'b1; end
                        2'd1: begin scl_o <= 1'b1; end
                        2'd2: begin sda_o <= 1'b0; end          // SDA 下降沿
                        2'd3: begin scl_o <= 1'b0;
                                   sh_reg  <= {addr_r, 1'b0};   // 地址+W
                                   bit_cnt <= 3'd7;
                                   state   <= S_ADDR; end
                    endcase
                end

                // ---- 重复起始（读事务前）----
                S_RSTA: begin
                    case (phase)
                        2'd0: begin sda_oe <= 1'b1; sda_o <= 1'b1; scl_o <= 1'b0; end
                        2'd1: begin scl_o <= 1'b1; end
                        2'd2: begin sda_o <= 1'b0; end
                        2'd3: begin scl_o <= 1'b0;
                                   sh_reg  <= {addr_r, 1'b1};   // 地址+R
                                   bit_cnt <= 3'd7;
                                   state   <= S_ADDRR; end
                    endcase
                end

                // ---- 发 8 bit（S_ADDR / S_REG / S_WR / S_ADDRR 共用时序）----
                S_ADDR, S_ADDRR, S_REG, S_WR: begin
                    case (phase)
                        2'd0: begin sda_oe <= 1'b1; sda_o <= sh_reg[7]; scl_o <= 1'b0; end
                        2'd1: begin scl_o <= 1'b1; end
                        2'd2: begin sh_reg <= {sh_reg[6:0], 1'b0};
                                   if (bit_cnt == 3'd0) begin
                                       sda_oe <= 1'b0;          // 释放 SDA 准备收 ACK
                                       case (state)
                                           S_ADDR:  begin state <= S_AACK;  nstate <= S_REG;  end
                                           S_ADDRR: begin state <= S_ARACK; nstate <= S_RD;   end
                                           S_REG:   begin state <= S_RACK;
                                                          nstate <= rw_r ? S_RSTA : S_WR; end
                                           S_WR:    begin state <= S_WACK;  nstate <= S_STOP; end
                                           default: begin state <= S_STOP; end
                                       endcase
                                   end else bit_cnt <= bit_cnt - 3'd1;
                              end
                        2'd3: begin scl_o <= 1'b0; end
                    endcase
                end

                // ---- 等 ACK（第 9 个时钟，SCL 高时采样 SDA，低电平=应答）----
                S_AACK, S_RACK, S_WACK, S_ARACK: begin
                    case (phase)
                        2'd0: begin sda_oe <= 1'b0; scl_o <= 1'b0; end
                        2'd1: begin scl_o <= 1'b1; end
                        2'd2: begin
                                  if (sda == 1'b1) begin        // NACK
                                      ack_err <= 1'b1;
                                      state   <= S_STOP;
                                  end else begin
                                      if (nstate == S_WR) begin
                                          sh_reg  <= wdata_r;
                                          bit_cnt <= 3'd7;
                                      end else if (nstate == S_REG) begin
                                          sh_reg  <= reg_r;
                                          bit_cnt <= 3'd7;
                                      end else if (nstate == S_RD) begin
                                          nleft   <= nbytes_r;
                                          bit_cnt <= 3'd7;
                                      end
                                      state <= nstate;
                                  end
                              end
                        2'd3: begin scl_o <= 1'b0; end
                    endcase
                end

                // ---- 收 8 bit ----
                S_RD: begin
                    case (phase)
                        2'd0: begin sda_oe <= 1'b0; scl_o <= 1'b0; end
                        2'd1: begin scl_o <= 1'b1; end
                        2'd2: begin
                                  rd_sh <= {rd_sh[62:0], sda};
                                  if (bit_cnt == 3'd0) begin
                                      state <= S_RACKB;
                                  end else bit_cnt <= bit_cnt - 3'd1;
                              end
                        2'd3: begin scl_o <= 1'b0; end
                    endcase
                end

                // ---- 主机应答：还有字节就 ACK(0)，最后一个字节 NACK(1) ----
                S_RACKB: begin
                    case (phase)
                        2'd0: begin sda_oe <= 1'b1; sda_o <= (nleft > 4'd1) ? 1'b0 : 1'b1;
                                   scl_o <= 1'b0; end
                        2'd1: begin scl_o <= 1'b1; end
                        2'd2: begin
                                  if (nleft > 4'd1) begin
                                      nleft  <= nleft - 4'd1;
                                      bit_cnt <= 3'd7;
                                      state  <= S_RD;
                                  end else begin
                                      state <= S_STOP;
                                  end
                              end
                        2'd3: begin scl_o <= 1'b0; end
                    endcase
                end

                // ---- 停止条件：SCL 高时 SDA 由 0 变 1 ----
                S_STOP: begin
                    case (phase)
                        2'd0: begin sda_oe <= 1'b1; sda_o <= 1'b0; scl_o <= 1'b0; end
                        2'd1: begin scl_o <= 1'b1; end
                        2'd2: begin sda_o <= 1'b1; end          // SDA 上升沿
                        2'd3: begin
                                  scl_o  <= 1'b1;
                                  sda_oe <= 1'b0;
                                  data_rd <= rd_sh;
                                  done   <= 1'b1;
                                  busy   <= 1'b0;
                                  state  <= S_IDLE;
                              end
                    endcase
                end

                default: state <= S_IDLE;
                endcase
            end
        end
    end

endmodule
