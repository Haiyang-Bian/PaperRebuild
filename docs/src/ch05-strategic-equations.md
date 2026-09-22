# 策略报价准备：支付推导与符号

由strategic.toml生成。R5-SP是项目编号，连续策略报价优化尚未实现。

## R5-SP1

~~~math
\Pi^{\rm IES}=\Delta t\sum_{i,t}(\lambda_{b(i)t}q_{it}-\lambda_t^U u_{it}-\lambda_t^D d_{it})
\tag{R5-SP1}
~~~

全部IES在全时域的净支付；购电支出减去备用容量收入。

原式：5-6、5-33；API：[`r5_market_payment_identity`](@ref)；测试：`R5-SP 全时域支付与强对偶线性式`。

## R5-SP2

~~~math
-\Delta t\sum_{i,t}(v_{it}q_{it}-b_{it}^Uu_{it}-b_{it}^Dd_{it})=Z-C_G,\quad C_G=\Delta t\sum_{g,t}(c_{gt}p_{gt}+b_{gt}^Uu_{gt}+b_{gt}^Dd_{gt})
\tag{R5-SP2}
~~~

从出清目标移项时，发电机的三类报价成本都必须被减去。固定普通负荷效用已在两侧一致省略。

原式：5-34、5-59；API：[`r5_market_payment_identity`](@ref)；测试：`R5-SP 全时域支付与强对偶线性式`。

## R5-SP3

~~~math
\Pi^{\rm IES}=C_G+\mathcal R_G^{\rm cap}+\mathcal R_G^{\rm bid}+\mathcal R^{\rm ramp}+\mathcal R^{\rm line}-\Delta t\sum_{b,t}\lambda_{bt}D_{bt}-\sum_t(\sigma_t^UR_t^{\rm sys,U}+\sigma_t^DR_t^{\rm sys,D})
\tag{R5-SP3}
~~~

发电机驻点、互补及系统守恒给出的净支付线性表达；适用于全部IES合计，不保证逐时成立。

原式：5-58、5-60、5-61；API：[`r5_market_payment_identity`](@ref)；测试：`R5-SP 全时域支付与强对偶线性式`。

## 符号与作用域

| ID | 数学符号 | 含义 | 单位 | Julia映射 | 作用域 |
|---|---|---|---|---|---|
| R5-SP-S01 | ``\Pi^{\rm IES}`` | 全部IES合计日前净支付 | USD | `direct_payment_USD / affine_payment_USD` | 全时域标量；含备用收入，非纯资源成本 |
| R5-SP-S02 | ``\lambda_{bt},\lambda_t^U,\lambda_t^D`` | 节点电能价及上/下备用容量价 | USD/MWh；USD/(MW h) | `energy / up / down multipliers divided by dt_h; energy also subtracts PTDF congestion` | 节点×时段或时段；原始乘子符号沿用R5-MK5 |
| R5-SP-S03 | ``\pi_t,\sigma_t^U,\sigma_t^D`` | 包含时间步的能量及备用平衡拉格朗日乘子 | USD/MW | `multipliers[energy / up / down]` | 时段向量；乘功率即费用，不再乘dt_h |
| R5-SP-S04 | ``k_{gt}^p,k_{gt}^U,k_{gt}^D`` | 发电机能量及备用报价容量上界乘子 | USD/MW | `pg_bid / gu_bid / gd_bid` | 发电机×时段；与物理容量乘子分开 |
| R5-SP-S05 | ``\rho_{gt}^+,\rho_{gt}^-,p_{g0}`` | 爬坡上下界乘子与已知初始出力 | USD/MW；MW | `ramp_up / ramp_down / p_initial` | 全时域伸缩求和含首时段乘子差乘p_initial |

## 原文、采用解释与证据

### R5-SP-C01

**原文：**PDF90原(5-59)右侧印为Upsilon减去发电能量报价成本减上/下备用报价成本的括号，与(5-34)的三类成本同为正不一致。

**采用解释：**由已经独立核查的出清原问题重新移项：Z-C_G，C_G三项均为正相加。保留印刷式，不假定作者实际程序也使用该符号。

**证据与边界：**一小时教学例Z=-1280、发电能量1600、上备用100、下备用20；左侧-3000，采用移项-3000，印刷移项-2760，相差240 USD。

### R5-SP-C02

**原文：**5-61给出了线性净支付形式；采用市场还显式区分报价容量和物理容量，并给定非零初始出力。

**采用解释：**保留发电报价上界、线路租金、普通负荷节点价及初始爬坡项。先验算全时域恒等式，再作为策略报价构建依据。

**证据与边界：**首时段负荷100、廉价机组初始30、上升20 MW，初始爬坡项为900 USD；省略会破坏恒等式。

### R5-SP-C03

**原文：**PDF85明确price maker；PDF86说明在不能影响市场价时退化为price taker；(5-32)约束策略报价。

**采用解释：**旧固定价风险模型是价格接受者基准。接入原(5-32)连续报价及出清KKT才可评价价格制定；不把菜单搜索替代连续报价后称原双层问题完成。

**证据与边界：**本批仅实现支付恒等式；双层决策、互补处理及报价边界仍须单独实施与验证。

### R5-SP-C04

**原文：**原文未在上述原页完整说明下层多最优解和价格不唯一的选择规则。

**采用解释：**上层同时选择有利出清量和价格是乐观双层解释，应明确标注。恒等式通过不证明价格唯一；不得用任意大M或隐式价格截断制造有界最优。

**证据与边界：**后续用退化解析例、独立下层重解和价格范围检查区分报价能力与价格选择收益。
