# R4热状态相容性与保持控制量的重构

## 1. 本批问题

[重构实验](ch04-network-results.md)在20个运行的59个弧时段中发现近零质量流仍传正热量。
当前目的：固定设备出力、负荷、拓扑、管道热量及父运行费用，另找满足温度与混合关系的状态。
“现存状态有问题”和“同控制不存在可行热状态”是两个不同命题。

原页PDF66–67列出(4-41)–(4-47)，PDF149确认[26]为Khatibi等2021论文。
[大学托管接受稿](https://vbn.aau.dk/ws/portalfiles/portal/433818534/Exploiting_Power_to_Heat_Assets_in_District_Heating_Networks_to_Regulate_Electric_Power_Network.pdf)
可检索部分显示其第IV节采用设备成本与聚合热量关系；本次PDF截图获取失败，
尚未建立逐管方程等价证据。本批使用显式守恒推导，不把引用关系当成物理完备性的证明。

## 2. 两层检查

**envelope：线性必要条件。**给定有限供回温边界，逐管显热只能位于流量乘温差的范围内。
供回管各自损耗也要求足够的流量/温降；同时检查端口、节点质量守恒及管道容量。
该层通过不保证所有温度能同时实现。

**mixing：稳态供回水相容性。**增加管道出口、节点混合以及本地源荷出口温度，
分别约束供水与回水焓流，不将两侧混合合并成一个节点净热量式。
流量乘温度导致非凸问题；由Gurobi寻找候选，再用保存数值独立回算。
未求得候选、求解器报告不可行和独立检查失败分别记录。

原式与项目推导、单位和代码映射见[五条HC方程](ch04-heat-equations.md)。
损耗仍按父输入的参考供回温冻结，没有升级成随实际温度变化的散热模型。
本批不检查水压、泵或时延，不能将通过写成完整热网认证。

## 3. 一个可手算的例子

两段90m管道，每对供/回管损耗分别为0.00126/0.00054 MW，cp=4180 J/(kg·K)，流量1 kg/s。
源供温353.15 K、末端回温313.15 K，则每段供水降0.3014354 K，沿反方向每段回水降0.1291866 K。
源产热为0.16828 MW，末端交付0.16468 MW，两对损耗合计0.0036 MW。
这些值同时满足双网络混合；单独令第二段质量流为零会失败，而允许质量流重构可恢复该手算状态。

测试R4-HC1至HC5同时覆盖这个证据、损耗方向、温度边界、零流量正热量、
容量不足、不可行证书不当候选、预算到期及存档篡改。

## 4. 冻结实验与判定

父批次为r4-network-20260919，34个整数运行；每个运行固定两组温度带：

| 项目温度带 | 供温K | 回温K |
|---|---|---|
| reference10 | 343.15–363.15 | 303.15–323.15 |
| reference20 | 333.15–373.15 | 293.15–333.15 |

这些是参考353.15/313.15 K的±10K、±20K诊断假设，不是论文参数。
每组完整核查共享600秒：固定质量流LP30秒、自由流LP30秒、固定流混合240秒、自由流混合300秒。
只有对应必要条件被求解器判为不可行，才跳过详细检查；数值失败不能替代不可行证据。
建模、求解及中间存档均受同一截止时间约束。

父浮点热量不改写；方程匹配内部带宽为原A1的十分之一，最后仍用原功率/流量A1及1e-4K温度门槛。
正入流时另算加权平均温度，避免微小质量流把很大的温度误差隐藏在很小的功率残差中。
费用来自未变的设备和负荷，重构目标为可行性常数零；不把它当作新的运行成本优化。

## 5. Julia与运行入口

~~~julia
using PaperRebuild
old = read_r4_run("results/runs/r4/r4-network-20260919/open--electric--exact")
spec = R4HeatCompatibilitySpec(level=:mixing, fixed_mass=false)
built = build_r4_heat_reconstruction(old.case, old.result; spec)
~~~

[build_r4_heat_reconstruction](@ref PaperRebuild.build_r4_heat_reconstruction)只建模；
[reconstruct_r4_heat](@ref PaperRebuild.reconstruct_r4_heat)预算内求解；
[validate_r4_heat_reconstruction](@ref PaperRebuild.validate_r4_heat_reconstruction)独立数值验算。
保存/重读用[save_r4_heat_run](@ref PaperRebuild.save_r4_heat_run)与
[read_r4_heat_run](@ref PaperRebuild.read_r4_heat_run)，均保留父调度的身份。

~~~powershell
julia +1.12.6 --startup-file=no --project=. scripts/test_r4_heat_compatibility.jl
julia +1.12.6 --startup-file=no --project=. scripts/test_r4_heat_compatibility.jl --gurobi
julia +1.12.6 --startup-file=no --project=. scripts/check_r4_heat_compatibility.jl
julia +1.12.6 --startup-file=no --project=. scripts/study_r4_heat_compatibility.jl
~~~

正式结果另存，旧运行与旧验收状态不迁移。见[272阶段结果与解析反例](ch04-heat-results.md)。
