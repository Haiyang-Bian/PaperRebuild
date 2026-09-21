function r8_includes()
    vcat(
        r7_flow_planning_includes(),
        [
            "src/$layer/r8_tradeoff.jl" for
            layer in ("core", "formulations", "verification", "algorithms", "reporting")
        ],
    )
end
function r8_science_paths()
    root=normpath(joinpath(@__DIR__, "..", ".."))
    Dict(
        p=>joinpath(root, split(p, '/')...) for
        p in vcat(r8_includes(), ["src/PaperRebuild.jl", "Project.toml", "Manifest.toml"])
    )
end
r8_science_hashes() = Dict(p=>bytes2hex(sha256(read(f))) for (p, f) in r8_science_paths())

"""保存R8原始主阶段、固定计划恢复评估、输入与科学源码；拒绝覆盖或求解后源码改变。"""
function save_r8_run(c, flow, s, r, directory::AbstractString)
    r["source_hashes_at_solve"]==r8_science_hashes() || error("R8求解后源码变化")
    isequal(validate_r8_solution(c, flow, s, r), r["validation"]) || error("R8摘要不一致")
    dest=abspath(directory)
    ispath(dest)&&error("不覆盖R8记录")
    stage=dest*".writing-"*string(uuid4())
    mkpath(stage)
    for (p, x) in (
        "normal.toml"=>c.normal.data,
        "planning.toml"=>c.specification,
        "flow.toml"=>flow,
        "spec.toml"=>s,
        "result.toml"=>r,
    )
        write(joinpath(stage, p), r7_text(x))
    end
    for (p, f) in r8_science_paths()
        target=joinpath(stage, "code", split(p, '/')...)
        mkpath(dirname(target))
        cp(f, target)
    end
    replay="module FrozenR8\nusing JuMP,TOML,SHA,Dates,UUIDs\nconst MOI=JuMP.MOI\n" *
           join("include(\"$p\")\n" for p in r8_includes()) *
           "end\nx=FrozenR8.read_r8_run(joinpath(@__DIR__,\"..\"))\nprintln(x.result[\"run_id\"])\n"
    write(joinpath(stage, "code/replay.jl"), replay)
    hashes=Dict(
        replace(relpath(joinpath(p, f), stage), '\\'=>'/')=>bytes2hex(sha256(read(joinpath(p, f))))
        for (p, _, fs) in walkdir(stage) for f in fs
    )
    write(joinpath(stage, "files.toml"), r7_text(Dict("files"=>hashes)))
    mv(stage, dest)
    read_r8_run(dest)
    dest
end

"""校验R8完整文件集合、哈希和原始数值；旧科学源码用存档code/replay.jl独立重读。"""
function read_r8_run(directory::AbstractString)
    hashes=TOML.parsefile(joinpath(directory, "files.toml"))["files"]
    required=Set(
        vcat(
            [
                "normal.toml",
                "planning.toml",
                "flow.toml",
                "spec.toml",
                "result.toml",
                "code/replay.jl",
            ],
            "code/" .* collect(keys(r8_science_paths())),
        ),
    )
    Set(keys(hashes))==required || error("R8存档清单缺失")
    actual=Set(
        replace(relpath(joinpath(p, f), directory), '\\'=>'/') for (p, _, fs) in walkdir(directory)
        for f in fs
    )
    actual==union(required, Set(["files.toml"])) || error("R8存档文件集合改变")
    for (p, h) in hashes
        !isabspath(p)&&!occursin(':', p)&&!occursin('\\', p)&&all(
            x->!(x in ("", ".", "..")),
            split(p, '/'),
        ) || error("R8路径越界")
        bytes2hex(sha256(read(joinpath(directory, split(p, '/')...))))==h || error("R8存档篡改")
    end
    c=load_r7_planning_case(
        joinpath(directory, "normal.toml"),
        joinpath(directory, "planning.toml"),
    )
    f, s, r=[TOML.parsefile(joinpath(directory, p*".toml")) for p in ("flow", "spec", "result")]
    r["source_hashes_at_solve"]==r8_science_hashes() || error("请用冻结R8入口重读")
    all(hashes["code/"*p]==h for (p, h) in r["source_hashes_at_solve"]) || error("R8源码副本错误")
    q=validate_r8_solution(c, f, s, r)
    isequal(q, r["validation"]) || error("R8原值与摘要不同")
    (; case = c, flow = f, spec = s, result = r, validation = q)
end
