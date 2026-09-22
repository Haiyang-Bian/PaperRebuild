# 主体拆分符号表

<!-- generated from docs/reading/ch04/scalability.toml; do not edit -->

以下为项目推导符号，不能冒称论文原有扩容规则。

| 符号 | 含义 | 单位 | Julia字段 |
| --- | --- | --- | --- |
| ``i,r,t`` | 父聚合商、子主体及时间索引；运营商不拆分 | index | `mapping.parent_for_actor / copy_index` |
| ``k`` | 每个父主体的等分倍数，本协议取1、2、4 | 1 | `mapping.multiplier` |
| ``d_{i,t},d_{ir,t}`` | 各能量载体的实际灵活负荷；电、热分别应用同一推导 | MW | `values.P_D / H_D` |
| ``\bar d_{i,t}`` | 父主体偏好负荷，子偏好为其1/k | MW | `actors.P_preferred / H_preferred` |
| ``a_i`` | 父主体二次不满意度系数；子主体取k倍 | CNY/(h MW²) | `actors.sat_P / sat_H` |
| ``w_{i,t},w_{ir,t}`` | 不满意度上图辅助量，等分提升除以k，聚合相加 | CNY/h | `values.w_P / w_H` |
| ``\delta_{ir,t},\bar\delta_{i,t}`` | 子主体偏好减实际负荷，及同父子主体偏差的平均值 | MW | `r9_split_cost_identity: δ / meanδ` |
| ``J_k,J_1,\Delta J`` | 子调度与聚合调度实际资源费用及非负差；不是求解器增广目标 | CNY | `child_cost_CNY / parent_cost_CNY / variance_gap_CNY` |
