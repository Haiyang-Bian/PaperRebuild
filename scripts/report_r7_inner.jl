using PaperRebuild, JuMP, TOML, SHA

function frozen_r7_record(dir)
    m=Module(gensym(:FrozenR7Report))
    Base.include(m, abspath(joinpath(dir, "code/replay.jl")))
    Base.invokelatest(getfield, m, :x)
end

function assert_frozen_tree(dir)
    files=TOML.parsefile(joinpath(dir, "files.toml"))["files"]
    for (p, h) in files
        !isabspath(p)&&!occursin(':', p)&&!occursin('\\', p)&&all(
            x->!(x in ("", ".", "..")),
            split(p, '/'),
        ) || error("证据路径错误")
        bytes2hex(sha256(read(joinpath(dir, split(p, '/')...))))==h || error("证据文件改变")
    end
end

function stage_rows(dir)
    rule=TOML.parsefile(joinpath(dir, "rule.toml"))
    rows=String["case,run_id,iteration,restricted_value_MWh,cap_MWh,lower_bound_MWh,upper_bound_MWh,fault,topology_count"]
    for p in sort(collect(keys(rule["files"])))
        name=splitext(basename(p))[1]
        x=frozen_r7_record(joinpath(dir, name, "adversary"))
        for (k, it) in enumerate(x.result["iterations"])
            m=it["master"]
            v=x.validation["iterations"][k]
            value=haskey(m, "values") ? m["values"]["theta_MWh"] : ""
            fault=haskey(m, "values") ? join(m["values"]["fault"], ";") : ""
            push!(
                rows,
                join(
                    [
                        name,
                        x.result["run_id"],
                        k,
                        value,
                        x.validation["cap_MWh"],
                        v["lower_bound_MWh"],
                        v["upper_bound_MWh"],
                        fault,
                        length(m["topologies"]),
                    ],
                    ",",
                ),
            )
        end
    end
    join(rows, "\n")*"\n"
end

function create_report(src, out)
    ispath(out)&&error("不覆盖已保存报告")
    assert_frozen_tree(src)
    stages=stage_rows(src)
    cp(src, out)
    write(joinpath(out, "stages.csv"), stages)
    # 科学原值和原源码同字节搬入可提交摘要；只添加机械表和来源说明。
    meta=Dict(
        "schema"=>"r7-inner-evidence-transfer-v1",
        "reoptimized"=>false,
        "parent_manifest_sha256"=>bytes2hex(sha256(read(joinpath(src, "files.toml")))),
        "copied_files"=>TOML.parsefile(joinpath(src, "files.toml"))["files"],
        "report_script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
    )
    write(joinpath(out, "transfer.toml"), PaperRebuild.r7_text(meta))
    files=Dict(
        replace(relpath(joinpath(p, f), out), '\\'=>'/')=>bytes2hex(sha256(read(joinpath(p, f))))
        for (p, _, fs) in walkdir(out) for f in fs if !(p==out&&f=="files.toml")
    )
    write(joinpath(out, "files.toml"), PaperRebuild.r7_text(Dict("files"=>files)))
    check_report(out)
end

function check_report(dir)
    assert_frozen_tree(dir)
    read(joinpath(dir, "stages.csv"), String)==stage_rows(dir)||error("迭代图源失步")
    transfer=TOML.parsefile(joinpath(dir, "transfer.toml"))
    transfer["reoptimized"]===false || error("报告不应重新优化")
    for (p, h) in transfer["copied_files"]
        bytes2hex(sha256(read(joinpath(dir, split(p, '/')...))))==h || error("父批次原值发生改变")
    end
    println("R7 inner evidence and stage table verified; no reoptimization.")
end

length(ARGS)>=2||error(
    "usage: report_r7_inner.jl create SRC NEW_DIR | check DIR | copy-record SRC NEW_DIR",
)
if ARGS[1]=="create"&&length(ARGS)==3
    create_report(abspath(ARGS[2]), abspath(ARGS[3]))
elseif ARGS[1]=="check"&&length(ARGS)==2
    check_report(abspath(ARGS[2]))
elseif ARGS[1]=="copy-record"&&length(ARGS)==3
    ispath(ARGS[3])&&error("不覆盖记录")
    frozen_r7_record(ARGS[2])
    cp(ARGS[2], ARGS[3])
    frozen_r7_record(ARGS[3])
else
    error("unknown report command")
end
