`timescale 1ns/1ps
////////////////////////////////////////////////////////////////////////////////
// mpu6050_reader.v —— MPU6050 初始化 + 循环读三轴加速度
//
// 上电 -> 延时 100ms -> 配置寄存器 -> 每 1/SAMPLE_RATE 秒读一次 ACCEL_XOUT_H(0x3B)
// 起连续 6 字节 -> 拼成 ax/ay/az（有符号 16 bit）-> sample_valid 拉高一个周期
//
// ⚠️ 量程必须设 ±16g（ACCEL_CONFIG = 0x18, AFS_SEL=3）。
//    默认 ±2g 一敲就爆表，力度信息全部丢失 —— 这是最容易踩的坑。
//    ±16g 下 1g = 32768/16 = 2048 LSB。
////////////////////////////////////////////////////////////////////////////////
module mpu6050_reader #(
    parameter CLK_FREQ    = 27_000_000,
    parameter SAMPLE_RATE = 1000              // 采样率 Hz（500~1000）
)(
    input  wire        clk,
    input  wire        rst_n,
    output wire        scl,
    inout  wire        sda,
    output reg  [15:0] ax,
    output reg  [15:0] ay,
    output reg  [15:0] az,
    output reg         sample_valid,
    output reg         ready                  // 初始化完成
);

    localparam DEV_ADDR = 7'h68;              // MPU6050（AD0 接地）
    localparam REG_PWR  = 8'h6B;              // PWR_MGMT_1
    localparam REG_ACC  = 8'h1C;              // ACCEL_CONFIG
    localparam REG_RATE = 8'h19;              // SMPLRT_DIV
    localparam REG_AXH  = 8'h3B;              // ACCEL_XOUT_H

    localparam BOOT_CYC = CLK_FREQ / 10;      // 上电延时 100ms
    localparam SAMP_CYC = CLK_FREQ / SAMPLE_RATE;

    localparam ST_BOOT = 4'd0, ST_PWR = 4'd1,  ST_PWRW = 4'd2,
               ST_ACC  = 4'd3, ST_ACCW = 4'd4, ST_RATE = 4'd5, ST_RATEW = 4'd6,
               ST_DLY  = 4'd7, ST_RD   = 4'd8, ST_RDW  = 4'd9;

    reg [31:0] cyc;
    reg [3:0]  st;

    reg        m_start;
    reg        m_rw;
    reg [7:0]  m_reg;
    reg [7:0]  m_wdata;
    reg [3:0]  m_nbytes;
    wire [63:0] m_rdata;
    wire       m_done, m_ack_err, m_busy;

    i2c_master #(
        .CLK_FREQ (CLK_FREQ),
        .I2C_FREQ (400_000)
    ) u_i2c (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (m_start),
        .dev_addr (DEV_ADDR),
        .rw       (m_rw),
        .reg_addr (m_reg),
        .data_wr  (m_wdata),
        .nbytes   (m_nbytes),
        .data_rd  (m_rdata),
        .done     (m_done),
        .ack_err  (m_ack_err),
        .busy     (m_busy),
        .scl      (scl),
        .sda      (sda)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= ST_BOOT; cyc <= 32'd0;
            m_start <= 1'b0; m_rw <= 1'b0; m_reg <= 8'd0;
            m_wdata <= 8'd0; m_nbytes <= 4'd1;
            ax <= 16'd0; ay <= 16'd0; az <= 16'd0;
            sample_valid <= 1'b0; ready <= 1'b0;
        end else begin
            sample_valid <= 1'b0;
            m_start      <= 1'b0;

            case (st)
                // ---- 上电延时，等 MPU6050 时钟稳定 ----
                ST_BOOT: begin
                    if (cyc >= BOOT_CYC) begin cyc <= 32'd0; st <= ST_PWR; end
                    else cyc <= cyc + 32'd1;
                end

                // ---- 唤醒：PWR_MGMT_1 = 0x00（退出睡眠，选内部 8MHz）----
                ST_PWR: begin
                    m_rw <= 1'b0; m_reg <= REG_PWR; m_wdata <= 8'h00; m_nbytes <= 4'd1;
                    m_start <= 1'b1; st <= ST_PWRW;
                end
                ST_PWRW: if (m_done) st <= ST_ACC;

                // ---- 量程：ACCEL_CONFIG = 0x18 -> AFS_SEL=3 -> ±16g ----
                ST_ACC: begin
                    m_rw <= 1'b0; m_reg <= REG_ACC; m_wdata <= 8'h18; m_nbytes <= 4'd1;
                    m_start <= 1'b1; st <= ST_ACCW;
                end
                ST_ACCW: if (m_done) st <= ST_RATE;

                // ---- 采样率分频 ----
                ST_RATE: begin
                    m_rw <= 1'b0; m_reg <= REG_RATE; m_wdata <= 8'h01; m_nbytes <= 4'd1;
                    m_start <= 1'b1; st <= ST_RATEW;
                end
                ST_RATEW: if (m_done) begin ready <= 1'b1; cyc <= 32'd0; st <= ST_DLY; end

                // ---- 等一个采样周期 ----
                ST_DLY: begin
                    if (cyc >= SAMP_CYC) begin cyc <= 32'd0; st <= ST_RD; end
                    else cyc <= cyc + 32'd1;
                end

                // ---- 读 6 字节：AXH AXL AYH AYL AZH AZL ----
                ST_RD: begin
                    m_rw <= 1'b1; m_reg <= REG_AXH; m_nbytes <= 4'd6;
                    m_start <= 1'b1; st <= ST_RDW;
                end
                ST_RDW: if (m_done) begin
                    // data_rd 字节 0 在最低位：AXH 是字节 0
                    ax <= {m_rdata[ 7:0], m_rdata[15: 8]};
                    ay <= {m_rdata[23:16], m_rdata[31:24]};
                    az <= {m_rdata[39:32], m_rdata[47:40]};
                    sample_valid <= 1'b1;
                    st <= ST_DLY;
                end

                default: st <= ST_BOOT;
            endcase
        end
    end

endmodule
