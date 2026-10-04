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
// SCL 由本模块产生，SDA 为开漏（只拉低、不推高；外部必须接 4.7k 上拉）。
//
// ⚠️ 四个曾经踩过的坑（改代码时别再踩回去）：
//   1) SDA 必须"只拉低不推高"。发 '1' 位时要释放总线靠上拉，
//      否则从机 ACK 拉低时会和主机推高打架，总线变 X。
//   2) 释放 SDA 准备收 ACK 必须在 SCL 为低时做。
//      在第 8 位的相位 2（SCL 仍为高）释放，SDA 会上跳，
//      从机把这当成 STOP，位计数清零 -> 第 9 位不拉 ACK -> ack_err 恒为 1。
//   3) phase 只能有一个驱动源。原来主状态机在 IDLE 里也写 phase，
//      和分频块的 phase<=phase+1 打架，仿真结果依赖 always 块顺序。
//   4) 【最重要】状态切换必须全部发生在相位 3。
//      若在相位 2 切状态，新状态会从相位 3 开始，把相位 0/1/2 整个跳过去：
//      S_STOP 只跑到"相位 3 = 直接结束"，压根不产生 STOP 条件；
//      S_RSTA 也产生不了重复起始。从机就一直咬住 SDA，后续 START 全部丢失。
//      相位 3 切换 -> phase 自然回绕到 0，新状态必定从相位 0 完整跑满 4 相位。
//      用 nstate 做"待切换状态"：相位 2 决定去向，相位 3 真正切换。
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

    // 一个 SCL 周期分 4 个相位，故分频系数 = ceil(CLK/(4*I2C_FREQ))。
    // 必须向上取整：27MHz 下 trunc 得 16 -> 422kHz，超 400kHz 上限；ceil 得 17 -> 397kHz。
    localparam integer DIV_RAW = (CLK_FREQ + 4*I2C_FREQ - 1) / (4 * I2C_FREQ);
    localparam integer DIV     = (DIV_RAW > 2) ? DIV_RAW : 2;

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
    reg        sda_drv, scl_o;  // sda_drv=1 表示拉低；0 表示释放（靠上拉变高）
    reg        rw_r;
    reg [6:0]  addr_r;
    reg [7:0]  reg_r;
    reg [7:0]  wdata_r;
    reg [3:0]  nbytes_r;

    // 只有 IDLE 且收到 start 才算一次启动（busy 期间忽略重复 start）
    wire start_pulse = (state == S_IDLE) && start;

    assign scl = scl_o;
    assign sda = sda_drv ? 1'b0 : 1'bz;   // 开漏：只拉低，其余时刻高阻靠上拉

    // ---- SCL 分频：产生 4 倍频 tick ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt <= 16'd0;
            tick    <= 1'b0;
        end else if (start_pulse) begin
            // 复位分频相位，保证事务第一个相位也是完整 DIV 长
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

    // ---- phase 唯一驱动源 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          phase <= 2'd0;
        else if (start_pulse) phase <= 2'd0;
        else if (tick)       phase <= phase + 2'd1;
    end

    // ---- 主状态机 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; nstate <= S_IDLE;
            bit_cnt <= 3'd0; sh_reg <= 8'd0; rd_sh <= 64'd0; nleft <= 4'd0;
            sda_drv <= 1'b0; scl_o <= 1'b1;
            busy <= 1'b0; done <= 1'b0; ack_err <= 1'b0;
            data_rd <= 64'd0;
            rw_r <= 1'b0; addr_r <= 7'd0; reg_r <= 8'd0;
            wdata_r <= 8'd0; nbytes_r <= 4'd1;
        end else begin
            done <= 1'b0;

            if (state == S_IDLE) begin
                scl_o   <= 1'b1;
                sda_drv <= 1'b0;
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
                end
            end else if (tick) begin
                case (state)

                // ---- 起始条件：SCL 高时 SDA 由 1 变 0 ----
                S_START: begin
                    case (phase)
                        2'd0: begin sda_drv <= 1'b0; scl_o <= 1'b1; end
                        2'd1: begin scl_o <= 1'b1; end
                        2'd2: begin sda_drv <= 1'b1; end          // SDA 下降沿 = START
                        2'd3: begin scl_o   <= 1'b0;
                                   sh_reg  <= {addr_r, 1'b0};   // 地址+W
                                   bit_cnt <= 3'd7;
                                   state   <= S_ADDR; end
                    endcase
                end

                // ---- 重复起始（读事务前）----
                S_RSTA: begin
                    case (phase)
                        2'd0: begin sda_drv <= 1'b0; scl_o <= 1'b0; end
                        2'd1: begin scl_o <= 1'b1; end
                        2'd2: begin sda_drv <= 1'b1; end
                        2'd3: begin scl_o   <= 1'b0;
                                   sh_reg  <= {addr_r, 1'b1};   // 地址+R
                                   bit_cnt <= 3'd7;
                                   state   <= S_ADDRR; end
                    endcase
                end

                // ---- 发 8 bit（S_ADDR / S_REG / S_WR / S_ADDRR 共用时序）----
                //     数据的建立发生在相位 0（SCL 为低），SCL 高期间 SDA 保持不变。
                S_ADDR, S_ADDRR, S_REG, S_WR: begin
                    case (phase)
                        2'd0: begin
                                   // 开漏：bit=0 拉低，bit=1 释放（靠上拉为高）
                                   sda_drv <= ~sh_reg[7];
                                   scl_o   <= 1'b0;
                              end
                        2'd1: begin scl_o <= 1'b1; end
                        2'd2: begin
                                   sh_reg <= {sh_reg[6:0], 1'b0};
                                   if (bit_cnt == 3'd0) begin
                                       // ⚠️ 这里不能直接切 state（见文件头坑 2/4），
                                       //    也不能在这里释放 SDA（SCL 仍为高，会被当成 STOP）。
                                       case (state)
                                           S_ADDR:  nstate <= S_AACK;
                                           S_ADDRR: nstate <= S_ARACK;
                                           S_REG:   nstate <= S_RACK;
                                           S_WR:    nstate <= S_WACK;
                                           default: nstate <= S_STOP;
                                       endcase
                                   end
                              end
                        2'd3: begin
                                   scl_o <= 1'b0;
                                   if (bit_cnt == 3'd0) state <= nstate;
                                   else                 bit_cnt <= bit_cnt - 3'd1;
                              end
                    endcase
                end

                // ---- 等 ACK（第 9 个时钟，SCL 高时采样 SDA，低电平=应答）----
                S_AACK, S_RACK, S_WACK, S_ARACK: begin
                    case (phase)
                        2'd0: begin sda_drv <= 1'b0; scl_o <= 1'b0; end   // SCL 低时释放
                        2'd1: begin scl_o <= 1'b1; end
                        2'd2: begin
                                  if (sda == 1'b1) begin        // NACK
                                      ack_err <= 1'b1;
                                      nstate  <= S_STOP;
                                  end else begin
                                      case (state)
                                          S_AACK:  begin nstate <= S_REG;
                                                         sh_reg  <= reg_r;
                                                         bit_cnt <= 3'd7; end
                                          S_RACK:  begin nstate <= rw_r ? S_RSTA : S_WR;
                                                         sh_reg  <= wdata_r;
                                                         bit_cnt <= 3'd7; end
                                          S_WACK:  begin nstate <= S_STOP; end
                                          S_ARACK: begin nstate  <= S_RD;
                                                         nleft   <= nbytes_r;
                                                         bit_cnt <= 3'd7; end
                                          default: nstate <= S_STOP;
                                      endcase
                                  end
                              end
                        2'd3: begin scl_o <= 1'b0; state <= nstate; end
                    endcase
                end

                // ---- 收 8 bit ----
                S_RD: begin
                    case (phase)
                        2'd0: begin sda_drv <= 1'b0; scl_o <= 1'b0; end
                        2'd1: begin scl_o <= 1'b1; end
                        2'd2: begin
                                  rd_sh <= {rd_sh[62:0], sda};
                                  if (bit_cnt == 3'd0) nstate <= S_RACKB;
                              end
                        2'd3: begin
                                  scl_o <= 1'b0;
                                  if (bit_cnt == 3'd0) state <= nstate;
                                  else                 bit_cnt <= bit_cnt - 3'd1;
                              end
                    endcase
                end

                // ---- 主机应答：还有字节就 ACK(拉低)，最后一个字节 NACK(释放) ----
                S_RACKB: begin
                    case (phase)
                        2'd0: begin
                                   sda_drv <= (nleft > 4'd1) ? 1'b1 : 1'b0;
                                   scl_o   <= 1'b0;
                              end
                        2'd1: begin scl_o <= 1'b1; end
                        2'd2: begin
                                  if (nleft > 4'd1) begin
                                      nleft   <= nleft - 4'd1;
                                      bit_cnt <= 3'd7;
                                      nstate  <= S_RD;
                                  end else begin
                                      nstate <= S_STOP;
                                  end
                              end
                        2'd3: begin scl_o <= 1'b0; state <= nstate; end
                    endcase
                end

                // ---- 停止条件：SCL 高时 SDA 由 0 变 1 ----
                S_STOP: begin
                    case (phase)
                        2'd0: begin sda_drv <= 1'b1; scl_o <= 1'b0; end
                        2'd1: begin scl_o <= 1'b1; end
                        2'd2: begin sda_drv <= 1'b0; end          // SDA 上升沿 = STOP
                        2'd3: begin
                                  scl_o   <= 1'b1;
                                  sda_drv <= 1'b0;
                                  data_rd <= rd_sh;
                                  done    <= 1'b1;
                                  busy    <= 1'b0;
                                  state   <= S_IDLE;
                              end
                    endcase
                end

                default: state <= S_IDLE;
                endcase
            end
        end
    end

endmodule
