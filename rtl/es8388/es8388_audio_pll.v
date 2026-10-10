//============================================================
// es8388_audio_pll.v —— 50MHz -> ES8388 MCLK（高云 GW5A 专用 PLL 原语）
//
// ⚠️ 高云 PLL 原语按系列不同名，GW5A(Arora-V) 上综合器认的是 `PLLA`
//    （实测：`rPLL` 报 EX3937 unknown module；`PLL` 报 RP0008 no PLL
//    resource；只有 `PLLA` 能过综合，参数表见 simlib/gw5a/prim_sim.v
//    与 UG306-1.0.6_Arora V时钟资源(Clock)用户指南.pdf 第 5.1 节）。
//
// 频率公式（内部反馈）：
//     Fpfd  = CLKIN / IDIV                 （PFD 合法范围 19~87.5MHz）
//     Fvco  = Fpfd × FBDIV × MDIV          （GW5A-25: VCO 700~1400MHz）
//     MCLK  = Fvco / ODIV0
// 本配置：
//     Fpfd  = 50MHz / 1 = 50MHz
//     Fvco  = 50MHz × 1 × 14.5 = 725MHz
//     MCLK  = 725MHz / 59 = 12.288136MHz（+11.0ppm，与参考设计同解）
//     fs    = MCLK/256 = 48000.53Hz（+0.0034%，约 0.02 音分，不可闻）
// （14.5 = 14 + 4×0.125，MDIV 支持 1/8 小数；曾试过 50/5×6×16÷78.125
//   = 精确 12.288MHz 的解，但 PFD=10MHz 低于 19MHz 下限被 PA2078 拒绝，
//   PFD 限制下 50MHz 输入只能 IDIV=1 或 2，+11ppm 已是数学最优）
//============================================================
//============================================================
// iverilog 仿真时定义 SIM_PLL_STUB 即可绕开 PLLA 原语（Icarus 不认识它），
// 用一个 12.5MHz 分频 + 延时锁定信号代替。上板综合走下面的 PLLA 分支。
//============================================================
module es8388_audio_pll (
    input  wire clkin,          // 50MHz 板载晶振
    output wire clkout,         // 12.288MHz -> ES8388 MCLK
    output wire locked          // PLL 锁定指示
);

`ifdef SIM_PLL_STUB
    reg [1:0] div      = 2'd0;
    reg       clkout_r = 1'b0;
    reg [7:0] lock_cnt = 8'd0;
    reg       locked_r = 1'b0;
    always @(posedge clkin) begin
        div      <= div + 1'b1;
        clkout_r <= (div == 2'd1);          // 50/4 = 12.5MHz，仿真够用
        if (&lock_cnt) locked_r <= 1'b1;
        else           lock_cnt <= lock_cnt + 1'b1;
    end
    assign clkout = clkout_r;
    assign locked = locked_r;
`else

    PLLA #(
        .FCLKIN         ("50.0"),
        // ---- 分频链：÷1 ×1 ×14.5 ÷59 = 12.288136MHz ----
        .IDIV_SEL       (1),            // 1~64，实际分频值
        .FBDIV_SEL      (1),            // 1~64
        .MDIV_SEL       (14),           // 2~128
        .MDIV_FRAC_SEL  (4),            // ×0.125，14.500
        .ODIV0_SEL      (59),           // 1~128
        .ODIV0_FRAC_SEL (0),            // 59.000
        // ---- 只用 0 通道 ----
        .CLKOUT0_EN     ("TRUE"),
        .CLKOUT1_EN     ("FALSE"),
        .CLKOUT2_EN     ("FALSE"),
        .CLKOUT3_EN     ("FALSE"),
        .CLKOUT4_EN     ("FALSE"),
        .CLKOUT5_EN     ("FALSE"),
        .CLKOUT6_EN     ("FALSE"),
        .CLK0_IN_SEL    (1'b0),         // 0 通道输入来自 VCO
        .CLK0_OUT_SEL   (1'b0),         // 0 通道输出来自 ODIV0
        .CLKFB_SEL      ("INTERNAL"),   // 内部反馈
        .DE0_EN         ("FALSE"),      // ODIV0=2~128 时固定 50% 占空比
        // ---- 相位/占空比微调全部保持默认（不需要）----
        .DYN_DPA_EN     ("FALSE"),
        .DYN_PE0_SEL    ("FALSE"),
        .DYN_PE1_SEL    ("FALSE"),
        .DYN_PE2_SEL    ("FALSE"),
        .DYN_PE3_SEL    ("FALSE"),
        .DYN_PE4_SEL    ("FALSE"),
        .DYN_PE5_SEL    ("FALSE"),
        .DYN_PE6_SEL    ("FALSE"),
        .RESET_I_EN     ("FALSE"),
        .RESET_O_EN     ("FALSE"),
        .SSC_EN         ("FALSE")
        // ICP_SEL / LPF_RES / LPF_CAP 留默认值 X，工具自动计算
    ) u_pll (
        .CLKIN       (clkin),
        .CLKFB       (1'b0),
        .RESET       (1'b0),            // 高有效，这里不复位
        .PLLPWD      (1'b0),            // 0 = PLL 上电
        .RESET_I     (1'b0),
        .RESET_O     (1'b0),
        // PLLA 没有 ENCLKx 端口，通道使能由 CLKOUTx_EN 参数控制
        // 动态端口全部拉低（分频参数全静态）
        .PSSEL       (3'b0),
        .PSDIR       (1'b0),
        .PSPULSE     (1'b0),
        .SSCPOL      (1'b0),
        .SSCON       (1'b0),
        .SSCMDSEL    (7'b0),
        .SSCMDSEL_FRAC(3'b0),
        .MDCLK       (1'b0),            // MDIV 动态写接口，不用
        .MDOPC       (2'b0),
        .MDAINC      (1'b0),
        .MDWDI       (8'b0),
        .CLKOUT0     (clkout),
        .CLKOUT1     (),
        .CLKOUT2     (),
        .CLKOUT3     (),
        .CLKOUT4     (),
        .CLKOUT5     (),
        .CLKOUT6     (),
        .CLKFBOUT    (),
        .MDRDO       (),
        .LOCK        (locked)
    );

`endif

endmodule
