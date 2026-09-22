# 第5章市场：原式映射与符号

由docs/reading/ch05/market.toml生成。原件PDF89–90；本页覆盖固定报价LP的9条原式。
为便于阅读，原主体索引J/l改记g/b/i；上下界和类别上标的物理含义保留。
完整推导、单位和边界见[市场说明](ch05-market.md)，未宣称实现双层或风险调度。

## 式（5-34）：最小化报价供给成本减消费效用

~~~math
\min\ \sum_{g}o^{GC,E}_{gt}P^{GC}_{gt}-\sum_b o^D_{bt}P^D_{bt}-\sum_i o^{IES,E}_{it}P^{IES}_{it}+\sum_g(o^{GC,RU}_{gt}R^{GC,U}_{gt}+o^{GC,RD}_{gt}R^{GC,D}_{gt})+\sum_i(o^{IES,RU}_{it}R^{IES,U}_{it}+o^{IES,RD}_{it}R^{IES,D}_{it})
\tag{5-34}
~~~

采用解释：固定普通负荷效用作为常数省略；显式求和全部时段并乘dt_h。该数值不是资源成本。原文主体索引J/l在展示中改记g/b/i。

API：[`build_r5_market`](@ref)；测试组：R5 market primal, dual and units。

## 式（5-35）：PTDF线路容量与净注入

~~~math
-\overline P_l\le\sum_b\operatorname{PTDF}_{lb}(P^{GC}_{bt}-P^D_{bt}-P^{IES}_{bt})\le\overline P_l
\tag{5-35}
~~~

采用解释：按接入节点汇总主体，普通负荷与IES购电为负注入；不采用5-49/50的普通负荷正号。

API：[`build_r5_market`](@ref)；测试组：R5 market primal, dual and units。

## 式（5-36）：上、下备用容量分别平衡

~~~math
R_t^{Sys,U/D}=\sum_gR_{gt}^{GC,U/D}+\sum_iR_{it}^{IES,U/D}
\tag{5-36}
~~~

采用解释：保持等式平衡；备用容量尚不认证激活后的网络与热状态可交付性。

API：[`build_r5_market`](@ref)；测试组：R5 market primal, dual and units。

## 式（5-37）：系统能量平衡

~~~math
\sum_b(-P_{bt}^{IES}-P_{bt}^{D}+P_{bt}^{GC})=0
\tag{5-37}
~~~

采用解释：代码取整行相反数D+IES-GC=0，等式乘子的符号一并转换。

API：[`build_r5_market`](@ref)；测试组：R5 market primal, dual and units。

## 式（5-38）：发电机能量与备用共用物理容量

~~~math
\underline P_g^{GC}+R_{gt}^{GC,D}\le P_{gt}^{GC}\le\overline P_g^{GC}-R_{gt}^{GC,U}
\tag{5-38}
~~~

采用解释：上下容量逐行保留，备用报价上限与物理余量同时生效。

API：[`build_r5_market`](@ref)；测试组：R5 market primal, dual and units。

## 式（5-39）：IES上备用减少购电，下备用增加购电

~~~math
\underline P_i^{IES}+R_{it}^{IES,U}\le P_{it}^{IES}\le\overline P_i^{IES}-R_{it}^{IES,D}
\tag{5-39}
~~~

采用解释：购电为正；本轮只验证日前余量，实时交付符号留待物理补救接口单独验证。

API：[`build_r5_market`](@ref)；测试组：R5 market primal, dual and units。

## 式（5-40）：发电机和IES各自的能量报价容量

~~~math
0\le P_{jt}^{GC/IES}\le P_j^{Bid}
\tag{5-40}
~~~

采用解释：分别使用gen.p_bid_max与ies.purchase_bid_max，不默认为物理容量。

API：[`build_r5_market`](@ref)；测试组：R5 market KKT ramp, integrity and statuses。

## 式（5-41）：备用报价容量

~~~math
0\le R_{jt}^{GC/IES,U/D}\le R_j^{Bid}
\tag{5-41}
~~~

采用解释：为主体和上/下备用分别提供有限非负上限。

API：[`build_r5_market`](@ref)；测试组：R5 market primal, dual and units。

## 式（5-42）：发电机跨时段爬坡

~~~math
-R_g^{RP}\le P_{gt}^{GC}-P_{g,t-1}^{GC}\le R_g^{RP}
\tag{5-42}
~~~

采用解释：显式p_initial与dt_h；可分别指定上/下MW/h边界。末端下一时段乘子置零。

API：[`build_r5_market_dual`](@ref)；测试组：R5 market KKT ramp, integrity and statuses。

## 符号表

| 稳定ID / 原符号 | 含义与类别 | 单位 / 定义域 | Julia与维度 | 来源 |
|---|---|---|---|---|
| r5-market-generation / ``P_{gt}^{GC}`` | 发电机能量中标功率；variable | MW；非负，满足物理与报价界 | `P_G[g,t]`；发电机×时段 | 5-34, 5-38, 5-40 |
| r5-market-purchase / ``P_{it}^{IES}`` | IES购电中标功率，正号为消费；variable | MW；非负，满足物理与报价界 | `P_IES[i,t]`；IES×时段 | 5-34, 5-39, 5-40 |
| r5-market-reserve-g / ``R_{gt}^{GC,U},R_{gt}^{GC,D}`` | 发电机上/下备用容量；variable | MW；非负 | `R_G_up[g,t], R_G_down[g,t]`；发电机×时段 | 5-36, 5-38, 5-41 |
| r5-market-reserve-ies / ``R_{it}^{IES,U},R_{it}^{IES,D}`` | IES上/下备用容量；variable | MW；非负；上备用减少购电 | `R_IES_up[i,t], R_IES_down[i,t]`；IES×时段 | 5-36, 5-39, 5-41 |
| r5-market-demand / ``P_{bt}^{D}`` | 普通用户固定负荷；parameter | MW；有限非负 | `load_MW[b][t]`；节点×时段 | 5-35, 5-37 |
| r5-market-ptdf / ``\operatorname{PTDF}_{lb}`` | 给定参考节点下的注入到支路流量系数；parameter | 1；有限实数；参考列零 | `network.ptdf[l][b]`；支路×节点 | 5-35 |
| r5-market-line-limit / ``\overline P_l`` | 双向支路容量；parameter | MW；有限正数 | `network.limit_MW[l]`；支路 | 5-35 |
| r5-market-energy-bid / ``o^{GC,E}_{gt},o^{IES,E}_{it}`` | 发电成本报价与IES购电效用报价；parameter | USD/MWh；固定有限非负，非策略变量 | `generators[g].energy_bid[t], ies[i].energy_bid[t]`；主体×时段 | 5-32, 5-34 |
| r5-market-reserve-bid / ``o^{GC/IES,RU/RD}_{jt}`` | 各主体上/下备用单位容量每小时报价；parameter | USD/(MW*h)；固定有限非负 | `up_bid[t], down_bid[t]`；主体×时段 | 5-34及项目显式时间单位 |
| r5-market-bid-capacity / ``P_j^{Bid},R_j^{Bid}`` | 能量与备用报价数量上限；parameter | MW；有限非负，独立于物理容量 | `p_bid_max, purchase_bid_max, up_max, down_max`；主体，跨时段固定 | 5-40, 5-41 |
| r5-market-physical-capacity / ``\underline P^{GC/IES},\overline P^{GC/IES}`` | 发电或购电物理边界；parameter | MW；0≤下界≤上界，均有限 | `p_min, p_max, q_min, q_max`；主体 | 5-38, 5-39 |
| r5-market-required-reserve / ``R_t^{Sys,U/D}`` | 系统上/下备用需求；parameter | MW；有限非负 | `reserve_up_MW[t], reserve_down_MW[t]`；时段 | 5-36 |
| r5-market-ramp / ``R_g^{RP},P_{g0}^{GC}`` | 爬坡速率及给定初始出力；parameter | MW/h; MW；有限非负，初始出力在物理范围内 | `ramp_up_MW_h, ramp_down_MW_h, p_initial`；发电机 | 5-42与项目显式初始条件 |
| r5-market-time / ``\Delta t`` | 时间步；project parameter | h；有限正数 | `dt_h`；标量 | 原文一小时；项目显式转换 |
| r5-market-equality-dual / ``\pi_t,\sigma_t^U,\sigma_t^D`` | 采用平衡行的拉格朗日乘子；π为项目符号，不冒称原λ符号方向相同；dual variable | USD/MW；自由实数；原始MOI值另存 | `multipliers.energy, multipliers.up, multipliers.down`；时段 | 原5-36/37；R5-MK2项目行方向 |
| r5-market-inequality-dual / ``\mu^{\pm},\rho^{\pm},a,b,c,e,k,\eta`` | 线路、爬坡、容量和报价上界的采用乘子；dual variable | USD/MW；非负；全部不等式按h≤0解释 | `multipliers各具名行；原始raw_duals另存`；对应主体或支路×时段 | 5-35, 5-38至5-42；项目统一拉格朗日记号 |
| r5-market-lmp / ``\lambda_{bt}`` | 节点单位能量边际价格；derived output | USD/MWh；实数，耦合条件下可为负 | `LMP_USD_MWh[b][t]`；节点×时段 | R5-MK5项目推导 |

## 采用边界

- R5-MK-C01：按5-35采用负的普通负荷注入；5-49/50正号保留在原页审计，不复制。
- R5-MK-C02：原5-46已有下一时段项。显式补齐初始出力、时间单位和对偶常数，并测试首末边界；不声称作者漏写全部跨时耦合。
- R5-MK-C03：固定普通负荷效用项是常数，本模型原对偶同时省略；只比较同口径目标。
- R5-MK-C04：发电能量报价上限与物理容量分开；备用报价上限和物理余量也分别约束。
- R5-MK-C05：本批固定报价连续LP不包含策略反馈、备用激活可交付性、IES物理补救或风险；退化价格不要求逐项唯一。
