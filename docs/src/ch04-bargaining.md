# R4第三批：从总体节约到参与条件

本批接续[可实施基线](ch04-baseline-results.md)。同一调度下，资源成本与内部支付分开：
调度决定总剩余，议价决定如何分配。采用r4_nash_checked_v1，先验证固定调度的单阶段解析分配。
两阶段TSPA、ATC/ADMM、拓扑优化及论文规模仍未实现。

## 1. 原文在解决什么问题？

PDF70–72、式（4-71）–（4-94）先最大化可转移总效用，再分配支付。
分歧点d表示不合作时的效用；它必须有明确制度和可执行计划作为依据。
原文的[解析支付](@ref ch04-094)与[符号表](ch04-bargaining-equations.md)保留原编号。
本项目采用同输入、原电网及静态热能流均通过的AG0作为本批分歧点；仅购能制度是项目新增设定。

令不含内部支付的合作效用为u，净收款为p，正权重为α。定义：

~~~math
S=\sum_i(u_i-d_i),\qquad g_i=u_i+p_i-d_i,\qquad
\sum_i p_i=0\Longrightarrow\sum_i g_i=S .
\tag{R4-N1}
~~~

当S>0，最大化加权对数增益。约束只耦合增益总和，一阶条件给出
α_i/g_i相等，结合总和即可得到原文（4-82）的分配。
权重统一乘正数不会改变解。计算中以1合成美元为对数参考单位，使对数的自变量无量纲。

**适用条件不能省略：**支付无限额、可正可负、没有额外交易摩擦；所有权重严格为正。
零剩余只能让各方恰好回到分歧点，不计算log(0)；负剩余无法同时满足预算平衡和个体理性。
代码不会把很小的负数裁为零。若增加支付上限、运营商不得付钱等约束，解析解不再自动适用。

固定一个可行物理候选时，本批只认证它的最优分配。要称整个两阶段问题全局最优，
还须证明物理调度达到同一可行域的总效用全局最优。本批不升级上游求解证据。

## 2. 总支付与补偿款必须分开

原文（4-94）的φ是总支付。本批先从账本移除全部内部零售、P2P和服务费，
令u等于支付前成本的负值，再计算新总支付。若读者希望继续使用旧零售账单，可另列补偿：

~~~math
\Delta\phi_i=p_i-c_i^{old},\qquad
U_i^{old}+\Delta\phi_i=u_i+p_i,\qquad \sum_i\Delta\phi_i=0 .
\tag{R4-N2}
~~~

其中c_old是旧结算的内部净收支。不能将新总支付再次加到已结算效用上。
不满意度已经货币化并计入u，改变支付不会改变设备出力、负荷、电热损耗或资源成本。

API：[解析分配](@ref PaperRebuild.r4_nash_allocation)、
[独立验收](@ref PaperRebuild.validate_r4_allocation)、
[物理候选接入](@ref PaperRebuild.r4_allocate_coordination)。

## 3. 权重的原文依据与项目映射

PDF72以分布式能源容量与峰值负荷之和表征聚合商市场力，运营商权重等于聚合商之和。
原文没有逐项说明电热设备和储能容量怎样相加。项目预先冻结capacity_load_v1：

- CHP/PV按电功率，HP/EB按输入电功率，电池按功率；不把MWh与MW相加，也不重复计CHP热功率。
- 加参考电负荷和热负荷各自峰值。跨载能类型的和是分配政策指标，不是物理能量相加。
- A/B权重为1.02/0.80，DSO为1.82，故DSO分得总增量的一半。
- equal_v1为明确声明的三方等权对照；不是看到结果后挑选的权重。

[权重API](@ref PaperRebuild.r4_bargaining_weights)返回各分项以便复查。
权重表示事先选择的分配规则，不能用分到的份额反过来证明该方的真实边际贡献。

## 4. 原文TSPA为何还需要单独研究？

PDF73–74的两阶段流程先忽略网络，求聚合商间AGNB；再固定注入，
允许网络约束带松弛与惩罚，计算DHSO0-r作为运营商分歧点，最后实施网络协同分配。
这与本批的可实施AG0不相同，不能把单阶段分配改名为TSPA。

原文式（4-102）使用“协同总效用不低于P2P阶段总效用”这一前提。
当P2P分歧点依赖松弛网络时，可行域包含关系不自动成立；必须核对罚项、松弛位置和费用口径。
证明中比较的是指定聚合商交易联盟与加入运营商后的选择，并没有逐一核验任意子联盟。
本批只报告相对指定分歧点的个体理性，不声称整个合作博弈的核非空或联盟普遍稳定。

后续实现将同时保留原文松弛分歧点和实际网络验收，若S<0则保存分配不可行结果。
ATC/ADMM原页中惩罚系数、平方范数与对偶更新的记号疑点另行推导，不在本批静默补写。

## 5. 验证与操作

手算例：u=(-3,8,5)，d=(-5,2,4)，权重=(1,2,3)，总剩余9，
增益=(1.5,3,4.5)，净支付=(-0.5,-3,3.5)。支付为零和，各方均比d好。
独立测试用JuMP/Clarabel指数锥重新求解同一对数目标，核对分配、目标与有效间隙。
建模形式参见[JuMP官方指数锥示例](https://jump.dev/JuMP.jl/stable/tutorials/conic/tips_and_tricks/#Exponential-Cone)。

~~~jldoctest
julia> using PaperRebuild

julia> r = r4_nash_allocation([-3., 8., 5.], [-5., 2., 4.], [1., 2., 3.]);

julia> r["gain"]
3-element Vector{Float64}:
 1.5
 3.0
 4.5

julia> validate_r4_allocation(r)["strict_improvement"]
true
~~~

| 操作 | 根目录Julia 1.12.6命令 |
|---|---|
| R4测试 | julia +1.12.6 --project=. scripts/test_r4.jl |
| 映射检查 | julia +1.12.6 --project=. scripts/check_r4_bargaining.jl |
| 局部补证与分配 | julia +1.12.6 --project=. scripts/study_r4_bargaining.jl 新批次ID |
| 已存记录报告 | julia +1.12.6 --project=. scripts/report_r4_bargaining.jl 路径/study.toml 新报告目录 |
| 图表重绘 | julia +1.12.6 --project=docs scripts/plot_r4_bargaining.jl 新报告目录 |

正式清单为configs/r4/bargaining-study.toml，求解前冻结。旧物理计划、原始状态和原运行均不覆盖。
证书是对旧候选的补充记录，不修改原cost_optimization_complete字段。
