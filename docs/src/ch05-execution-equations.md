# 市场执行选择：公式与符号

由execution.toml生成。R5-EX为项目执行规则，不冒用作者式号或市场制度。

## R5-EX1

~~~math
y^\dagger=\arg\min_{y\in Y,\ c(o)^\mathsf Ty=f^\star(o)}\frac12\sum_k(y_k/s_P)^2
\tag{R5-EX1}
~~~

先保持原市场最优值，再对全部成交作严格凸最小范数选择；不是给原福利目标加epsilon。

原式：5-34至5-42；API：[`build_r5_execution_selector`](@ref)；测试：`R5-EX 市场唯一选择与固定交付`。

## R5-EX2

~~~math
\xi^\dagger=\arg\min_{\xi\in\mathcal D(o),\ D(\xi)=f^\star(o)}\frac12\sum_j(\xi_j/(\Delta t\,s_\pi))^2
\tag{R5-EX2}
~~~

对原独立对偶的全部显式乘子采用统一正权重，选出唯一价格；不隐式设置乘子界。规则依赖声明的对偶表示。

原式：5-43至5-58；API：[`solve_r5_market_execution`](@ref)；测试：`R5-EX 单位尺度与选择证书`。

## R5-EX3

~~~math
Hx+A^\mathsf T\mu=0,\quad d(\mu)=b^\mathsf T\mu-\tfrac12(A^\mathsf T\mu)^\mathsf TH^{-1}(A^\mathsf T\mu)
\tag{R5-EX3}
~~~

选择QP行按Ax+b<=0或=0保存；H正对角。由原始MOI乘子独立核验驻点、符号、互补与原对偶差。

原式：项目选择问题KKT；API：[`validate_r5_market_execution`](@ref)；测试：`R5-EX 严格凸选择与原始乘子`。

## R5-EX4

~~~math
(P_t^{DA},R_t^U,R_t^D)=(P_t^{IES,\dagger},R_t^{IES,U,\dagger},R_t^{IES,D,\dagger}),\quad C_{\rm exec}=\Pi(y^\dagger,\xi^\dagger)+\min_{\text{recourse}}\sup_{p\in\mathcal P}\sum_s p_sQ_s
\tag{R5-EX4}
~~~

固定市场实际成交，在原风险/设备/历史边界下重新求补救；原变量界保持，条件最优界不作为策略报价全局界。

原式：5-33、5-66、5-68；API：[`evaluate_r5_execution_delivery`](@ref)；测试：`R5-EX 市场唯一选择与固定交付`。

## 符号与作用域

| ID | 数学符号 | 含义 | 单位 | Julia映射 | 作用域 |
|---|---|---|---|---|---|
| R5-EX-S01 | ``f^\star(o)`` | 给定报价的原市场LP最优目标 | USD | `primary / clearing_objective` | 由独立原始/对偶见证认证；固定普通负荷效用常数仍省略 |
| R5-EX-S02 | ``y^\dagger,\xi^\dagger`` | 唯一选择的成交向量与完整显式市场乘子 | MW；USD/MW | `market[values / multipliers]` | 乘子除以dt才为USD/MWh；不是选择QP的原始MOI对偶 |
| R5-EX-S03 | ``s_P,s_\pi`` | 统一数量和价格参考尺度 | MW；USD/MWh | `R5MarketExecutionSpec` | 预声明1MW和100USD/MWh，统一缩放不改变数学最优选择 |
| R5-EX-S04 | ``H,\mu`` | 严格凸选择QP的正对角Hessian和规范方向乘子 | 按选择问题归一化 | `witness[system][h] / raw_duals` | 原始MOI乘子保持；不裁剪；独立对偶值检验 |

## 原文、采用解释与证据

### R5-EX-C01

**原文：**已核读原式定义市场福利与KKT，没有给出多最优选择的完整执行细则。

**采用解释：**选择最小范数制度作为单独项目对照；不冒称作者规则、现实市场制度或悲观策略解。

**证据与边界：**原最优值、唯一选择证书和内部交付分别保存。

### R5-EX-C02

**原文：**原始成交与对偶价格都可能多解；有限报价不保证有限价格面。

**采用解释：**严格凸且强制的平方范数在非空闭最优面上取得唯一最小值；即使原面无界也不需要价格截断。

**证据与边界：**解析QP、原始乘子、单位尺度和稀缺价格反例；价格选择依赖完整声明的对偶表示。

### R5-EX-C03

**原文：**旧策略最优解依赖乐观原始/对偶选择。

**采用解释：**旧报价在新制度下只作执行评价，不能把固定报价/成交后的条件补救界称策略全局界。

**证据与边界：**旧选定、旧独立和新选择成交分别固定；不调整成交制造可交付性，不覆盖历史结果。
