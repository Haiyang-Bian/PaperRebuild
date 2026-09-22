"""
    save_r4_discrete_run(case, result; directory="results/runs/r4", run_id=...)

保存全部离散模式及失败、原始与重构候选、共享预算和源码快照；拒绝覆盖旧目录。
"""
function save_r4_discrete_run(
    c::R4Case,
    r;
    directory = joinpath("results", "runs", "r4"),
    run_id = string(uuid4()),
)
    isequal(validate_r4_discrete(c, r), r["validation"]) || error("枚举验收改变")
    return save_r4_run(c, r; directory, run_id)
end

"""
    read_r4_discrete_run(directory)

只读核验运行文件清单、字节哈希、全部模式覆盖、原始与重构验收；不重算优化、不迁移历史。
"""
function read_r4_discrete_run(path::AbstractString)
    hashes=TOML.parsefile(joinpath(path, "hashes.toml"))["sha256"]
    actual=Set(
        replace(relpath(joinpath(d, f), path), '\\'=>'/') for (d, _, fs) in walkdir(path) for
        f in fs if f!="hashes.toml"
    )
    actual==Set(keys(hashes)) || error("枚举运行文件清单改变")
    for (rel, h) in hashes
        !isabspath(rel)&&!(".." in split(rel, '/')) || error("非法存档路径")
        bytes2hex(sha256(read(joinpath(path, rel))))==h || error("枚举文件哈希改变")
    end
    c=load_r4_case(joinpath(path, "input.toml"))
    r=TOML.parsefile(joinpath(path, "result.toml"))
    v=validate_r4_discrete(c, r)
    isequal(v, r["validation"]) || error("重读枚举验收改变")
    return (; case = c, result = r, validation = v)
end
