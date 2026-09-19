using PaperRebuild, TOML, SHA, Dates

function freeze_r6_main()
    VERSION == v"1.12.6" || error("冻结生成器使用Julia 1.12.6")
    root = normpath(joinpath(@__DIR__, ".."))
    length(ARGS) == 1 || error("用法: freeze_r6_data.jl <新输出目录>")
    path = abspath(ARGS[1])
    ispath(path) && error("不覆盖已有数据包")
    p = load_r6_protocol(joinpath(root, "configs", "r6", "protocol.toml"))
    sources = [
        "src/core/r6_protocol.jl",
        "src/algorithms/r6_data.jl",
        "src/verification/r6_statistics.jl",
        "src/reporting/r6_data.jl",
        "scripts/freeze_r6_data.jl",
        "src/PaperRebuild.jl",
        "src/core/r5_market.jl",
        "configs/r6/protocol.toml",
        "Project.toml",
        "Manifest.toml",
    ]
    hashes = Dict(s => bytes2hex(sha256(read(joinpath(root, s)))) for s in sources)
    status = readchomp(Cmd(["git", "status", "--porcelain"]; dir = root))
    # 个人编辑器设置与科学输入分开；科学文件有未提交修改时不能宣称正式冻结。
    changed = readchomp(Cmd(["git", "diff", "HEAD", "--name-only", "--", sources...]; dir = root))
    isempty(changed) || error("科学源码尚未提交，不进行正式数据冻结")
    run(Cmd(["git", "ls-files", "--error-unmatch", "--", sources...]; dir = root))
    sets = Dict(s => r6_generate_trajectories(p, s) for s in ("train", "validation", "test"))
    reps = r6_fit_representatives(sets["train"], p)
    reps["converged"] || error("聚类达到预算仍未收敛")
    all(bytes2hex(sha256(read(joinpath(root, s)))) == h for (s, h) in hashes) ||
        error("生成时源码变化")
    manifest = save_r6_dataset(
        path,
        p,
        sets,
        reps;
        provenance = Dict(
            "commit" => readchomp(Cmd(["git", "rev-parse", "HEAD"]; dir = root)),
            "working_tree_status" => status,
            "source_files" => hashes,
            "created_utc" => string(Dates.now(Dates.UTC)),
            "rng" => "Random.Xoshiro",
        ),
    )
    read_r6_dataset(path)
    println(
        "R6 input frozen: ",
        p.data["samples"],
        "; representatives=",
        length(reps["counts"]),
        "; iterations=",
        reps["iterations"],
    )
    println("Protocol SHA256: ", manifest["protocol_sha256"])
    println("No method optimization or out-of-sample performance has been claimed.")
end

freeze_r6_main()
