using PaperRebuild, TOML, SHA
root=normpath(joinpath(@__DIR__, ".."))
path=joinpath(root, "configs", "r4", "thermal-study.toml")
ispath(path) && error("不覆盖已冻结规则")
names=["open", "import", "electric_bottleneck", "heat_bottleneck"]
inputs=Dict(
    name=>load_r4_case(joinpath(root, "configs", "r4", "reconfiguration", name*".toml")).sha256 for
    name in names
)
records=[
    Dict("id"=>name*"--"*policy*"--"*loss, "case"=>name, "policy"=>policy, "loss"=>loss) for
    name in names for policy in ("fixed", "joint") for loss in ("reference", "exponential")
]
rules=Dict(
    "schema"=>"r4-thermal-study-v1",
    "origin"=>"synthetic",
    "records"=>records,
    "input_sha256"=>inputs,
    "budget_sec"=>600.0,
    "electric"=>"exact",
    "supply_K"=>[343.15, 363.15],
    "return_K"=>[303.15, 323.15],
    "flow_floor"=>1e-4,
    "idle_rule"=>"decoupled_steady_no_transport",
    "bypass"=>"absent",
    "pressure_pumps_dynamics"=>false,
    "parent_batch"=>"r4-network-20260919",
    "acceptance"=>"Unchanged A1 and A2; temperature 1e-4K; failures/timeouts retained.",
    "comparison"=>"Reference versus exponential changes only running-pipe heat loss. Both add idle/temperature/mixing relative to the parent model; the legacy comparison is a combined model change.",
    "initialization"=>"No parent incumbent or reference temperature solution injected.",
    "cost_scope"=>"Resource, discomfort, grid and switching; no pump cost or idle restart energy.",
)
write(path, PaperRebuild.r4_text(rules))
println(
    "Frozen 16 runs, unchanged four parent inputs, before formal optimization: ",
    bytes2hex(sha256(read(path))),
)
