//============================================================
// demo_es8388.sdc —— 本 demo 有两个真实时钟域，必须分别声明
//============================================================

// 板载 50MHz 有源晶振 -> 周期 20ns
create_clock -name clk -period 20.000 [get_ports {clk}]

// ES8388 主机模式产生的 BCLK（= MCLK/4 ≈ 3.073MHz，周期 325.5ns）
create_clock -name aud_bclk -period 325.520 [get_ports {aud_bclk}]

// 两个域之间（50MHz 域的 I2C/按键/LED  <->  BCLK 域的 DDS/sel 同步）
// 全部走打两拍同步器，按异步时钟组处理，不让工具瞎报路径
set_clock_groups -asynchronous -group [get_clocks {clk}] -group [get_clocks {aud_bclk}]
