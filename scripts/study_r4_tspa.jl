# 两罚系数共享同一AGNB控制；原始计划与集中参考始终只读。
include("r4_setup.jl")
using SHA, Dates
root=normpath(joinpath(@__DIR__, ".."))
config=joinpath(root, "configs", "r4", "tspa-study.toml")
spec=TOML.parsefile(config)
batch=isempty(ARGS) ? "r4-tspa-"*Dates.format(now(), "yyyymmddTHHMMSS") : only(ARGS)
occursin(r"^[A-Za-z0-9_-]+$", batch) || error("批次ID非法")
dest=joinpath(root, "results", "runs", "r4", batch)
ispath(dest) && error("不覆盖已有批次")
mkpath(dest)
hashes=PaperRebuild.r4_science_hashes()
records=Dict{String,Any}[]
optimizer=r4_optimizer(Symbol(spec["solver"]))
for name in spec["cases"]
    parentdir=joinpath(root, spec["parent_directory"])
    agpath=joinpath(parentdir, name*"--independent_exact")
    swpath=joinpath(parentdir, name*"--central_exact")
    ag=read_r4_run(agpath)
    sw=read_r4_run(swpath)
    c=ag.case
    c.sha256==spec["input_sha256"][name] || error("父输入与冻结清单不一致")
    trading=nothing
    for penalty in spec["penalties"]
        r=solve_r4_tspa(
            c;
            independent = ag.result,
            central = sw.result,
            optimizer,
            spec = R4TSPASpec(; penalty, weight_rule = Symbol(spec["weight_rule"])),
            electric = Symbol(spec["electric"]),
            budget_sec = spec["budget_sec"],
            trading_run = trading,
        )
        id=name*"--penalty-"*string(Int(penalty))
        r["parent_result_sha256"]=Dict(
            "independent"=>bytes2hex(sha256(read(joinpath(agpath, "result.toml")))),
            "central"=>bytes2hex(sha256(read(joinpath(swpath, "result.toml")))),
        )
        path=save_r4_tspa_run(c, r; directory = dest, run_id = id)
        read_r4_tspa_run(path)
        push!(records, Dict("id"=>id, "case"=>name, "penalty"=>penalty, "input_sha256"=>c.sha256))
        # 包含已知独立候选回退时也保留原solver候选，不能静默改写其最优性声明。
        trading=r["trading_solver"]["validation"]["model_pass"] ? r["trading_solver"] :
                r["trading_selected"]
        println(
            id,
            " | ",
            r["validation"],
            " | stage1 surplus=",
            r["economics"]["stage1"]["surplus"],
        )
        flush(stdout)
    end
end
hashes==PaperRebuild.r4_science_hashes() || error("执行期间源码改变")
write(
    joinpath(dest, "study.toml"),
    PaperRebuild.r4_text(
        Dict(
            "batch"=>batch,
            "origin"=>"synthetic",
            "config_sha256"=>bytes2hex(sha256(read(config))),
            "records"=>records,
            "source_hashes_at_solve"=>hashes,
        ),
    ),
)
hs=Dict{String,String}()
for (dir, _, files) in walkdir(dest), file in files
    p=joinpath(dir, file)
    hs[replace(relpath(p, dest), '\\'=>'/')]=bytes2hex(sha256(read(p)))
end
write(joinpath(dest, "batch-hashes.toml"), PaperRebuild.r4_text(Dict("sha256"=>hs)))
println("Saved: ", joinpath(dest, "study.toml"))
