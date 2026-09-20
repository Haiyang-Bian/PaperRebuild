function r7_linked_science_paths()
    paths=merge(r7_planning_science_paths(), r7_transport_science_paths())
    root=normpath(joinpath(@__DIR__, "..", ".."))
    for layer in ("core", "formulations", "verification", "algorithms", "reporting")
        p="src/$layer/r7_linked_planning.jl"
        paths[p]=joinpath(root, split(p, '/')...)
    end
    paths["src/networks/r7_linked_state.jl"]=joinpath(root, "src/networks/r7_linked_state.jl")
    paths
end
r7_linked_science_hashes() =
    Dict(p=>bytes2hex(sha256(read(f))) for (p, f) in r7_linked_science_paths())

function r7_linked_check_record(c, s, r)
    q=validate_r7_linked_planning(c, s, r)
    isequal(q, r["validation"]) &&
    r["candidate_accepted"]==q["robust_model_pass"] &&
    r["conditional_cost_complete"]==q["conditional_optimality_pass"] ||
        error("详细规划原值与摘要不同")
    q
end

"""
    save_r7_linked_planning(case, spec, result, directory)

保存R7-L3规划的共同正常输入、全部事件流量、原值、历史连接、状态与冻结源码，拒绝覆盖旧目录。
源码变化须先保存新的运行；冻结入口可在后续代码修改后重验，不能重新优化代替原值检查。
"""
function save_r7_linked_planning(c, s, r, directory::AbstractString)
    r["source_hashes_at_solve"]==r7_linked_science_hashes() || error("详细规划求解后源码变化")
    r7_linked_check_record(c, s, r)
    dest=abspath(directory)
    ispath(dest)&&error("不覆盖详细规划运行")
    stage=dest*".writing-"*string(uuid4())
    mkpath(stage)
    for (p, data) in (
        "normal.toml"=>c.normal.data,
        "planning.toml"=>c.specification,
        "spec.toml"=>s,
        "result.toml"=>r,
    )
        write(joinpath(stage, p), r7_text(data))
    end
    includes=String[]
    function add(p)
        push!(includes, "src/"*p)
    end
    for name in ("recovery", "adversary")
        for layer in ("core", "formulations", "verification", "algorithms", "reporting")
            add("$layer/r7_$name.jl")
        end
    end
    for p in (
        "core/r7_commitment.jl",
        "components/r7_commitment.jl",
        "verification/r7_commitment.jl",
        "networks/r7_pipe_state.jl",
        "networks/fixed_flow_heat.jl",
    )
        add(p)
    end
    for name in ("thermal", "transport", "normal", "planning", "linked_planning")
        add("core/r7_$name.jl")
        name=="normal" && add("networks/r7_normal_transport.jl")
        name=="linked_planning" && add("networks/r7_linked_state.jl")
        for layer in ("formulations", "verification", "algorithms", "reporting")
            add("$layer/r7_$name.jl")
        end
    end
    paths=r7_linked_science_paths()
    Set(includes)==setdiff(
        Set(keys(paths)),
        Set(["src/PaperRebuild.jl", "Project.toml", "Manifest.toml"]),
    ) || error("详细规划冻结源码依赖清单不一致")
    for (p, f) in paths
        target=joinpath(stage, "code", split(p, '/')...)
        mkpath(dirname(target))
        cp(f, target)
    end
    replay="module FrozenR7Linked\nusing JuMP,TOML,SHA,Dates,UUIDs\nconst MOI=JuMP.MOI\n" *
           join("include(\"$p\")\n" for p in includes) *
           "end\nx=FrozenR7Linked.read_r7_linked_planning(joinpath(@__DIR__,\"..\"))\nprintln(x.result[\"status\"],\" linked=\",x.validation[\"robust_model_pass\"])\n"
    write(joinpath(stage, "code/replay.jl"), replay)
    files=Dict(
        replace(relpath(joinpath(p, f), stage), '\\'=>'/')=>bytes2hex(sha256(read(joinpath(p, f))))
        for (p, _, fs) in walkdir(stage) for f in fs
    )
    write(joinpath(stage, "files.toml"), r7_text(Dict("files"=>files)))
    mv(stage, dest)
    read_r7_linked_planning(dest)
    dest
end

"""只读核验详细规划全部原值、输入/源码哈希及逐轮证据；拒绝篡改或用当前源码冒充历史版本。"""
function read_r7_linked_planning(directory::AbstractString)
    hashes=TOML.parsefile(joinpath(directory, "files.toml"))["files"]
    required=Set(
        vcat(
            ["normal.toml", "planning.toml", "spec.toml", "result.toml", "code/replay.jl"],
            ["code/"*p for p in keys(r7_linked_science_paths())],
        ),
    )
    Set(keys(hashes))==required || error("详细规划清单缺项")
    actual=Set(
        replace(relpath(joinpath(p, f), directory), '\\'=>'/') for (p, _, fs) in walkdir(directory)
        for f in fs
    )
    actual==union(required, Set(["files.toml"])) || error("详细规划文件集合变化")
    for (p, h) in hashes
        !isabspath(p)&&!occursin(':', p)&&!occursin('\\', p)&&all(
            x->!(x in ("", ".", "..")),
            split(p, '/'),
        ) || error("存档路径非法")
        bytes2hex(sha256(read(joinpath(directory, split(p, '/')...))))==h ||
            error("详细规划存档篡改")
    end
    c=load_r7_planning_case(
        joinpath(directory, "normal.toml"),
        joinpath(directory, "planning.toml"),
    )
    s=TOML.parsefile(joinpath(directory, "spec.toml"))
    r=TOML.parsefile(joinpath(directory, "result.toml"))
    r["source_hashes_at_solve"]==r7_linked_science_hashes() || error("请使用冻结code/replay.jl重验")
    all(hashes["code/"*p]==h for (p, h) in r["source_hashes_at_solve"]) || error("源码副本身份错误")
    q=r7_linked_check_record(c, s, r)
    (; case = c, spec = s, result = r, validation = q)
end
