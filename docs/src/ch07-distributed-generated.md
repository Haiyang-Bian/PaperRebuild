# 分布边界协调符号与采用式索引

<!-- generated from docs/reading/ch07/distributed.toml; do not edit -->

定义以台账为准；原式出处沿用第4章核读，R9-DC编号为项目补充。

| 符号 | 含义 | 单位 | Julia字段 |
| --- | --- | --- | --- |
| ``b_{i,t}=(P_{i,t}^{net},Q_{i,t}^{load},H_{i,t}^{src},H_{i,t}^{demand})`` | 主体实际控制导出的四分量边界；净电注入向网络为正，其余三项非负 | MW, Mvar, MW, MW | `message[4(i-2)+1:4(i-1), t]` |
| ``x_j,\ell_j`` | 本诊断的原变量与严格相等上下界；与ADMM归一化消息x属于不同作用域 | 原变量各自单位；不得将不同变量原始残差合并作A1 | `equal-bounds.toml: index, name, value` |
| ``\widehat b_{i,t}`` | 运营商网络块中的对应边界副本 | MW, Mvar, MW, MW | `operator.values.boundary` |
| ``S_j`` | 通信行全时域最大绝对边界；恒零行取同单位1，边界不变 | corresponding message unit | `contract.scale[j]` |
| ``x=S^{-1}b,\ z=S^{-1}\widehat b,\ u`` | 归一化主体消息、网络副本及缩放对偶变量；并非原物理功率或市场价格 | 1 | `trace[k].x, trace[k].z, trace[k].u` |
| ``C_s`` | 从输入预先计算并冻结的正费用尺度，不是费用界 | CNY | `result.cost_scale` |
| ``\rho`` | 归一化增广目标的固定正罚系数 | 1 | `spec.rho` |
| ``r^k=x^k-z^k,\ d^k=\rho(z^k-z^{k-1})`` | ADMM原始与对偶残差；无穷范数分别检查A4 | 1 | `trace[k].primal, trace[k].dual` |

## 采用式

- **R9-DC1**：主体四类边界及输入推导的有限通信盒。热源、热需求分开，储热充放不丢失。
- **R9-DC2**：资源成本分块，外购费用与网络动作仅由运营商承担，内部支付不进入系统资源目标。
- **R9-DC3**：边界一致性与集中模型的双向嵌入；原值合并不平均或再调度。
- **R9-DC4**：固定正罚系数的归一化两块ADMM；所有独立主体共同构成第一块。整数版本仅为启发式。
- **R9-DC5**：独立原始/对偶残差、逐轮控制回放、最好候选与范围明确的物理检查。

## 项目诊断关系

- **R9-DB1**：有限且严格相等的上下界改为固定等式，其它目标及约束逐行不变；只检验本首块表示假设。 状态：`verified_equivalence_did_not_resolve_solver_status`。
