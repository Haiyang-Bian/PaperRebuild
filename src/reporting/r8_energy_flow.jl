function r8_energy_includes()
    vcat(
        r8_includes(),
        [
            "src/$layer/r8_energy_flow.jl" for
            layer in ("core", "formulations", "verification", "algorithms", "reporting")
        ],
    )
end

"""保存稳态能流输入、原始解、界、摘要及科学源码；不覆盖已有运行，不允许求解后源码变化。"""
function save_r8_energy_run(c, s, r, directory::AbstractString)
    r["source_hashes_at_solve"]==r8_energy_science_hashes() || error("能流求解后科学源码改变")
    validate_r8_energy_solution(c, s, r)==r["validation"] || error("能流摘要不符")
    dest=abspath(directory)
    ispath(dest)&&error("不覆盖能流运行")
    stage=dest*".writing-"*string(uuid4())
    mkpath(stage)
    for (p, x) in (
        ("normal.toml", c.normal.data),
        ("planning.toml", c.specification),
        ("spec.toml", s),
        ("result.toml", r),
    )
        write(joinpath(stage, p), r7_text(x))
    end
    root=normpath(joinpath(@__DIR__, "../.."))
    for p in keys(r8_energy_science_hashes())
        target=joinpath(stage, "code", split(p, '/')...)
        mkpath(dirname(target))
        cp(joinpath(root, p), target)
    end
    replay="module FrozenR8Energy\nusing JuMP,TOML,SHA,Dates,UUIDs\nconst MOI=JuMP.MOI\n"*join(
        "include(\"$p\")\n" for p in r8_energy_includes()
    )*"end\nr=FrozenR8Energy.read_r8_energy_run(joinpath(@__DIR__,\"..\"))\nprintln(r.result[\"run_id\"])\n"
    write(joinpath(stage, "code/replay.jl"), replay)
    files=Dict(
        replace(relpath(joinpath(p, f), stage), '\\'=>'/')=>bytes2hex(sha256(read(joinpath(p, f))))
        for (p, _, fs) in walkdir(stage) for f in fs
    )
    write(joinpath(stage, "files.toml"), r7_text(Dict("files"=>files)))
    mv(stage, dest)
    read_r8_energy_run(dest)
    dest
end

"""核验完整文件集合、哈希和稳态原值；科学代码不同版本时使用存档code/replay.jl。"""
function read_r8_energy_run(directory::AbstractString)
    files=TOML.parsefile(joinpath(directory, "files.toml"))["files"]
    actual=Set(
        replace(relpath(joinpath(p, f), directory), '\\'=>'/') for (p, _, fs) in walkdir(directory)
        for f in fs
    )
    required=Set(
        vcat(
            ["normal.toml", "planning.toml", "spec.toml", "result.toml", "code/replay.jl"],
            "code/" .* collect(keys(r8_energy_science_hashes())),
        ),
    )
    Set(keys(files))==required && actual==union(required, Set(["files.toml"])) ||
        error("能流运行文件集合改变")
    for (p, h) in files
        !isabspath(p)&&!occursin(':', p)&&!occursin('\\', p)&&all(
            x->!(x in ("", ".", "..")),
            split(p, '/'),
        ) || error("能流归档路径越界")
        bytes2hex(sha256(read(joinpath(directory, split(p, '/')...))))==h || error("能流归档篡改")
    end
    c=load_r7_planning_case(
        joinpath(directory, "normal.toml"),
        joinpath(directory, "planning.toml"),
    )
    s, r=[TOML.parsefile(joinpath(directory, p*".toml")) for p in ("spec", "result")]
    r["source_hashes_at_solve"]==r8_energy_science_hashes() || error("请使用冻结能流入口重读")
    all(files["code/"*p]==h for (p, h) in r["source_hashes_at_solve"]) ||
        error("能流科学源码副本错误")
    q=validate_r8_energy_solution(c, s, r)
    q==r["validation"] || error("能流原值与摘要不符")
    (; case = c, spec = s, result = r, validation = q)
end
