# R4第二批：可实施分歧点与固定效用

本批承接[首批结果](ch04-results.md)，保留旧AG0热过剩反例及全部历史判定。
这是一项新的项目对照制度，不是将旧不可行计划重新命名为可行。
采用模型为r4_baseline_checked_v1；热网仍为静态能量流，未恢复完整温度场。

## 1. 固定效用后才能评价灵活性

令负荷偏好为独立冻结的参数，而可调范围仍由参考负荷和flex决定：

~~~math
C^{sat}=\Delta t\sum_{i,t,c\in\{P,H\}}a_i^c
(\widehat D^c_{i,t}-D^c_{i,t})^2,\qquad
(1-\zeta_i)D^{ref}_{i,t}\le D_{i,t}\le(1+\zeta_i)D^{ref}_{i,t}.
\tag{R4-B1}
~~~

新批次把偏好冻结为首批基础输入的原上界。固定负荷对照只令flex=0，保留同一偏好、价格、设备和网络。
因此固定负荷可行域是灵活负荷可行域的子集；若均求到全局最优，扩大范围的最小成本不可能增加。
有限预算下的候选若反向变化，应先核对求解界，不能直接解释为灵活性有害。

配置采用preference_model=explicit_reference_v1及P_preferred/H_preferred；缺失/非有限输入拒绝。
旧输入继续按原上界取偏好，不迁移旧结果。API：[负荷偏好](@ref PaperRebuild.r4_preferred_demand)。

新实现用每小时成本变量w建立等价锥上图：

~~~math
w\ge a(\widehat D-D)^2
\ \Longleftrightarrow\
(w,\tfrac12,\sqrt a(\widehat D-D))\in\mathcal Q_r,\qquad C^{sat}=\Delta t\,w .
\tag{R4-B1a}
~~~

w单位为合成美元/h，结果spec中以dissatisfaction_epigraph=USD_per_h记录。
旧运行的w单位仍为MW²，独立验证按元数据换回同一平方残差，并直接从D重算费用。
这是变量缩放，不是修改不满意度系数或验收阈值；不声称任意病态模型都能因此得到可靠解。

## 2. 一个明确且保守的独立运营制度

新增import_only_v1：聚合商拥有本地设备、自用和从运营商购能权，暂不拥有向网络净出售的接入权：

~~~math
P^{net}_{i,t}\le0,\qquad H^{net}_{i,t}\le0,\quad i\in\{A,B\}.
\tag{R4-B2}
~~~

该制度预先冻结，并同时传入独立本地求解、冻结计划网络校核及集中对照。
它不保证任意输入都可行；线路、电源或热管容量不足仍可失败，仍须原电网等式和热能流独立校核。
它也不是原文的通用运营制度。其作用是给出一个可检查的研究分歧点，避免以不能实施的利润作为议价底线。

本地零售买价严格大于卖价。净购能条件下，同时买入与卖出相同能量会增加费用，
故本地模型将卖量固定为零、由净量=−购量施加边界。这是最优值等价消元；
网络和集中阶段直接约束节点注入。独立验证仍检查同一净注入不等式。

四配置为开放/仅购能 × 灵活/固定负荷，各运行AG0原电网校核、集中SOCP、集中原电网等式。
开放组保留原失败边界。仅购能组内AG0与SWM具有完全相同的输入和接入边界。
开放与仅购能之间的差异另称接入制度变化，不能混称同制度协调收益。

## 3. 成本与分配分别判断

~~~math
S=C^{AG0}-C^{SWM},\qquad
\sum_i(U_i^{SWM}-U_i^{AG0})=S .
\tag{R4-B3}
~~~

只有两套数值都通过采用模型、原电网、热能流和账本检查时才报告S和节约比例。
内部支付决定各主体的份额，总体节约不保证各方都愿意加入。
[独立核算API](@ref PaperRebuild.r4_coordination_surplus)不执行议价，也不把费用差当最优性间隙。

## 4. 预先冻结的验收

- 旧文件独立重读不改判；显式偏好等于旧锚点时目标一致。
- 固定/灵活配置保持相同偏好；比较可行域包含关系及有效界。
- 同一接入约束适用于三个阶段；验证器从数值重新检查，不能只信模型构造。
- 非法输入、缺解、原等式失败或不同输入不得产生虚假可实施收益率。
- 依旧使用A1/A2；每方式600秒，开放枚举对照60秒；原始失败一并保存。

本页为求解前定义。正式结果在实验封存后补充，不预设所有基线均可行或所有主体受益。

## 5. Julia与VS Code入口

~~~julia
using PaperRebuild
case = load_r4_case("configs/r4/baseline/import_flexible.toml")
r4_preferred_demand(case.data["actors"][2], "P", 1)
~~~

| 操作 | 根目录命令 |
| --- | --- |
| 冻结输入（已有不同内容拒绝） | julia +1.12.6 --project=. scripts/freeze_r4_baseline.jl |
| 数学/兼容回归 | julia +1.12.6 --project=. scripts/test_r4.jl |
| 公式/API映射 | julia +1.12.6 --project=. scripts/check_r4_baseline.jl |
| 正式运行 | julia +1.12.6 --project=. scripts/study_r4_baseline.jl |
| 已存运行生成报告 | julia +1.12.6 --project=. scripts/report_r4_baseline.jl 路径/study.toml |
| 报告重绘 | julia +1.12.6 --project=docs scripts/plot_r4_baseline.jl results/summaries/r4-baseline |
| 已封存报告检查 | julia +1.12.6 --project=. scripts/check_r4_baseline.jl results/summaries/r4-baseline |

以上常用操作已配置为VS Code任务。执行脚本通过与原生任务UI触发成功分别记录。
报告/运行/图表拒绝覆盖原文件；重复实验或重绘请使用新的目录。
