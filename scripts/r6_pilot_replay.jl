using Tar, TOML, SHA

const R6_PILOT_SOURCE_COMMIT = "12feb05"
const R6_PILOT_INPUTS = ["results/summaries/r6-data-v1", "results/summaries/r6-training-pilot-v1"]

function r6_replay_inventory(dir)
    files=Dict{String,String}()
    for (base, dirs, names) in walkdir(dir)
        any(islink(joinpath(base, x)) for x in vcat(dirs, names)) && error("重放输入不能含链接")
        for name in names
            path=joinpath(base, name)
            files[replace(relpath(path, dir), '\\'=>'/')]=bytes2hex(sha256(read(path)))
        end
    end
    files
end

function freeze_r6_pilot_replay(output)
    ispath(output) && error("不覆盖源码重放包")
    root=normpath(joinpath(@__DIR__, ".."))
    commit=readchomp(`git -C $root rev-parse $R6_PILOT_SOURCE_COMMIT`)
    paths=[
        "src",
        "Project.toml",
        "Manifest.toml",
        "configs/r6",
        "tools/solvers/Project.toml",
        "tools/solvers/Manifest.toml",
        "scripts/r6_pilot_report.jl",
        "scripts/r5_strategic_report_tables.jl",
        "scripts/test_r6_pilot_artifacts.jl",
    ]
    pilot=TOML.parse(
        String(read(`git -C $root show $commit:results/summaries/r6-training-pilot-v1/pilot.toml`)),
    )
    append!(paths, collect(keys(pilot["source_hashes"])))
    unique!(paths)
    bytes=read(`git -C $root archive --format=tar $commit -- $paths`)
    length(bytes)<5*1024^2 || error("源码归档超过项目单文件限制")
    sources=mktempdir() do temp
        Tar.extract(IOBuffer(bytes), temp)
        files=r6_replay_inventory(temp)
        all(get(files, k, "")==h for (k, h) in pilot["source_hashes"]) ||
            error("冻结源码依赖不完整")
        files
    end
    meta=Dict(
        "schema"=>"r6-pilot-replay-v1",
        "source_commit"=>commit,
        "archive_sha256"=>bytes2hex(sha256(bytes)),
        "sources"=>sources,
        "inputs"=>Dict(p=>r6_replay_inventory(joinpath(root, p)) for p in R6_PILOT_INPUTS),
    )
    mkpath(output)
    write(joinpath(output, "source.tar"), bytes)
    open(joinpath(output, "replay.toml"), "w") do io
        TOML.print(io, meta; sorted = true)
    end
    println("Frozen pilot source bundle: ", commit, "; bytes=", length(bytes))
end

function replay_r6_pilot(bundle)
    root=normpath(joinpath(@__DIR__, ".."))
    meta=TOML.parsefile(joinpath(bundle, "replay.toml"))
    meta["schema"]=="r6-pilot-replay-v1" || error("源码重放版本错误")
    archive=joinpath(bundle, "source.tar")
    bytes2hex(sha256(read(archive)))==meta["archive_sha256"] || error("源码归档被修改")
    for h in Tar.list(archive)
        h.type in (:file, :directory) &&
        !isabspath(h.path) &&
        !occursin(':', h.path) &&
        !occursin('\\', h.path) &&
        !(".." in split(h.path, '/')) || error("归档路径或文件类型不合法")
    end
    Set(keys(meta["inputs"]))==Set(R6_PILOT_INPUTS) || error("重放输入范围改变")
    mktempdir() do temp
        # 先检查原值，后在隔离目录加载原包；无需旧Git历史或商业求解器许可。
        Tar.extract(archive, temp)
        r6_replay_inventory(temp)==meta["sources"] || error("归档源码清单不符")
        for p in R6_PILOT_INPUTS
            source=joinpath(root, p)
            r6_replay_inventory(source)==meta["inputs"][p] || error("冻结数据改变：$p")
            dest=joinpath(temp, p)
            mkpath(dirname(dest))
            cp(source, dest)
        end
        command=`$(Base.julia_cmd()) --startup-file=no --project=$temp $(joinpath(temp,"scripts","test_r6_pilot_artifacts.jl"))`
        run(Cmd(command; dir = temp))
    end
    println("Pilot replay passed with frozen sources; current implementation was not substituted.")
end

if abspath(PROGRAM_FILE)==(@__FILE__)
    length(ARGS)==2 || error("usage: r6_pilot_replay.jl freeze <new-bundle> | check <bundle>")
    ARGS[1]=="freeze" ? freeze_r6_pilot_replay(ARGS[2]) :
    ARGS[1]=="check" ? replay_r6_pilot(ARGS[2]) : error("未知操作")
end
