const R7_ADVERSARY_REPORT_FILE = @__FILE__

function r7_adversary_science_paths()
    root=normpath(joinpath(@__DIR__, "..", ".."))
    merge(
        r7_recovery_science_paths(),
        Dict(
            "src/$layer/r7_adversary.jl" => joinpath(root, "src", layer, "r7_adversary.jl") for
            layer in ("core", "formulations", "verification", "algorithms", "reporting")
        ),
    )
end
r7_adversary_science_hashes() =
    Dict(p=>bytes2hex(sha256(read(f))) for (p, f) in r7_adversary_science_paths())

"""保存固定灾前状态的对手原值、恢复原值、对偶、源码与哈希；不覆盖旧目录，不重新求解。"""
function save_r7_adversary(c::R7RecoveryCase, r, directory::AbstractString)
    r["source_hashes_at_solve"]==r7_adversary_science_hashes() || error("求解后对手源码改变")
    isequal(validate_r7_adversary(c, r), r["validation"]) || error("对手原值与汇总不同")
    dest=abspath(directory)
    ispath(dest) && error("不覆盖已有对手运行")
    stage=dest*".writing-"*string(uuid4())
    mkpath(stage)
    write(joinpath(stage, "case.toml"), r7_text(c.data))
    write(joinpath(stage, "result.toml"), r7_text(r))
    paths=r7_adversary_science_paths()
    for (p, f) in paths
        target=joinpath(stage, "code", split(p, '/')...)
        mkpath(dirname(target))
        cp(f, target)
    end
    replay="module FrozenR7Inner\nusing JuMP,TOML,SHA,Dates,UUIDs\nconst MOI=JuMP.MOI\n" *
           join(
               "include(\"src/$layer/r7_$part.jl\")\n" for part in ("recovery", "adversary") for
               layer in ("core", "formulations", "verification", "algorithms", "reporting")
           ) *
           "end\nx=FrozenR7Inner.read_r7_adversary(joinpath(@__DIR__,\"..\"))\nprintln(x.result[\"status\"])\n"
    write(joinpath(stage, "code/replay.jl"), replay)
    files=Dict(
        replace(relpath(joinpath(p, f), stage), '\\'=>'/')=>bytes2hex(sha256(read(joinpath(p, f))))
        for (p, _, fs) in walkdir(stage) for f in fs
    )
    write(joinpath(stage, "files.toml"), r7_text(Dict("files"=>files)))
    mv(stage, dest)
    read_r7_adversary(dest)
    dest
end

"""按存档源码与原始数值只读重验内层故障对手；源码更新后应运行该存档code/replay.jl。"""
function read_r7_adversary(directory::AbstractString)
    files=TOML.parsefile(joinpath(directory, "files.toml"))["files"]
    required=Set(
        vcat(
            ["case.toml", "result.toml", "code/replay.jl"],
            ["code/"*p for p in keys(r7_adversary_science_paths())],
        ),
    )
    Set(keys(files))==required || error("对手存档清单不完整")
    actual=Set(
        replace(relpath(joinpath(p, f), directory), '\\'=>'/') for (p, _, fs) in walkdir(directory)
        for f in fs
    )
    actual==union(required, Set(["files.toml"])) || error("对手存档存在未登记文件")
    for (p, h) in files
        bytes2hex(sha256(read(joinpath(directory, split(p, '/')...))))==h ||
            error("对手存档哈希失配")
    end
    c=load_r7_recovery_case(joinpath(directory, "case.toml"))
    r=TOML.parsefile(joinpath(directory, "result.toml"))
    r["source_hashes_at_solve"]==r7_adversary_science_hashes() ||
        error("请使用冻结源码重读对手运行")
    all(files["code/"*p]==h for (p, h) in r["source_hashes_at_solve"]) || error("对手源码副本改变")
    q=validate_r7_adversary(c, r)
    isequal(q, r["validation"]) || error("保存对手原值与结论不同")
    (; case = c, result = r, validation = q)
end
