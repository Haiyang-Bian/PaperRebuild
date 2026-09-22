# 策略报价分解：公式与符号

由strategic-benders.toml生成。R5-SB为项目采用推导，市场/舒适分支的作用域分别登记。

## R5-SB1

~~~math
\min_{o,y,\pi,\mu,\delta,x,z,\theta,\lambda^Q,\nu^Q}\ \Pi^{\mathrm{IES}}(y,\pi,\mu)+\rho\lambda^Q+\sum_j\widehat p_j\nu_j^Q,\quad \lambda^QD_{ij}+\nu_j^Q\ge\theta_i
\tag{R5-SB1}
~~~

第一阶段包含连续报价、全部下层KKT和成交到共同承诺的相等关系；净支付只计一次。项目保留完整费用运输对偶，不冻结一次最坏权重。风险运输对偶另行保留。

原式：5-71、5-72、5-85、5-86；API：[`build_r5_strategic_benders_master`](@ref)；测试：`R5-SB 市场主问题和声明域`。

## R5-SB2

~~~math
\theta_i\ge \ell_i^{b,k}(x)-M_i^{b,k}\bigl(1-\chi_b(z_i)\bigr),\qquad \chi_0(z)=1-z,\quad \chi_1(z)=z
\tag{R5-SB2}
~~~

已核验原始对偶产生指定舒适分支的补救费用下支撑；M和负费用底界来自全输入有限盒。全部市场报价只通过共同承诺影响补救，因此旧参数LP条件割仍有效；诊断仅在条件LP明确不可行时使用。

原式：5-87至5-92、5-94至5-98；API：[`solve_r5_strategic_benders`](@ref)；测试：`R5-SB 条件割与完整候选费用`。

## R5-SB3

~~~math
U_k=\min_{j\le k,\ j\in\mathcal V}\{\Pi_j+\sup_{p\in\mathcal P}\sum_i p_iQ_i(x^j,z_i^j)\},\qquad L_k=\max_{j\le k}L_j^{\mathrm{MP}}
\tag{R5-SB3}
~~~

集合V只含市场KKT、所有物理补救和独立费用/风险运输均通过的候选。上界按净支付加最坏补救费选择；完整声明域的主问题原求解器界才可累计。原5-102扩张前的受限域界仅用于该轮受限比较。

原式：5-93、5.5.4步骤2.c至2.d；API：[`validate_r5_strategic_benders`](@ref)；测试：`R5-SB 风险时间尺度和私人支付`。

## R5-SB4

~~~math
\mathcal F_{\mathrm{fixed\ market}}\subseteq\mathcal F_{\mathrm{optimistic}},\qquad \mathcal F_{\Pi^c}=\mathcal F\cap\{z_i=0:i\notin\Pi^c\}
\tag{R5-SB4}
~~~

固定互补分支与固定非关键舒适开关是两个独立限制；它们的最优界均不能自动当完整MPEC下界。比较器要求相同输入、相同市场分支及完整舒适域，另列完整模型A2。

原式：5-72、5-102；API：[`compare_r5_strategic_benders_runs`](@ref)；测试：`R5-SB 证据重读与失败传播`。

## R5-SB5

~~~math
v_{\mathrm{MP}}\le v_{\mathrm{full}},\qquad v_{\mathrm{MP}}=-\infty\ \not\Rightarrow\ v_{\mathrm{full}}=-\infty
\tag{R5-SB5}
~~~

只有部分补救割的主问题可能比完整模型更松。其无界状态不得改称原策略模型无界，也不能用任意对偶上界或直接参考解掩盖；保留状态并单列适用边界。

原式：5-85至5-92；API：[`validate_r5_strategic_benders`](@ref)；测试：`R5-SB 本机完整SOS1与独立直接对照`。

## 符号与作用域

| ID | 数学符号 | 含义 | 单位 | Julia映射 | 作用域 |
|---|---|---|---|---|---|
| R5-SB-S01 | ``o,y,\pi,\mu,\delta`` | 连续报价、市场成交及上层选择的下层乘子 | USD/MWh；MW；USD/MW | `master[bids / selected_market]` | 沿用R5-ST；选定乘子不是MIP求解器原始对偶 |
| R5-SB-S02 | ``x,z,\theta`` | 共同日前承诺、舒适分支和补救费用上图 | MW；1；USD | `master[first_stage / z / theta]` | x逐时与市场成交相等；theta不是已验证补救费用 |
| R5-SB-S03 | ``Q_i,\ell_i^{b,k},M_i^{b,k}`` | 条件补救费用、可信下支撑与条件停用界 | USD | `subproblems / cuts` | 沿用R5-BD；不遗漏零最坏概率情景 |
| R5-SB-S04 | ``U_k,L_k,\mathcal V`` | 完整候选上界、主问题下界和已验算候选集合 | USD | `validation[upper_bound / lower_bound] / iterations[candidate]` | 完整、固定互补和受限舒适域分开；缺少证明保留无穷界 |

## 原文、采用解释与证据

### R5-SB-C01

**原文：**原5-72明确包括市场KKT，紧凑记法未逐项展开第一阶段变量。

**采用解释：**直接连续报价模型和分解主问题使用同一完整市场关系及支付恒等式，固定报价Benders结果不改名。

**证据与边界：**主问题MOI类型检查、所选下层独立KKT、成交桥接、直接模型后置比较。

### R5-SB-C02

**原文：**原5-85/流程使用一次最坏权重，5-91/92割只在对应舒适分支有效。

**采用解释：**采用已说明的完整运输对偶和有理有限盒保护割，允许负补救成本；区别于原文字面流程。

**证据与边界：**继承R5-BD的有效下支撑证明，再验证含市场净支付的完整上下界。

### R5-SB-C03

**原文：**原5-102固定外集z=0，且原页没有提供全部市场乘子的有效大M。

**采用解释：**保留paper_critical受限路线与原生SOS1；固定互补只作显式开放测试，不与完整策略域混用。

**证据与边界：**两轴域标签、原求解器界、同输入同域比较及伪造全域标签拒绝。

### R5-SB-C04

**原文：**原算法有限上下界与相对完整补救前提需要检查。

**采用解释：**从空割/空关键集开始逐情景检查，保留不可行、无可信乘子和松弛无界；不隐藏调用直接参考。

**证据与边界：**容量不足、稀缺价格、预算和许可状态测试；直接参照仅后置运行，不提供初始解或割。
