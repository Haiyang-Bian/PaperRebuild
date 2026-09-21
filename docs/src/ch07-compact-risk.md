# 第7.4节：保持原模型的紧凑表示

上一轮[带初值对照](ch07-seeded-risk.md)中，3B/3C返回了合格调度，但费用仍为
396812.219543 CNY/日，备用接近零，间隙32.9549%；3A超时无新候选。
这说明可行见证与验证链条已有证据，尚不能比较三方案经济性。

本节点检验一个具体问题：**改变同一数学问题的装配方式，能否降低计算负担？**
模型表示命名为`r9_compact_v1`。它不是新的风险模型，不修改支持、概率、半径、价格、
交付和舒适边界，也不改变A1/A2。以下三项先证明等价，再进行规模对照。

## 1. 原上下界用原生变量界表达

只处理原系数台账显式标为`bound=true`、单个系数严格为1、右端有限的上下界。
例如原矩阵行与新变量域表示：

```math
1\cdot y_j\ge l_j,\quad 1\cdot y_j\le u_j
\quad\Longleftrightarrow\quad y_j\in[l_j,u_j].
\tag{R9-CX1}
```

一般设备或网络单项关系仍保留为约束；不因它只含一个变量就擅自改类。
重复上下界、非单位系数和错误方向被拒绝。
[JuMP约束文档](https://jump.dev/JuMP.jl/stable/manual/constraints/)区分变量域与仿射约束的表示；
这里保留原行ID到实际上下界引用的映射。
数学约束仍然存在，不能把原生边界从矩阵中移出称为删除物理限制。

## 2. 只移除精确零系数

```math
\sum_j a_jy_j=\sum_{j:a_j\ne0}a_jy_j.
\tag{R9-CX2}
```

代码仅使用`iszero(a_j)`，不设数值截断阈值；例如``10^{-30}``也保留。
不改变变量单位、右端、容差或原数据。需要由当前求解器实际计时确认影响，
因为前端或求解器也可能已经处理了部分零项。

## 3. 用等式定义情景费用

原费用运输约束反复引用每个情景的完整费用表达式。新表示引入一个**自由**费用变量：

```math
q_s=\sum_j c_{s,j}y_{s,j},\qquad
\lambda_Cd_{sr}+\nu_{C,r}\ge q_s.
\tag{R9-CX3}
```

每个原可行点都可通过唯一的``q_s=c_s^{\mathsf T}y_s``扩展；
从新可行点消去``q_s``便恢复全部原运输行。目标表达式不变，所以实数算术下可行域投影和
最优值完全相同。没有添加人为费用上下界，也没有用单向不等式代替定义等式。
浮点求解的残差仍由原验证器按原A1/A2检查。

新表示每情景增加一个变量和一条定义等式，减少费用系数在运输行中的重复。
因此“紧凑”指矩阵表达与重复项，**不是变量总数必然减少**。

## 原值与初值怎样保持可核查

- 共同初值仍从原已核查调度读取；新增费用变量用其原费用计算。
- 每条原行保留映射，初值仍检查实际模型的全部行；原生PStart/Start逐值读回。
- 解的设备、网络、承诺与风险变量仍由原数值接口提取。
- 保存后使用原`validate_r5_risk`重算物理、成本、风险及有效界，不用新模型的求解状态代替。
- `representation`和新代码哈希单独保存；旧输入、模型版本及历史文件不迁移。

原生LP/MIP初值属性的区别仍按[Gurobi说明](https://docs.gurobi.com/projects/optimizer/en/current/features/warmstart.html)处理。
新入口显式开启求解日志，并检查文件中存在实际优化进度；仅有日志文件头不算启用成功。

## Julia入口与测试

```@index
Pages = ["ch07-compact-risk.md"]
```

```@docs
build_r9_compact_risk
PaperRebuild.r9_logged_risk_optimize!
```

求解复用[`solve_r9_seeded_risk`](@ref)，显式指定`representation=:r9_compact_v1`；
旧调用默认仍为原表示。例：

```julia
model = build_r9_compact_risk(case; optimizer=optimizer_factory)
# 构造不求解、不写文件；正式运行通过下列冻结脚本入口。
```

数学测试`test/r9_compact_risk.jl`对三个解析小例的LP/MILP逐行消元核对、比较目标、
双向传递可行点，再通过原验证器和存档重读。它检验的是模型等价与接口，不能证明百情景加速。

本节点已通过84项数学/集成、16项本机Gurobi原生初值/实际日志、30项冻结兼容检查。
原生日志测试首版通过但出现Windows临时文件仍被占用的清理警告；新版保留独立日志目录，
再次16项通过且无该警告，原日志保留。这不改变科学模型或验收门槛。

```sh
julia +1.12.6 --startup-file=no --project=. scripts/test_r9_compact_risk.jl
julia +1.12.6 --startup-file=no --project=. scripts/test_r9_compact_native.jl
```

## 事前比较协议与当前边界

协议`configs/r9/compact-study.toml`保留原100代表、三个案例哈希、共同初值与求解器参数。
每项完整600秒，优化截止420秒、独立运输截止480秒，余下用于原验证和保存。
先冻结源码、协议和父输入身份，按3A/3B/3C依次执行；不在看到费用后修改数据或预算。

已冻结`results/summaries/r9-compact-input-20260921-v1`，manifest SHA256为
`b3473ac124c64b7fef5789ef4638e3bf2a15ea11cfa0d30f5e0e2829acebe609`。
17项当前代码/案例/协议核对及549项旧带初值证据检查通过，旧数值与判定保持。
冻结包检查入口为`scripts/check_r9_compact_delivery.jl`；VS Code提供专项、冻结、批量运行及重读任务。

```sh
julia +1.12.6 --startup-file=no --project=. scripts/r9_seeded_study.jl freeze results/summaries/r9-common-input-20260921-v2 results/summaries/r9-common-evidence-20260921-v1 results/runs/r9-compact-input-new configs/r9/compact-study.toml
```

规模对照需要分别记录构建、初值映射、原生求解、原验证、封存耗时，及实际候选和费用界。
表达方式同时改变三项，并启用日志观测；即使出现改善，也只支持这个组合在当前输入上的结果，
不拆分未经实验控制的单因素贡献，不外推所有优化模型。

**当前规模对照尚未运行，未取得新的百情景费用或加速结果。**
若仍受限，保留负结果，根据实际阶段耗时选择下一步；不原样无限重跑。
样本外评价须在训练候选锁定后进行；第7.5节按独立输入推进，不要求本节先认证全部全局最优。
