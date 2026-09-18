# 中标之后：IES能否实际交付备用？

## 1. 从市场账面容量到物理运行

市场基准回答“谁中标多少电量和备用”。本批继续问：把这份成交作为已知输入后，
发电机、电锅炉、管道和建筑能否在给定调用轨迹下满足承诺？

采用版本为`r5_dispatch_checked_v1`，是一条完整已知轨迹的连续LP。
它保留第5章线性配电网、固定流量热输运及建筑温度动态，尚未优化日前报价或概率风险。
原式（5-1）—（5-31）、12组符号与6项采用解释见[台账](ch05-dispatch-equations.md)。
原件为PDF85–88，建筑依据另核对PDF43的（2-72）；不直接继承R4的稳态循环模型。

## 2. 交付方向、罚款和手算

购电为正。日前买了0.162MW，收到0.02MW上备用指令，实际购电应降到0.142MW。
统一采用

~~~math
d_t=P_t^{DA}-P_t^{actual},\quad
r_t=\alpha_t^U R_t^U-\alpha_t^D R_t^D,\quad
e_t=|r_t-d_t|.
\tag{R5-D1}
~~~

因此上备用的d为正，实时结算`−price_RT*d`为收入；下备用反向。
原（5-1）的加号与（5-3）/（5-8）不宜混用，本项目保留原文并另定义d。

单时段教学建筑在293.15K，环境283.15K，G=0.0042MW/K，需要0.042MW总供热维持恒温。
若COP=1的电锅炉供热，基础电负荷0.1MW，实际购电为0.142MW。
日前价格100、上备用容量价5、实时价格100时，足额交付上述0.02MW上备用的净费用为
`16.2−0.1−2=14.1`合成美元；未交付罚款为零。
单独改变市场支付不会改变热力学关系。

（5-4）要求累计误差不超过δ乘以**累计成交备用容量**，本批按dt积分为MWh。
它并不是“误差/实际调用量”的比例。若实际只调用中标容量的10%，δ=0.1可能允许完全不交付该次调用。
这个现象来自原判据的分母，报告须同时给出请求、实际交付和绝对误差，不能只展示模型通过。
绝对值使用上图变量建模，罚价严格为正；独立验证仍检查是否取等。

## 3. 建筑接受的是总热量

第2章（2-72）使用带帽的总热量，正文明确它由区供热和本地电热设备共同提供。
第5章（5-30）也写出这种分解。因此采用版将（5-27）的热输入解释为`H_D+H_DH`。
以单区热容和传热损耗恢复量纲：

~~~math
C_j\frac{T_{jt}-T_{j,t-1}}{\Delta t}
=H^D_{jt}+\eta_j^{DH}P^{DH}_{jt}-G_j(T_{jt}-T_t^{AM}),
\qquad \eta_j^H=\frac{\Delta t}{C_j},\quad U_j=\frac{\Delta tG_j}{C_j}.
\tag{R5-D2}
~~~

C为MWh/K，G为MW/K，dt为h；供热是MW。这里使用隐式Euler，与原式当前室温出现在损耗项的结构一致。
C/G是项目显式物理解释与合成输入，未声称取得了作者全部建筑参数。
原离散η/U已经含时间步，改用15分钟时不能直接沿用一小时数值。

同一总供热从“全区供热”换成“全本地加热”，在相同热容/损耗下应得到相同室温；
电耗和费用是否相同还取决于COP、热网及设备。本批手算令COP都为1、无管损以隔离这一关系。
接口[`r5_building_coefficients`](@ref)、[`r5_building_temperature`](@ref)，测试组`R5 building total heat and units`。

## 4. 供回水是两个方向的混合

每根管的质量流量保持严格正向给定。供水按from→to，回水沿相反方向；
热源出口和负荷回水出口是独立端口，不能无条件等同于节点混合温度。
对节点n采用：

~~~math
\left(\sum_{p\in out(n)}m_p+\sum_{j\in load(n)}m_j\right)T^S_n
=\sum_{p\in in(n)}m_pT^{S,out}_p+\sum_{s\in source(n)}m_sT^{S,src}_s,
\tag{R5-D3a}
~~~

~~~math
\left(\sum_{p\in in(n)}m_p+\sum_{s\in source(n)}m_s\right)T^R_n
=\sum_{p\in out(n)}m_pT^{R,out}_p+\sum_{j\in load(n)}m_jT^{R,load}_j.
\tag{R5-D3b}
~~~

这同时需要供水质量守恒`入管+源注入=出管+负荷取水`。
源产热为`cp*m_source*(T_source−T_return_node)`，负荷取热为`cp*m_load*(T_supply_node−T_return_load)`。
cp从J/(kg·K)除以1e6得到MW换算，流量保持kg/s。

管道采用原（5-25）/（5-26）的节点法形式：无损输运按时段质量重叠，
随后使用作者J衰减及当时环境温度；非整步时延不取整，历史不能补零。
建模复用已核查的恒流核；验证器另以平移的质量区间重叠计算权重。
作者J与连续PDE精确解的差别仍沿用C08边界，没有因此宣布热网动态完全物理精确。

## 5. 电网、成本和适用限制

- 使用（5-16）的电压**幅值**v；r/x为pu，支路MW/Mvar显式除以S_base。
- EB和本地加热是耗电，CHP/GT/PV是发电；GT按元件定义加入平衡和设备费用。
- Q统一记录净注入，设备边界显式配置；合成本地加热采用单位功率因数。
- 线路P/Q分别有有限盒界，这是项目运行限制，不当作MVA圆形容量。
- 初始出力、管道入口历史、建筑初温都固定；建筑终端必须显式选择`free`或`initial`。
- 管内终端温度显式为`free`，本批不加入R3恢复尾段；费用比较不当作周期热状态恢复后的净收益。
- 净费用分为日前购能减容量收入、设备费用、实时偏差结算和误差罚款。
  固定成交费用是常数，不能把补救LP称为已完成最优市场策略。

本批不含交流损耗、水压、泵耗、储能、逐时信息约束、风险机会约束或Benders。
原始约束和变量界乘子会保存，但尚未独立核验补救KKT，因此本批不把它们用于分解割。

## 6. Julia操作与验收

[`R5DispatchCase`](@ref)严格检查质量守恒、单位、历史与边界；
[`build_r5_dispatch`](@ref)只建模，[`solve_r5_dispatch`](@ref)共享建模与求解预算。
[`validate_r5_dispatch`](@ref)不使用JuMP约束表达式，独立重算全部声明关系、成本和交付量。
可从[`r5_award_from_market`](@ref)提取已认证市场运行，保留父输入和原值哈希，不缩放MW。
提取完成不表示设备足以兑现该成交。

~~~powershell
julia +1.12.6 --startup-file=no --project=. scripts/check_r5_dispatch.jl
julia +1.12.6 --startup-file=no --project=. scripts/test_r5_dispatch.jl
julia +1.12.6 --startup-file=no --project=. scripts/run_r5_dispatch.jl configs/r5/dispatch/hand.toml results/runs/r5/dispatch-hand-new highs 60
julia +1.12.6 --startup-file=no --project=. scripts/validate_r5_dispatch.jl results/runs/r5/dispatch-hand-new
~~~

科学验收仍用A1/A2：分别报告线性电网、固定流量热关系、硬舒适约束、交付考核、
绝对误差上图取等、费用重算和有效界。模型不可行、不支持求解器、许可缺失和无解超时分别保存。
保存和重读见[`save_r5_dispatch_run`](@ref)、[`read_r5_dispatch_run`](@ref)，不覆盖旧运行。
本批正式证据须先冻结规则、提交科学源码再运行；测试通过本身不等于已经形成正式研究结论。
