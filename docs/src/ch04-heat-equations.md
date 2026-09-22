# 热状态相容性：公式、符号与映射

由docs/reading/ch04/heat-compatibility.toml生成；HC式均为项目推导。

## R4-HC1

~~~math
H_{ij}^{in}=c\,m_{ij}(S_i-R_{ij}^{out}),\qquad H_{ij}^{out}=c\,m_{ij}(S_{ij}^{out}-R_j)
\tag{R4-HC1}
~~~

两根供回水管作为一对；入口与出口指相同空间截面，回水方向与供水相反。c=cp/10^6。

API：[build_r4_heat_reconstruction](@ref PaperRebuild.build_r4_heat_reconstruction)；测试：R4-HC1。

## R4-HC2

~~~math
c\,m_{ij}(S_i-S_{ij}^{out})=\widehat L_{ij}^{S},\quad c\,m_{ij}(R_j-R_{ij}^{out})=\widehat L_{ij}^{R}
\tag{R4-HC2}
~~~

分别冻结供回参考损耗；两式相加恢复父运行的总损耗，但不等于真实温度相关散热。

API：[build_r4_heat_reconstruction](@ref PaperRebuild.build_r4_heat_reconstruction)；测试：R4-HC2。

## R4-HC3

~~~math
H_i^{src}=c\,m_i^{src}(S_i^{src}-R_i),\qquad H_i^{load}=c\,m_i^{load}(S_i-R_i^{load})
\tag{R4-HC3}
~~~

本地源、荷端口与网络混合温度分开，不强迫热源出口和混合供温相同。

API：[validate_r4_heat_reconstruction](@ref PaperRebuild.validate_r4_heat_reconstruction)；测试：R4-HC3。

## R4-HC4

~~~math
\begin{aligned}m_i^{src}S_i^{src}+\sum_{p\to i}m_p S_p^{out}&=(m_i^{load}+\sum_{i\to p}m_p)S_i,\\m_i^{load}R_i^{load}+\sum_{i\to p}m_p R_p^{out}&=(m_i^{src}+\sum_{p\to i}m_p)R_i.\end{aligned}
\tag{R4-HC4}
~~~

分别检查供水和回水的加权混合；正入流时独立重算混合温度，A1为1e-4 K。

API：[validate_r4_heat_reconstruction](@ref PaperRebuild.validate_r4_heat_reconstruction)；测试：R4-HC4。

## R4-HC5

~~~math
m_i^{src}+\sum_{p\to i}m_p=m_i^{load}+\sum_{i\to p}m_p,\qquad 0\le m_p\le u_p\overline m_p
\tag{R4-HC5}
~~~

质量守恒、方向与容量；所有设备/负荷/热交付和父费用冻结。

API：[reconstruct_r4_heat](@ref PaperRebuild.reconstruct_r4_heat)；测试：R4-HC5。

## 符号

|稳定ID|数学符号|Julia名称|含义/维度|单位|
|---|---|---|---|---|
|hc_mass|``m_{ij},m_i^{src},m_i^{load}``|m_pipe / m_source / m_load|供回管对质量流与非负源荷端口流；管道或节点×时间|kg/s|
|hc_node_temperatures|``S_i,R_i``|τ_S / τ_R|节点混合供温、混合回温；节点×时间；ASCII别名S/R|K|
|hc_port_temperatures|``S_i^{src},R_i^{load}``|τ_source / τ_load|源出口与荷出口温度；节点×时间；ASCII别名source/load|K|
|hc_pipe_temperatures|``S_{ij}^{out},R_{ij}^{out}``|τ_S_out / τ_R_out|供水沿i到j的出口、回水沿j到i的出口；方向弧×时间|K|
|hc_frozen_losses|``\widehat L_{ij}^{S},\widehat L_{ij}^{R}``|Ls / Lr|父输入参考温度、U和长度计算的冻结损耗；关闭管道为零|MW|

## 适用条件与疑点

### R4-HC-C01

父模型未把每管H与m、温度关联；20运行59处近零m正H。保存状态不相容不等于同控制不可重构。

新增独立核查，旧模型/原判定不改。

### R4-HC-C02

第4章指向文献[26]，原参考文献确为Khatibi等2021接受稿；尚未得到逐管方程等价证据。

本批HC方程作为守恒推导的项目核查，不冒称恢复了作者未公开实现。

### R4-HC-C03

父输入只有参考绝对温度和端口温差上下界，缺少完整节点/管道绝对温度带。

实验前冻结参考±10K和±20K两带；带内失败不推论全温区不可行。

### R4-HC-C04

固定损耗与真实温变散热不同；无压力、泵、时延及开关瞬态。

通过只认证声明的稳态热相容性，不称完整热物理成功。

### R4-HC-C05

父保存浮点数的守恒残差不为严格零；精确冻结所有等式可能造成数值矛盾。

匹配热交付/固定流量时用原A1的十分之一带宽，独立门槛仍为原A1；保存最大残差。
