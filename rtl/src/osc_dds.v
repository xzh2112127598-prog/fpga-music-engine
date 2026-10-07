`timescale 1ns/1ps
////////////////////////////////////////////////////////////////////////////////
// osc_dds.v —— 定点 DDS 振荡器（相位累加器 + 波表查表 + 可选线性插值）
//
// 对应 MATLAB：lib/dds_render.m（无插值）/ lib/dds_render_ip.m（插值）
// 全队口径：相位与频率字都是 32 bit，FTW = round(f × 2^32 / 48000)。
//
// 算法（与 MATLAB 逐位一致，改任何一处都要同步改 MATLAB 并重出 golden）：
//   1) 取相位高 ADDR_W 位当波表地址，低 SHIFT 位当插值小数
//   2) 无插值：out = rom[addr]
//      插值  ：out = round(a0 + frac/2^SHIFT × (a1 - a0))
//              ⚠️ MATLAB 的 round 是"半值远离零"，不是四舍五入到偶数。
//                 硬件实现要先取绝对值再加 2^(SHIFT-1) 后右移，最后还原符号；
//                 直接 (num + HALF) >>> SHIFT 只对正数成立，负数会偏一个 LSB。
//   3) 先输出、后累加相位（MATLAB 同序），相位自然回绕不需显式取模
//
// 为什么要插值：无插值时音高被量化到 1024 个台阶，高音区失真明显；
//               插值版 440Hz 实测误差 2 LSB（无插值 6 LSB），只多一个乘法器。
//
// ⚠️ 时序：ROM 按同步读建模（真实 BSRAM 就是同步的），所以从 en 到 out_valid
//    共 3 拍。接 Gowin pROM IP 时不用改时序；若换成分布式 ROM（异步读），
//    把 ROM_REG 改成 0 可以减少一拍，但综合出来会占大量 LUT，不建议。
//
// ⚠️ 128 振荡器怎么办：本模块内部自带一张 ROM，直接例化 128 份会要 128 块 BSRAM，
//    板子上没有。真正上板要改成 TDM（时分复用）：一个样本周期内把 128 个振荡器的
//    地址依次送进同一块 ROM，27MHz/48kHz = 562 个系统钟，够跑 128×2 次读。
//    接口已经把 addr / frac 分开，改 TDM 时只需把取指部分搬出去。
////////////////////////////////////////////////////////////////////////////////
module osc_dds #(
    parameter PHASE_W  = 32,                        // 相位/频率字位宽（全队统一 32）
    parameter ADDR_W   = 10,                        // 波表地址位宽（1024 点）
    parameter DATA_W   = 16,                        // 波表数据位宽（Q15）
    parameter IPOLATE  = 1,                         // 1=线性插值 0=直接查表
    parameter ROM_FILE = "golden/sine_1024.hex"     // $readmemh 路径（相对仿真工作目录）
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  en,                // 每样本一个周期
    input  wire [PHASE_W-1:0]    ftw,               // 频率控制字
    input  wire                  load,              // 同步装载相位（多振荡器同相位用）
    input  wire [PHASE_W-1:0]    phase_i,
    output reg  signed [15:0]    out,               // Q15 样点
    output reg                   out_valid,
    output wire [PHASE_W-1:0]    phase_o            // 当前相位（调试/TDM 用）
);

    localparam NWORD  = 1 << ADDR_W;
    localparam SHIFT  = PHASE_W - ADDR_W;           // 32-10 = 22

    // ---- 波表（同步读，模拟 BSRAM）----
    reg signed [DATA_W-1:0] rom [0:NWORD-1];
    initial $readmemh(ROM_FILE, rom);

    reg [PHASE_W-1:0] phase;
    assign phase_o = phase;

    // ---- 第 1 拍：取地址 / 小数，同时累加相位 ----
    reg [ADDR_W-1:0]  addr_r;
    reg [SHIFT-1:0]   frac_r;
    reg               v1;

    // ---- 第 2 拍：同步 ROM 读出相邻两点 ----
    reg signed [DATA_W-1:0] a0r, a1r;
    reg [SHIFT-1:0]         frac2;
    reg                     v2;

    // ---- 插值运算：num = a0<<SHIFT + frac×(a1-a0)，再半值远离零取整 ----
    wire signed [DATA_W-1:0] a0s = a0r;
    wire signed [DATA_W-1:0] a1s = a1r;
    wire signed [DATA_W:0]   dif = a1s - a0s;                 // 17 bit
    wire signed [SHIFT:0]    frc = {1'b0, frac2};             // 23 bit，非负
    // ⚠️ 左移的位宽由"左操作数自身"决定，不受赋值目标宽度影响（Verilog 经典坑）。
    //    直接写 a0s <<< SHIFT 只会在 16 位里左移，高位全丢。必须先把 a0s
    //    显式扩到 40 位再移。乘法是上下文决定宽度，所以 frc*dif 不用这样处理。
    wire signed [39:0] a0e  = a0s;
    wire signed [39:0] base = a0e <<< SHIFT;
    wire signed [39:0] prod = frc * dif;                      // 40 bit（含符号）
    wire signed [39:0] num  = base + prod;

    localparam signed [39:0] HALF = 40'sd1 << (SHIFT - 1);
    wire signed [39:0] mag  = num[39] ? (-num + HALF) : (num + HALF);
    wire signed [39:0] res  = num[39] ? -(mag >>> SHIFT) : (mag >>> SHIFT);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= {PHASE_W{1'b0}};
            addr_r <= {ADDR_W{1'b0}}; frac_r <= {SHIFT{1'b0}};
            a0r <= {DATA_W{1'b0}}; a1r <= {DATA_W{1'b0}}; frac2 <= {SHIFT{1'b0}};
            v1 <= 1'b0; v2 <= 1'b0;
            out <= 16'sd0; out_valid <= 1'b0;
        end else begin
            // 相位：装载优先，否则在 en 时累加（先输出后累加，与 MATLAB 同序）
            if      (load)  phase <= phase_i;
            else if (en)    phase <= phase + ftw;

            if (en) begin
                addr_r <= phase[PHASE_W-1 -: ADDR_W];   // 高 ADDR_W 位
                frac_r <= phase[SHIFT-1:0];             // 低 SHIFT 位
            end
            v1 <= en;

            // 同步读：相邻两点一次读出，地址回绕靠位宽自然截断（N = 2^ADDR_W）
            a0r   <= rom[addr_r];
            a1r   <= rom[addr_r + 1'b1];
            frac2 <= frac_r;
            v2    <= v1;

            out_valid <= v2;
            if (v2) begin
                if (IPOLATE) out <= res[15:0];
                else         out <= a0r;
            end
        end
    end

endmodule
