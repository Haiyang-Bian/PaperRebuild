# 可选Gurobi入口预检：只确认有效参数，不生成正式研究结论。
include("r4_setup.jl")
base=r4_optimizer(:gurobi)
tight=optimizer_with_attributes(base.optimizer_constructor, base.params..., "BarQCPConvTol"=>1e-9)
for (name, factory, expected) in (("original", base, 1e-6), ("qcp_1e9", tight, 1e-9))
    m=Model(factory)
    actual=get_optimizer_attribute(m, "BarQCPConvTol")
    @assert actual==expected
    println(name, ": BarQCPConvTol=", actual)
end
