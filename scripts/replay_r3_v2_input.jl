include("r3_setup.jl")
using Clarabel

# 干净克隆也可读取精确初值；检查模式不申请许可、不启动优化。
length(ARGS) in (2, 3) || error("usage: replay_r3_v2_input.jl INPUT_MANIFEST ID [--check-only]")
check_only = length(ARGS)==3
check_only && ARGS[3]!="--check-only" && error("未知选项")
manifest_path = abspath(ARGS[1])
manifest = TOML.parsefile(manifest_path)
selected = filter(e->e["id"]==ARGS[2] || (check_only && ARGS[2]=="all"), manifest["runs"])
isempty(selected) && error("未知实验ID")
for e in selected
    path = normpath(joinpath(dirname(manifest_path), e["case_file"]))
    dirname(path)==dirname(manifest_path) || error("案例路径越界")
    c = load_r2_case(path)
    c.sha256==e["input_sha256"] || error("案例哈希失配")
    initial = e["group"]=="robustness" ? PaperRebuild.r2_flow_matrix(c, e["initial_flow"]) : nothing
    if !isnothing(initial)
        PaperRebuild.r2_flow_hash(initial)==e["initial_flow_sha256"] || error("初值哈希失配")
    end
    operation = e["group"]=="modes" ? R3OperationSpec(c; mode = Symbol(e["mode"])) : nothing
    if check_only
        println("CHECKED ", e["id"])
        continue
    end
    @eval using Gurobi
    factory = r3_gurobi_factory(Gurobi)
    r =
        get(e, "method", "pg")=="reference" ?
        solve_r3_reference(c; operation, optimizer = factory, budget_sec = e["budget_sec"]) :
        solve_r3_projected_gradient(
            c;
            algorithm = :r3_pg_checked_v2,
            operation,
            initial_flow = initial,
            local_halfspace = get(e, "local_halfspace", true),
            optimizer = factory,
            convex_optimizer = Clarabel.Optimizer,
            budget_sec = e["budget_sec"],
            max_iterations = e["max_iterations"],
        )
    r["parent_run_id"] = manifest["batch"]*"/"*e["source_run_id"]
    id = "r3-v2-replay-"*e["id"]*"-"*string(uuid4())[1:8]
    directory = save_r3_run(c, r; run_id = id)
    validation = read_r3_run(directory).validation
    println(directory, " physical_pass=", validation.physical_pass)
end
