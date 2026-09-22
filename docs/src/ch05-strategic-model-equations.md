# 连续策略报价：公式与符号

由strategic-model.toml生成。R5-ST为项目编号，明确区分原式与乐观选择等新增假设。

## R5-ST1

~~~math
Ay=b,\quad Gy\le h,\quad y\ge0,\quad c(o)+A^\mathsf T\pi+G^\mathsf T\mu-\delta=0
\tag{R5-ST1}
~~~

下层目标系数c随连续报价o改变。等式乘子自由，其他乘子非负；所有市场原始行及变量下界均计入。报价界按原5-32显式输入。

原式：5-32、5-34、5-43至5-50；API：[`build_r5_strategic`](@ref)；测试：`R5-ST 连续报价与独立下层`。

## R5-ST2

~~~math
s=h-Gy\ge0,\quad \mu\ge0,\quad (\mu_j,s_j)\in\mathrm{SOS1},\qquad (\delta_k,y_k)\in\mathrm{SOS1}
\tag{R5-ST2}
~~~

两个非负量至多一个非零表达互补，不设置任意乘子上界；这是项目求解表示。风险舒适开关的大M仍来自显式温度域，不能与对偶M混为一谈。

原式：5-51至5-57；API：[`build_r5_strategic`](@ref)；测试：`R5-ST 连续报价与独立下层`。

## R5-ST3

~~~math
P_t^{\mathrm{DA}}=P_t^{\mathrm{IES}},\qquad R_t^U=R_t^{\mathrm{IES},U},\qquad R_t^D=R_t^{\mathrm{IES},D}
\tag{R5-ST3}
~~~

共同承诺与市场成交逐时相等，两侧同为MW；不按内部设备容量缩放成交。补救仍须逐情景满足原采用物理关系。

原式：5-33；API：[`validate_r5_strategic`](@ref)；测试：`R5-ST 连续报价与独立下层`。

## R5-ST4

~~~math
\min_{o,y,\pi,\mu,\delta,x,z}\ \Pi^{\mathrm{IES}}(y,\pi,\mu)+\sup_{p\in\mathcal P}\sum_i p_i Q_i(x_i),\qquad \sup_{p\in\mathcal P}\sum_i p_i z_i\le\epsilon
\tag{R5-ST4}
~~~

采用全时域支付恒等式R5-SP3连接风险补救；内嵌补救的日前价格显式为零，避免重复计费。费用和事件的最坏分布独立。所有下层最优变量共同由上层选择，是显式乐观解释。

原式：5-6、5-61、5-66、5-68；API：[`solve_r5_strategic`](@ref)；测试：`R5-ST 连续报价与独立下层`。

## R5-ST5

~~~math
\Pi_{\min/\max}(\bar y,\bar o)=\min/\max_{\pi,\mu}\{\Pi(\bar y,\pi,\mu):\ (\pi,\mu)\in\mathcal D(\bar o),\ D(\pi,\mu)=c(\bar o)^\mathsf T\bar y\}
\tag{R5-ST5}
~~~

固定原始成交和报价，在对偶最优面上分别求支付两端；不改变成交、不截断价格。强对偶与双边可行性保证对应下层最优，不证明悲观双层决策已求解。

原式：5-58、5-61；API：[`r5_market_settlement_range`](@ref)；测试：`R5-ST 固定成交价格最优面`。

## 符号与作用域

| ID | 数学符号 | 含义 | 单位 | Julia映射 | 作用域 |
|---|---|---|---|---|---|
| R5-ST-S01 | ``o_t^E,o_t^U,o_t^D`` | IES连续购电效用报价与上/下备用供给报价 | USD/MWh；USD/(MW h) | `bids[energy_bid / up_bid / down_bid][t]` | 三类时段向量；容量另以外生输入固定 |
| R5-ST-S02 | ``y`` | 全部发电与IES能量/备用成交 | MW | `selected_market[values]` | 主体×时段；与内部风险共同承诺精确桥接 |
| R5-ST-S03 | ``\pi,\mu,\delta`` | 所选下层等式、不等式与变量下界乘子 | USD/MW | `selected_market[multipliers / lower_bound_duals]` | 优化变量来源，不是上层MIP求解器原始对偶 |
| R5-ST-S04 | ``s`` | 市场不等式剩余容量 | MW | `market_slack` | 与非负乘子组成SOS1；独立验算由原值重算 |
| R5-ST-S05 | ``Q_i,z_i,\mathcal P`` | 情景补救费、舒适开关与有限支持运输歧义集 | USD；1 | `risk_policy / embedded_duals / oracles` | 沿用风险台账；费用/风险两个对手独立 |

## 原文、采用解释与证据

### R5-ST-C01

**原文：**原5-32为连续价格报价；原文未完整给出多最优出清的执行规则。

**采用解释：**单领导者连续报价，固定可报价容量，明确乐观原始/对偶选择；固定报价变体仍采用相同选择规则。

**证据与边界：**独立下层只比较最优值并核验KKT，不强迫成交和价格一致；另测固定成交支付范围。

### R5-ST-C02

**原文：**KKT互补常用大M表达，但原页不足以给出所有有效对偶界。

**采用解释：**SOS1原生表达，Gurobi PreSOS1BigM=0；不支持原生SOS1的求解器明确拒绝。开放求解器用于显式固定分支。

**证据与边界：**记录实际MOI类型；固定分支只报告该分支界；不能把其目标当作一般全域下界。

### R5-ST-C03

**原文：**原5-6净支付和实时补救共同组成IES目标。

**采用解释：**风险模板日前价格显式为零，净支付按所选真实出清乘子另计；不将上层界复用为风险子记录或市场界。

**证据与边界：**独立检查支付直接乘积与仿射式、三个运输证书及费用分项；缺失认证保留候选未决。

### R5-ST-C04

**原文：**价格制定者改善私人目标不自动改善总体资源成本。

**采用解释：**手算阶梯例分别记录IES支出和外部/内部发电资源费，明确固定报价对照与完全价格接受者不是同一概念。

**证据与边界：**预定低价容量0.2MW、普通负荷0.1MW、IES需求0.142MW及20/100/130三价格；不按收益调整参数。
