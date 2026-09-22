# 第7.4节输入：公式、符号和研究边界

由`docs/reading/ch07/reserve.toml`生成。

| 编号 | 含义 | Julia API |
|---|---|---|
| R9-RS1 | 参考负荷、端口质量流率与建筑连续C/G参数；项目替代，不拟合原表费用 | [`r9_reserve_template`](@ref) |
| R9-RS2 | 正向固定流量下，按原节点法J生成稳态入口历史；不改成PDE精确衰减 | [`audit_r9_reserve_input`](@ref) |
| R9-RS3 | 混合、建筑负荷回水及源端热量，分别核对供回方向与容量 | [`audit_r9_reserve_input`](@ref) |
| R9-RS4 | 输配费在日前和实时能量价各加一次，合并后仅按实际PCC购电计费 | [`r9_reserve_template`](@ref) |

| ID | 数学符号 | 含义 | 代码 | 单位 |
|---|---|---|---|---|
| r9.reserve.Href | ``H_b^{\mathrm{ref}}`` | 建筑参考热负荷；36节点均分参考总负荷 | `href` | MW |
| r9.reserve.m | ``m_b`` | 建筑端口质量流率；不是管内体积流量 | `buildings[b].m_kg_s` | kg/s |
| r9.reserve.C | ``C_b`` | 单区建筑显式热容；项目替代参数 | `C_MWh_K` | MWh/K |
| r9.reserve.G | ``G_b`` | 建筑与室外的传热系数 | `G_MW_K` | MW/K |
| r9.reserve.J | ``J_p`` | 作者固定流节点法的半时间步衰减系数 | `fixed_flow_kernel(...).J` | 1 |
| r9.reserve.tariff | ``\kappa^{\mathrm{grid}}`` | 按实际购电能量计费的输配费；不计入备用容量价 | `transmission_CNY_MWh` | CNY/MWh |

| 疑点 | 状态 | 采用解释或缺口 |
|---|---|---|
| R9-RS-C01 | project_interpretation | 表7-12四台P2H按电输入侧解释容量，效率0.8；原表未写容量侧。PV1仍为第7.1节2MW。 |
| R9-RS-C02 | project_interpretation | 备用价格文字与坐标时间单位不一致；显式采用CNY/(MW*h)，所有容量收益乘dt。图7-9曲线与文字200–400/20–40范围也不完全相容；当前合成价格按文字范围冻结，不称为原曲线数字化。 |
| R9-RS-C03 | bounded_model | 复用R5线性电压幅值潮流、固定正流热节点法、连续CHP及完整未来轨迹补救；不认证AC损耗、水压、启停或在线控制。 |
| R9-RS-C04 | boundary_declared | 建筑末温回初值，管温终端free；不能将末端管内热量消耗解释为公平周期收益。 |
| R9-RS-C05 | pending_formal_comparison | 3A要求全部调用交付，不能把模板delta=0.1称100%；三方案的交付规则及是否增加共同delta=0对照须在正式优化前冻结。无备用探针的容量分母为零，实际交付误差被约束为零。 |
| R9-RS-C06 | pending_formal_comparison | 100代表情景、训练/验证/测试划分、概率距离和风险半径尚未冻结；当前不报告3A/3B/3C收益排序、样本外可靠率或作者同输入结果。式5-70的联合舒适风险不同于交付误差delta；有限支持概率扰动不能认证任意未见24h调用轨迹。 |
| R9-RS-C07 | currency_checked | v1USD数据和哈希不迁移；v2显式USD/CNY及cost_per_MWh、penalty_per_MWh。原USD市场父记录和策略市场不自动跨币种。 |
