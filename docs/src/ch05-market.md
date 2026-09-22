# 第5章：固定报价的能量与备用联合出清

## 1. 市场在决定什么？

普通用户有固定用电负荷；发电机申报售电及备用报价；综合能源系统IES申报购电和备用报价。
出清机构在满足能量平衡、备用需求、线路和设备边界的条件下选择中标量。
这一步提供下一批双层模型的连续下层基准，尚未包含IES内部电热调度、策略报价、风险或Benders。

原件PDF89–90（印刷72–73）对应(5-34)–(5-58)。原文明确使用一小时时段，
(5-46)也已包含下一时段爬坡乘子。项目重新推导的重点是统一符号、初始出力、终端索引和时间步。
原(5-35)中的普通用电为负注入；(5-49)/(5-50)却写为正号。采用版以(5-35)和能量守恒为准。

入口为[`R5MarketCase`](@ref)、[`build_r5_market`](@ref)、[`build_r5_market_dual`](@ref)。
数学主符号沿用原文；代码中的G是GC的检索别名，U/D分别对应up/down，数组依次为主体、时段。

## 2. 原问题与单位

令发电能量中标量为p，IES购电量为q，普通负荷为D；u、d分别为上、下备用容量。
全部功率单位MW，Δt为h；能量报价单位美元/MWh，备用报价为美元/(MW·h)。
购电为正；IES提供上备用的含义是减少购电，因此它的可调范围与发电机相反。

原(5-34)的固定普通负荷效用项在本接口中省略为常数，原问题和对偶同时采用此口径。
这不会改变出清或边际价格，但不能把目标数字直接等同于含该常数的原文社会效益，更不是系统资源成本。

~~~math
\min Z=\Delta t\sum_t\left[\sum_g(c_gp_{gt}+b_g^Uu_{gt}+b_g^Dd_{gt})+
\sum_i(-v_iq_{it}+b_i^Uu_{it}+b_i^Dd_{it})\right].
\tag{R5-MK1}
~~~

平衡对应原(5-36)/(5-37)，项目给能量行选择以下方向：

~~~math
\sum_bD_{bt}+\sum_iq_{it}-\sum_gp_{gt}=0,\qquad
R_t^U-\sum_gu_{gt}-\sum_iu_{it}=0,\qquad
R_t^D-\sum_gd_{gt}-\sum_id_{it}=0.
\tag{R5-MK2}
~~~

容量及报价边界对应原(5-38)–(5-41)。物理容量与报价容量分别保留，不能假定相等：

~~~math
\underline P_g+d_{gt}\le p_{gt}\le\overline P_g-u_{gt},\quad
\underline Q_i+u_{it}\le q_{it}\le\overline Q_i-d_{it},\quad
0\le p_{gt}\le P_g^{\rm Bid},\quad 0\le q_{it}\le Q_i^{\rm Bid}.
\tag{R5-MK3}
~~~

各类备用也有独立非负报价上界。普通负荷不提供备用；本接口不认证备用激活后的线路可交付性。
给定PTDF和参考节点，采用净注入n=发电−普通负荷−IES购电，线路流量f=PTDF·n并满足双向容量。
PTDF模型不等同于交流潮流。原(5-42)的爬坡采用显式初始出力p_g0：

~~~math
-\Delta t\,r_g^D\le p_{gt}-p_{g,t-1}\le\Delta t\,r_g^U.
\tag{R5-MK4}
~~~

例如50MW普通负荷和30MW的IES购电，发电须为80MW。发电报价20、上/下备用报价5/2，
备用需求20/10MW，IES购电效用报价100且不提供备用，则一小时目标为
20×80+5×20+2×10−100×30=−1280美元。负数来自消费效用项，不表示设备产生负资源成本。
将时段改为0.25h而保留功率和单位报价后，目标为−320，边际能量价格仍是20美元/MWh。

## 3. 从同一原问题推导对偶

平衡等式的拉格朗日乘子为π、σU、σD；不等式均写成h≤0，其乘子非负。
记容量乘子为a/b（发电上/下）、c/e（IES上/下购电），能量报价上界乘子为k，
备用报价上界乘子为η；线路乘子为μ+/μ−，爬坡乘子差为r_t=ρ_t+−ρ_t−。
取不存在的r_(T+1)=0，定义节点边际价格：

~~~math
\lambda_{bt}=\frac{\pi_t-\sum_l\operatorname{PTDF}_{lb}(\mu_{lt}^+-\mu_{lt}^-)}{\Delta t}.
\tag{R5-MK5}
~~~

对非负原变量逐项求导，约化费用须非负；正中标量对应约化费用为零。例如：

~~~math
s_{gt}^{p}=\Delta t(c_g-\lambda_{b(g)t})+a_{gt}-b_{gt}+k_{gt}^{p}+r_{gt}-r_{g,t+1}\ge0,
\quad
s_{it}^{q}=\Delta t(-v_i+\lambda_{b(i)t})+c_{it}-e_{it}+k_{it}^{q}\ge0.
\tag{R5-MK6}
~~~

四类备用分别为Δt·报价−σ，加相应容量乘子及报价上界乘子；原变量与各自约化费用互补。
原不等式余量与非负乘子也互补。对偶目标由拉格朗日常数项组成；
初始爬坡会额外产生−(ρ_g1+−ρ_g1−)p_g0，不能把初始出力当成零。
[`build_r5_market_dual`](@ref)直接构建这一手推对偶，未调用自动对偶化工具。

JuMP/MOI最小化LP的原始对偶按约束方向记录：≥行非负、≤行非正、等式自由。
项目保存原始值，并按实际行方向转换为上述拉格朗日乘子，保留转换残差。
依据为[MOI官方对偶约定](https://jump.dev/MathOptInterface.jl/stable/background/duality/)，
不能把屏幕上某个对偶值不加符号说明地叫作电价。

两个解析爬坡例单独检查边界：

- 两小时负荷20/100MW，廉价机组报价20、每小时最多上升20MW，另一机组报价50。
  最优廉价出力20/40MW，总报价目标4200；边际价格为−10/50。
  第一小时略增负荷允许廉价机组第二小时多发电，因而第一小时边际费用可以为负；不需要负报价。
- 单小时负荷100MW、廉价机组初始30MW、上升界20MW，廉价出力50MW，目标3500。
  初始出力增加δ可减少约30δ的目标。再把其能量报价上限限制为40MW，目标变为3800。

这些是预先构造的解析检查，不是作者实际价格轨迹。

## 4. 怎样执行和判断？

~~~julia
using PaperRebuild, JuMP, HiGHS
case = load_r5_market_case("configs/r5/market-base.toml")
result = solve_r5_market(case; optimizer=HiGHS.Optimizer, budget_sec=60)
result["validation"]["model_pass"]
result["validation"]["kkt_pass"]
~~~

构建接口不求解、不写文件，且检查实际约束类型确为连续LP。
[`validate_r5_market`](@ref)从数值独立重算，不复用JuMP约束表达式。
`model_pass`、`kkt_pass`与`cost_optimization_complete`分别回答可行性、原对偶证据和费用求解状态。
缺失对偶、不可行、无解超时、有解超时、缺许可及数值错误保留各自状态。

[`save_r5_market_run`](@ref)保留输入、原始/转换乘子、残差、源码与环境；
[`read_r5_market_run`](@ref)核验哈希及数值，存档code/replay.jl可以用冻结源码只读重放。
[`compare_r5_market_runs`](@ref)只接受同输入及同目标口径；退化LP不要求不同求解器的全部价格和中标量相同。

后续先接入IES确定性物理调度，再区分价格接受者和价格制定者；DRO/DRJCC、Benders与样本外验收仍属后续工作。

## 5. Julia与VS Code入口

从项目根目录执行，结果目录必须尚不存在：

~~~powershell
julia +1.12.6 --startup-file=no --project=. scripts/check_r5_market.jl
julia +1.12.6 --startup-file=no --project=. scripts/test_r5_market.jl
julia +1.12.6 --startup-file=no --project=. scripts/run_r5_market.jl configs/r5/market-base.toml results/runs/r5/market-local highs 60
julia +1.12.6 --startup-file=no --project=. scripts/validate_r5_market.jl results/runs/r5/market-local
~~~

VS Code提供同名market mapping/tests/run/validate/compare任务。
正式规则已由freeze脚本一次性冻结在configs/r5/market/study.toml；克隆后直接运行study任务，
不用再次冻结。已有规则及结果不覆盖；每次研究使用新的批次ID。
HiGHS正式研究在独立Julia进程内从首个实例固定1线程；完整单元测试沿用该进程已经初始化的线程池。

97项市场测试包括单时段/四分之一小时、价格差分、跨时段爬坡、初始出力、报价数量限制、
空IES、容量不可行、缺少乘子、缺许可模拟、存档篡改及独立冻结源码重读。
市场数学验证与完整论文实验仍分别记录。
