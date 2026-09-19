# 市场选择以后，成交能否交付

上一批[连续策略结果](ch05-strategic-results.md)验证了显式乐观模型，
同时发现独立市场可能选择不同成交。本节把“市场最优”“按规则执行”和“内部能交付”分别检查。
新制度为项目对照，不是作者公布的市场规则。

## 1. 同样最优，为什么成交不同

若外部发电报价和IES购电报价都为100，增加1 MW购电带来的消费效用
恰好抵消新增发电成本。仅凭市场福利目标，可能有一整段同样最优的成交。
上层设备模型能在其中选出对自己有利且可交付的结果，独立市场却不一定做同样选择。

原PDF89/90的(5-34)至(5-58)给出市场LP及KKT。这些方程定义最优解集合，
没有在该集合内为本项目指定唯一执行结果。原文模型保留；
新增公式、符号与边界由[执行规则台账](ch05-execution-equations.md)生成。

## 2. 先保持原福利，再明确选择

[`build_r5_execution_selector`](@ref)先保持原市场最优目标等式，
再最小化全部成交量的平方和。另一问题在对偶最优面最小化全部显式乘子的平方和。
数量参考尺度为1 MW，价格参考尺度为100 USD/MWh，乘子尺度包含时间步。

~~~math
y^\dagger=\arg\min_{y\in Y,\ c(o)^\mathsf Ty=f^\star}
\frac12\|y/s_P\|_2^2,\qquad
\xi^\dagger=\arg\min_{\xi\in\mathcal D(o),\,D(\xi)=f^\star}
\frac12\|\xi/(\Delta t\,s_\pi)\|_2^2.
\tag{R5-EX1/2}
~~~

非空闭多面体上，正定平方范数有界子水平集保证最小值存在，严格凸性保证唯一。
原最优面无界不妨碍这一性质；这与给市场价格添加上限有不同含义。
此规则不表示公平，也依赖明确的对偶表示：增删冗余乘子可能改变最小范数价格。

这两个目标只负责选择，不计入资源成本或IES收益。
没有给原福利目标加一个任意小的权重，原LP的最优性仍单独验算。

## 3. 哪些乘子是价格

[`solve_r5_market_execution`](@ref)保存三个问题：原市场LP、原始选择QP和对偶选择QP。
价格来自最后一个问题的优化变量。两个QP的原始MOI乘子用于认证选择规则，
不能冒充原市场价格。符号转换遵循[MOI对偶约定](https://jump.dev/MathOptInterface.jl/stable/background/duality/)。

[`validate_r5_market_execution`](@ref)重新核验原市场守恒和KKT，
并从保存的QP系数、原值及原始乘子重算驻点、互补与原对偶差。
解析例取非负x、y及x+y=1；最小平方和解为(0.5,0.5)，增加x≥0.8后为(0.8,0.2)。
实际市场的价格/数量也须通过选择证书，求解器返回OPTIMAL本身不够。

## 4. 固定成交以后检查交付

[`evaluate_r5_execution_delivery`](@ref)将市场的购电、上备用和下备用逐时固定，
保留原设备容量、初始历史、情景轨迹、室温物理域和风险上限，重新求解条件补救。
增加成交等式时仍保留变量上下界；超容量应报告不可行。

~~~math
C_{\rm exec}
=\Pi(y^\dagger,\xi^\dagger)
+\min_{\text{recourse}}
  \sup_{p\in\mathcal P}\sum_s p_sQ_s.
\tag{R5-EX4}
~~~

市场支付此时为固定常数。条件补救的最优界只针对给定成交，
不能当作新市场制度下策略报价的最优界。模型内的费用和风险最坏分布继续分别核验。
本批不重新选择报价，因此不能声称原乐观报价在新制度下仍最优。

旧乐观成交、旧独立市场成交和新制度成交分别评价；
[`validate_r5_execution_delivery`](@ref)核验成交连接、采用物理关系、风险和费用。
保存/重读由[`save_r5_execution_run`](@ref)、[`read_r5_execution_run`](@ref)完成，
保留科学源码快照及各问题的原始状态。

## 5. 进度及下一步

78项专项与3141项完整回归通过；22项正式对照已完成，
10项新选择认证、18/20内部交付通过，详见[正式结果](ch05-execution-results.md)。
新制度的执行评价与“在新制度下重新优化报价”是两项不同工作。
既有乐观直接模型继续作为论文结构基准，用于后续策略分解的同模型对照；
新执行对照用于限定其可实施性结论。R6样本外与第6/7章仍按[全文清单](reproduction-coverage.md)推进。

~~~powershell
julia +1.12.6 --startup-file=no --project=. scripts/test_r5_execution.jl
julia +1.12.6 --startup-file=no --project=. scripts/check_r5_execution.jl
~~~
