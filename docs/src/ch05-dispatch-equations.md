# 第5章确定性补救：原式与符号

由docs/reading/ch05/dispatch.toml生成；原PDF85–88，建筑对照PDF43。
为展示省略共同量词；原冲突下标保留，采用方程单独解释。不是全文公式审核完成。
见[物理补救说明](ch05-dispatch.md)及[`build_r5_dispatch`](@ref)。

## 式（5-1）

~~~math
P^{PCC}_{t\omega}=P^{PCC}_t+P^{PCC,dev}_{t\omega}
\tag{5-1}
~~~

采用解释：正购电。另定义交付d=P_DA-P_actual；保留原加号，不把两种偏差定义混用。

## 式（5-2）

~~~math
r^R_{t\omega}=\alpha^{R,U}_{t\omega}R^{PCC,U}_t-\alpha^{R,D}_{t\omega}R^{PCC,D}_t
\tag{5-2}
~~~

采用解释：上备用减少购电，下备用增加购电；本批alpha与成交均为给定数值。

## 式（5-3）

~~~math
P^{mis}_{t\omega}=|r^R_{t\omega}-P^{PCC,dev}_{t\omega}|
\tag{5-3}
~~~

采用解释：采用|request-d|；非负上图变量有严格正罚价，另验算其是否取等。

## 式（5-4）

~~~math
0\le\sum_tP^{mis}_{t\omega}\le\delta\sum_t(R^{PCC,U}_t+R^{PCC,D}_t)
\tag{5-4}
~~~

采用解释：两侧乘dt得到MWh；分母是成交容量累计量，不擅自改成实际调用量。

## 式（5-5）

~~~math
\min\ C^{E\&RM}+C^{RT,C}+C^{RT,M}
\tag{5-5}
~~~

采用解释：固定成交下一条已知轨迹的净费用；不是上层策略优化或随机期望。

## 式（5-6）

~~~math
C^{E\&RM}=\sum_t(\lambda^E_{Mt}P^{PCC}_t-\lambda^{R,U}_tR^{PCC,U}_t-\lambda^{R,D}_tR^{PCC,D}_t)
\tag{5-6}
~~~

采用解释：分别按USD/MWh与USD/(MW*h)恢复dt；市场价可以为负。

## 式（5-7）

~~~math
C^{RT,C}=\sum_\omega\pi_\omega\sum_t(\sum_{g\in\mathcal G^{CHP}}c_g^{CHP}P^{CHP}_{gt\omega}+\sum_{g\in\mathcal G^{PV}}c_g^{PV}P^{PV}_{gt\omega})
\tag{5-7}
~~~

采用解释：本批退化为一个情景；按设备显式单位费用计入GT等有成本设备，原式没有单列GT的缺口保留。

## 式（5-8）

~~~math
C^{RT,M}=\sum_\omega\pi_\omega\sum_t(-\lambda^{RT}_{Mt\omega}P^{PCC,dev}_{t\omega}+\lambda^{pen}P^{mis}_{t\omega})
\tag{5-8}
~~~

采用解释：与正交付d保持一致：-price_RT*d+penalty*abs(request-d)，全部乘dt。

## 式（5-9）

~~~math
\underline P_g^c\le P^c_{gt\omega}\le\overline P_g^c,\quad-\overline Q_g^c\le Q^c_{gt\omega}\le\overline Q_g^c,\quad c\in\{CHP,GT,PV,EB\}
\tag{5-9}
~~~

采用解释：有功P为发电或EB非负耗电；Q统一为有符号净注入，逐设备有限上下界；PV另有可用轨迹。

## 式（5-10）

~~~math
-RD_g\le P^c_{gt\omega}-P^c_{g,t-1,\omega}\le RU_g,\quad c\in\{CHP,GT\}
\tag{5-10}
~~~

采用解释：显式初始出力，MW/h爬坡乘dt。

## 式（5-11）

~~~math
H^{CHP}_{gt\omega}=\eta_g^{CHP}P^{CHP}_{gt\omega}
\tag{5-11}
~~~

采用解释：常热电比，按source_id汇总到非负流量源端口。

## 式（5-12）

~~~math
H^{EB}_{gt\omega}=COP_g^{EB}P^{EB}_{gt\omega}
\tag{5-12}
~~~

采用解释：EB有功为耗电，电平衡扣除、热平衡增加。

## 式（5-13）

~~~math
P^{PCC}_{t\omega}=\sum_{b:1\to b}P_{1b,t\omega}
\tag{5-13}
~~~

采用解释：采用根节点守恒；若根节点有本地负荷/设备也计入，原无根负荷特例自动退化为该式。

## 式（5-14）

~~~math
\sum_{g\in\mathcal G_n^{CHP}}P^{CHP}_{gt\omega}+\sum_{g\in\mathcal G_n^{EB}}P^{EB}_{gt\omega}+\sum_{g\in\mathcal G_n^{PV}}P^{PV}_{gt\omega}+P_{mn,t\omega}=\sum_{b:n\to b}P_{nb,t\omega}+P^D_{nt\omega}
\tag{5-14}
~~~

采用解释：按元件和守恒恢复GT发电，EB及本地加热在耗电端；不复制原EB正供给项。

## 式（5-15）

~~~math
\sum_{g\in\mathcal G_n^{CHP}}Q^{CHP}_{gt\omega}+Q_{mn,t\omega}=\sum_{b:n\to b}Q_{nb,t\omega}+Q^D_{nt\omega}
\tag{5-15}
~~~

采用解释：按各设备显式Q净注入边界求和；本批合成EB/PV设Q=0，本地加热采用单位功率因数。

## 式（5-16）

~~~math
v_{nt\omega}=v_{mt\omega}-(r_{mn}P_{mn,t\omega}+x_{mn}Q_{mn,t\omega})/v_0
\tag{5-16}
~~~

采用解释：v为幅值pu，P/Q除S_base_MVA，r/x为pu；损耗忽略，不当作交流支路等式认证。

## 式（5-17）

~~~math
\underline V\le v_{nt\omega}\le\overline V
\tag{5-17}
~~~

采用解释：根电压固定，逐节点界；另加显式P/Q线路运行盒界，不能称MVA圆形容量。

## 式（5-18）

~~~math
\sum_{g\in\mathcal G_j^{CHP}}H^{CHP}_{gt\omega}+\sum_{g\in\mathcal G_j^{EB}}H^{EB}_{gt\omega}=c_w\hat m_{jt}(\tau^S_{jt\omega}-\tau^R_{jt\omega})
\tag{5-18}
~~~

采用解释：源端口流量非负；源出温与节点供水混合温度分开。c为J/(kg*K)，热功率除1e6为MW。

## 式（5-19）

~~~math
H^D_{jt\omega}=-c_w\hat m_{jt}(\tau^S_{jt\omega}-\tau^R_{jt\omega})
\tag{5-19}
~~~

采用解释：负荷端口以非负取水流量表示，H_D=cp*m_load*(S_node-R_load)，不对负流量套正界。

## 式（5-20）

~~~math
\sum_{j:j\to k}\hat m_{jk,t}\tau^{S,out}_{jk,t\omega}+\hat m_{kt}\tau^S_{kt\omega}=(\sum_{j:j\to k}\hat m_{jk,t}+\hat m_{jt})\tau^{S,mix}_{jt\omega}
\tag{5-20}
~~~

采用解释：原右侧节点下标不一致，采用显式入流焓/总出流混合，见项目R5-D3。

## 式（5-21）

~~~math
\sum_{l:l\to k}\hat m_{kl,t}\tau^{R,out}_{lk,t\omega}+\hat m_{kt}\tau^R_{kt\omega}=(\sum_{l:l\to k}\hat m_{kl,t}+\hat m_{jt})\tau^{R,mix}_{jt\omega}
\tag{5-21}
~~~

采用解释：保留原印刷下标问题；回水按反向管道入流加负荷出口，独立于供水混合。

## 式（5-22）

~~~math
\tau^{S,in}_{jk,t\omega}=\tau^{S,mix}_{jt\omega},\quad\tau^{R,in}_{kj,t\omega}=\tau^{R,mix}_{kt\omega}
\tag{5-22}
~~~

采用解释：一对供回水管共用正向供水索引，回水入口取to节点，不互换历史。

## 式（5-23）

~~~math
\tau^S_{jt\omega}=\tau^{S,mix}_{jt\omega}\ (j\in\mathcal J^S),\quad\tau^R_{jt\omega}=\tau^{R,mix}_{jt\omega}\ (j\in\mathcal J^D)
\tag{5-23}
~~~

采用解释：在源/荷端口与网络混合节点间按实际水流连接；一般源混合节点不能强令源出口等于混合温度。

## 式（5-24）

~~~math
\underline\tau^{S,mix}\le\tau^{S,mix}_{jt\omega}\le\overline\tau^{S,mix},\quad\underline\tau^{R,mix}\le\tau^{R,mix}_{jt\omega}\le\overline\tau^{R,mix}
\tag{5-24}
~~~

采用解释：节点供回水与端口温度界分别声明。

## 式（5-25）

~~~math
\tau^{S/R,out,*}_{jk,t\omega}=\sum_{\zeta=1}^tK_{jk,t\zeta}\tau^{S/R,in}_{jk,\zeta\omega}+\hat\tau^{S/R,out,*}_{jk,t}
\tag{5-25}
~~~

采用解释：固定正流量的精确时段质量重叠，非整步两段加权；前窗入口历史显式给定。

## 式（5-26）

~~~math
\tau^{S/R,out}_{jk,t\omega}=\hat\tau_t^{AM}+J_{jk,t}(\tau^{S/R,out,*}_{jk,t\omega}-\hat\tau_t^{AM})
\tag{5-26}
~~~

采用解释：沿用2-50的作者节点法J，独立验算；不是连续PDE精确衰减，C08适用边界保留。

## 式（5-27）

~~~math
\eta^H H^D_{jt\omega}+U_j(\hat\tau_t^{AM}-\tau^{IN}_{jt\omega})=\tau^{IN}_{jt\omega}-\tau^{IN}_{j,t-1,\omega}
\tag{5-27}
~~~

采用解释：依据2-72及总热定义改为H_D+H_DH，η=dt/C、U=dt*G/C；项目物理参数显式输入。

## 式（5-28）

~~~math
\underline\tau^{IN}\le\tau^{IN}_{jt\omega}\le\overline\tau^{IN}
\tag{5-28}
~~~

采用解释：本批硬舒适界，未启用风险开关；初温与free/initial终端规则显式给定。

## 式（5-29）

~~~math
P^D_{jt\omega}=\hat P^D_{jt\omega}+P^{DH}_{jt\omega}
\tag{5-29}
~~~

采用解释：采用hat P为基础电负荷，本地加热额外耗电；不再把正文所称总电负荷重复计入。

## 式（5-30）

~~~math
H^D_{jt\omega}=\hat H^D_{jt\omega}-H^{DH}_{jt\omega}
\tag{5-30}
~~~

采用解释：总受热等于区供热加本地热；没有单独固定一个与室温动态不一致的热需求。

## 式（5-31）

~~~math
0\le P^{DH}_{jt\omega}\le\overline P^{DH}_j,\quad H^{DH}_{jt\omega}=\eta^{DH}_jP^{DH}_{jt\omega}
\tag{5-31}
~~~

采用解释：P_DH额定值明确按电输入MW；合成COP显式提供，不使用原表5-4尚未核清的容量口径。

## 符号表

| ID / 原符号 | 含义 / 类别 | 单位 / 定义域 | Julia / 维度 | 来源 |
|---|---|---|---|---|
| D-PCC / ``P^{PCC}_t,P^{PCC}_{t\omega}`` | 日前与实际正购电 / 参数/变量 | MW / 有限非负购电边界 | `award.P_DA_MW / P_PCC` / time / PCC×time | 5-1/5-13；正交付另定义 |
| D-reserve / ``R_t^{PCC,U/D},\alpha_t^{U/D},r_t`` | 中标备用、调用比例与净请求 / 给定参数 | MW / 1 / MW / 容量非负；alpha∈[0,1] | `R_up_MW,R_down_MW,alpha_up,alpha_down` / time | 5-2 |
| D-delivery / ``d_t,e_t`` | 减少购电的正交付及绝对误差 / 变量 | MW / 有界有符号交付；误差非负 | `delivery,mismatch` / PCC×time | 项目R5-D1；5-3/5-4 |
| D-CG / ``C_j,G_j,\eta_j^H,U_j`` | 热容、传热与步长对应离散系数 / 参数 | MWh/K / MW/K / K/MW / 1 / C>0,G≥0 | `C_MWh_K,G_MW_K,η_H,U` / building | 项目R5-D2；2-72/5-27 |
| D-building / ``\tau^{IN}_{jt},H^D_{jt},H^{DH}_{jt},P^{DH}_{jt}`` | 室温、区供热、本地产热与用电 / 变量 | K / MW / MW / MW / 有限舒适界与非负热功率 | `τ_IN,H_D,COP_DH*P_DH,P_DH` / building×time | 5-27至5-31；总受热修正 |
| D-device / ``P^c_{gt},Q^c_{gt}`` | 元件有功及有符号无功注入 / 变量 | MW / Mvar / P≥0；EB为耗电；Q有限双侧界 | `P_DER,Q_DER` / device×time | 5-9至5-12 |
| D-electric / ``P_{mn,t},Q_{mn,t},v_{nt}`` | 线性配电网支路功率和电压幅值 / 变量 | MW / Mvar / pu / 有符号功率盒界和幅值界 | `P_line,Q_line,v` / line×time / node×time | 5-13至5-17 |
| D-flow / ``\hat m_p,m_s,m_j`` | 固定管流、源注入与负荷取水 / 参数 | kg/s / 严格正；逐节点守恒 | `pipes/sources/buildings.m_kg_s` / pipe / source / building | 5-18至5-23；项目非负端口映射 |
| D-nodeT / ``\tau^{S,mix}_{nt},\tau^{R,mix}_{nt}`` | 供回水节点混合温度 / 变量 | K / 有限节点温度界 | `τ_S,τ_R` / heat node×time | 5-20至5-24；采用入流守恒 |
| D-portT / ``\tau^{S,src}_{st},\tau^{R,load}_{jt}`` | 源出口及用户回水出口 / 变量 | K / 有限端口温度界 | `τ_src,τ_load_R` / source×time / building×time | 项目R5-D3；不与混合节点静默等同 |
| D-pipeT / ``\tau^{S/R,out}_{pt},K_{pt\zeta},J_p`` | 管道出口、质量重叠权重及作者衰减 / 变量/参数 | K / 1 / 1 / 权重非负和为1；0<J≤1 | `τ_pipe_S,τ_pipe_R,kernel.weights,kernel.J` / pipe×time / two lags / pipe | 5-25/5-26；2-47至2-54恒流特例 |
| D-money / ``\lambda^E,\lambda^{RU/RD},\lambda^{RT},\lambda^{pen},c_g`` | 市场价格、罚价和元件费用 / 给定参数 | USD/MWh；容量价USD/(MW*h) / 市场价有限有符号；罚价>0；设备费用≥0 | `energy_price,up_price,down_price,price,penalty_USD_MWh,cost_USD_MWh` / time / scalar / device | 5-5至5-8；显式dt |

## 采用边界

- R5-D01：正交付d=日前-实际；(5-1)加号与(5-3)/(5-8)组合不可混用。手算上下备用与结算检查。
- R5-D02：2-72使用总热量，5-27采用H_D+H_DH；C/G是项目物理恢复，原系数跨时间步不得直接复用。
- R5-D03：EB耗电、GT发电与成本恢复；Q统一净注入，本地加热功率因数1。没有存储设备，不擅自加入。
- R5-D04：固定正流量、显式历史；按关联关系分别混合供回水，不复制5-20/21/23冲突下标。作者J离散近似边界保留。
- R5-D05：线性幅值配电网不认证AC；P/Q盒界、初温与终端规则是显式补全，不计水压/泵耗。
- R5-D06：固定成交、完整已知一条轨迹；不称在线控制、策略报价、DRO或概率可靠性。备用考核按成交容量累计量归一化。
