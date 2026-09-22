# 八聚合商怎样分别求解并协调网络？

本页接续[设备接入与集中基准](ch07-network.md)。集中模型由一个求解器同时看到全部设备和网络；
本节点将同一资源目标拆成多个主体块及一个运营商块，检验交换边界量能否恢复一致调度。
沿用[第4章原式核读与符号修正](ch04-distributed.md)，不将项目ADMM实现称为作者源码的等价实现。
数据仍为合成替代；规模正式对照、议价和完整热物理分别验收。

## 1. 每个主体传什么？

主体保留自己的设备、负荷偏好和储能初末条件。运营商保留自身资源、电网和稳态热网络。
两块之间需要传递四种量，不能仅传电热净量：

```math
b_{i,t}=\begin{bmatrix}
\sum_{g\in\mathcal G_i}(P_{g,t}^{gen}-P_{g,t}^{cons})-P_{i,t}^{D}\\
q_iP_{i,t}^{D}\\
\sum_{g\in\mathcal G_i}H_{g,t}^{gen}\\
H_{i,t}^{D}+\sum_{g\in\mathcal G_i}H_{g,t}^{cons}
\end{bmatrix},\qquad \underline b_{i,t}\le b_{i,t}\le\overline b_{i,t}.
\tag{R9-DC1}
```

第一项是向电网注入为正的净功率，第二项是无功需求，后两项分别是供热端口和用热端口。
储热放热进入第三项，充热进入第四项。即使两个主体接在同一个热节点，也保留各自身份，
最后才在节点守恒中相加。有限盒从原设备容量、可用功率和负荷范围推导，只是必要边界。

例如，某主体电负荷1 MW、光伏2 MW，净电注入为1 MW；若同时向储热充入0.4 MW，
这个热需求必须告知网络。只发送净热交换，不能完整约束供、用热端口的质量流量包络。
完整定义由[符号权威表](ch07-distributed-generated.md)生成。

## 2. 为什么拆开后仍是同一个资源问题？

设主体成本包含自己的资源消耗和不满意度；运营商还承担外部购电、自身资源及网络动作成本。
内部零售或P2P支付由账本处理，不能重复计入社会资源成本：

```math
\min_{y_0,y_1,\ldots,y_A}
C_0(y_0)+\sum_{i=1}^{A}C_i(y_i),\qquad
y_i\in\mathcal Y_i,\quad y_0\in\mathcal Y_0.
\tag{R9-DC2}
```

主体索引在本文数学式为1…A，Julia保存的运营商为actor=1、主体为2…A+1。
运营商优化各主体边界的副本；边界一致时才可以合成集中可行调度：

```math
b_i(y_i)=\widehat b_i(y_0)\quad(\forall i).
\tag{R9-DC3}
```

**从集中到分块：**把集中解的各设备控制交给其所属主体，把网络控制及边界交给运营商。
设备约束不变，原节点守恒被同值边界替代，成本逐项相加等于集中目标。

**从分块到集中：**保留运营商的网络变量，以各主体实际控制替换其边界副本。
当四类边界相等，原节点电、热、质量关系不变；各设备已经满足本地约束。
因此分块合并对应同一采用模型。这个论证要求固定模式一致、原端口容量保持，
并不证明电网锥松弛取等或稳态热量能由完整温度、水压动态实现。

测试中的集中解只用于检查上述数学嵌入。正式算法不接收集中解作为初值。

## 3. 怎样更新消息？

将各行通信量除以输入确定的尺度S；费用除以冻结正尺度C_s。
全部聚合商相互独立，所以把它们共同看作ADMM第一块，运营商为第二块：

```math
\begin{aligned}
y_i^{k+1}&\in\arg\min_{y_i\in\mathcal Y_i}
  C_i(y_i)/C_s+\frac\rho2\|x_i(y_i)-z_i^k+u_i^k\|_2^2,\\
y_0^{k+1}&\in\arg\min_{y_0\in\mathcal Y_0}
  C_0(y_0)/C_s+\frac\rho2\|z(y_0)-x^{k+1}-u^k\|_2^2,\\
u^{k+1}&=u^k+x^{k+1}-z^{k+1},\qquad x=S^{-1}b,\quad z=S^{-1}\widehat b.
\end{aligned}
\tag{R9-DC4}
```

运营商的乘子符号与主体相反。两边从零消息、零缩放乘子开始，每个模型只构建一次，
逐轮更换增广目标。每次完整运行最多600秒，最多1000轮，所有块共用截止时间。
串行模拟各主体交换信息，不等于多机部署或隐私隔离；保存全部原值是为了研究审计。

`r9_boundary_admm_fixed_v1`要求全部储能、热方向及适用网络开关模式显式固定；
这时块内为连续凸锥模型。`r9_boundary_admm_mip_v1`保留整数，是独立命名的启发式，
不能直接继承凸ADMM收敛结论。旧集中、独立运营及R1–R8接口保持原行为。

原论文罚系数递增、更新记号及范数形式的疑点仍保留在第4章台账。本项目采用固定正ρ和
一致增广拉格朗日推导。依据为[ADMM作者说明](https://web.stanford.edu/~boyd/papers/admm/)；
其中也强调，中间迭代可能尚不满足一致性，因此中间目标低于最优值不表示取得可实施收益。

## 4. 怎样判断成功？

```math
\|r^k\|_\infty=\|x^k-z^k\|_\infty\le10^{-4},\qquad
\|d^k\|_\infty=\rho\|z^k-z^{k-1}\|_\infty\le10^{-4}.
\tag{R9-DC5}
```

这是A4消息门槛。停止还要求用实际主体控制合并的调度通过采用模型A1。
不会平均不一致消息，也不会调用集中模型或修正程序制造可行候选。
原支路等式、稳态热量/质量、账本和费用检查分别保留；最好模型候选与最好原电网候选分别记录。
每块增广目标的界属于该子问题，不能相加当作社会成本下界。迭代停止不自动设置费用最优性完成。

完整迭代保存主体与运营商原变量、消息、缩放乘子、增广目标、原费用、实际状态及耗时。
独立重读重新计算每轮消息和合并方程；失败的半轮单列，不伪装成有效更新。
超时、缺许可、求解器不支持、证明不可行和数值失败分别报告。预算超出如实记录。

## 5. Julia与验证入口

```@index
Pages = ["ch07-distributed.md"]
```

```@docs
r9_boundary_contract
r9_trading_boundary
build_r9_distributed_block
R9DistributedSpec
solve_r9_distributed
validate_r9_distributed
save_r9_distributed_run
read_r9_distributed_run
```

```sh
julia +1.12.6 --startup-file=no --project=. scripts/test_r9_distributed.jl
julia +1.12.6 --startup-file=no --project=. scripts/check_r9_distributed.jl
julia +1.12.6 --startup-file=no --project=. scripts/r9_distributed.jl run INPUT.toml RULES.toml results/runs/r9-distributed NEW_RUN_ID
julia +1.12.6 --startup-file=no --project=. scripts/r9_distributed.jl check RUN_DIRECTORY
```

规则文件使用`schema="r9-distributed-rules-v1"`，显式给出`algorithm`、`rho`、`max_iterations`、
`budget_sec`、`solver`及`[solver_options]`；fixed版本还必须给出`[fixed_modes]`中完整的
`z_storage`、`heat_direction`，v2网络输入还包含`u_E`和`u_H`，均按行列数组存储。
Gurobi运行改用`--project=tools/solvers`；算法不因缺许可而自动改用其它求解器或整数版本。
VS Code提供相应测试、映射、符号同步、运行及重验任务；输入路径由使用者明确选择。

当前145项专项检查通过，覆盖两主体/八主体零初值迭代、手算费用、跨时储能与固定拓扑、
失败状态、原值重放和篡改拒绝。仍需冻结44电节点/38热节点的正式对照；解析例的成功不能代替规模算法结果。
实际命令与原失败保存在`docs/agent/tasks/2026-09-22-r9-distributed.md`。
原AG0供热不足及第7.4节近零备用的负边界保持，不能因新的接口通过而改写。

两份命令行开发对照均从零消息运行4轮：Clarabel固定模式的最好采用模型费用为
100.000000003 CNY，Gurobi整数接口为99.999015426 CNY，均在手算100 CNY的A2门槛内。
这个微型整数例仅验证调用通路，不证明规模整数协调有效。两份原始输出的电网原等式均未通过，
只有模型A1和消息A4通过；辅助电流平方量的残差保留，费用差不能解释为经济优势。

额外只读诊断利用该手算例的零线路阻抗，按原支路等式重算电流平方辅助量，其余控制与费用逐位保持。
两份重构候选均通过采用模型及原电网检查；16项断言通过。原ADMM输出、最佳物理候选标志和存档未改写，
该诊断也没有反馈算法。零阻抗使辅助量不影响节点损耗和电压降；有阻抗网络必须重新核查全部依赖，
不能直接沿用这里的结论。通信量单位为MW/Mvar，内部P_branch/Q_branch已是标幺量，不能重复除基准。

## 内部建模与审计接口

下面的辅助接口用于核对实现分层；一般运行从前面的公共入口开始。

```@docs
PaperRebuild.r9_distributed_cost_scale
PaperRebuild.r9_distributed_modes
PaperRebuild.r9_trading_message_expressions
PaperRebuild.r9_distributed_objective!
PaperRebuild.r9_distributed_candidate
PaperRebuild.r9_distributed_block_cost
PaperRebuild.r9_distributed_error_status
PaperRebuild.r9_distributed_solve_block!
PaperRebuild.r9_distributed_check_files
PaperRebuild.r9_distributed_read_current
```
