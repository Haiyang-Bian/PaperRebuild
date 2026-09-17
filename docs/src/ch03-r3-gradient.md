# [R3 灵敏度与投影梯度](@id ch03-r3-gradient)

本页采用第3章已核查WMM解释，讨论流量变化如何影响固定流量子问题的最优费用。
算法名为 `r3_pg_checked_v1`。论文式（3-61）至（3-66）保留在[原式台账](@ref ch03-algorithm-equations)，
本页补全方程使用独立编号，不能将其当作原文逐字转录。

## 从物理量到最优值导数

流量改变管内水的停留时间，也改变热功率和多入流混合系数。因此，改变一个时段的流量，
可能影响后续多个时段的输运。历史流量是给定输入，不随优化改变。
若第i个时间段只覆盖部分管存水，令前序累计流量为S，则

```math
a_i=\frac{M/\Delta t-S}{m_i},\qquad
\frac{\partial a_i}{\partial m_j}=-\frac1{m_i}\;(j<i),\qquad
\frac{\partial a_i}{\partial m_i}=-\frac{a_i}{m_i}.
\tag{R3-PG-1}
```

完全覆盖和未覆盖段的导数为零。累计质量恰好等于管内质量时是分段切换点，
不能把某侧的导数写成唯一普通导数。权重、停留时间和指数衰减继续使用链式求导。
例如当前流量0.8 kg/s、管水1800 kg、步长3600 s，部分权重为0.625，
对当前流量导数为−0.78125 (kg/s)⁻¹。

实现：[`r3_transport_jacobian`](@ref)。其Jacobian列按当前、前一时段、…排列；
子问题组装只取非历史列。测试：`R3 analytic transport Jacobian`。

## 为什么不能只读一组等式乘子

将约束统一写为F(x,m)属于锥K，最小化问题的MOI约定为

```math
L(x,y;m)=c(x,m)-\sum_i y_i^\top F_i(x,m),\qquad
\nabla_m V=\partial_m c-\sum_i(\partial_m F_i)^\top y_i.
\tag{R3-PG-2}
```

等式的右侧先移入F；例如固定条件u−m=0贡献为+y。原式（3-61）仅写热耦合乘子，
采用式则核查所有流量相关项，避免漏掉水力等不等式贡献。
依据：[MOI对偶说明](https://jump.dev/MathOptInterface.jl/stable/background/duality/)。

现有实现有两条参数路径：水力/质量关系通过固定变量传递，由其固定等式对偶统一贡献；
热功率、混合和输运已代入数值系数，另加这些系数的偏导。不能再次把水力锥导数重复相加。
诊断的混合与输运松弛系数含流量，非零松弛时也必须求导。

实现：[`r3_value_sensitivity`](@ref)。保存`fixed_rhs/heat/mixing/transport/loss`分项。
测试：`R3 dual signs and complete value sensitivity`。

## 对偶可信度和适用边界

从JuMP原表达式和变量值重算可行性，避免后端桥接移位坐标影响ConstraintPrimal。
检查所有变量界、固定等式、线性约束和二阶锥的原始/对偶可行性、互补性与平稳性。
归一化KKT误差不得超过1e-6，有效对偶间隙不得超过A2的1e-4；只有OPTIMAL且有可行对偶时才可信。
这不替代独立物理A1，也不证明最优解唯一、处处可微或联合流量问题凸。

文献[116]公开预印本为Guo等的critical region projection：其多参数二次规划、
子问题可行和非退化假设不直接适用于当前变流量WMM。
预印本为2016年v1；论文引用2017年期刊版，版本差异保留。
来源：[作者预印本](https://arxiv.org/pdf/1606.04037)。

## 实施状态

灵敏度核查已通过131项断言：包括三档差分、单源/双源、费用/非零弹性目标和乘子符号。
这只验证本批光滑小例；外层投影与正式实验在后续节点验收。
