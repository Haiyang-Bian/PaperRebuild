"""
    save_r4_tspa_run(case, result; directory="results/runs/r4", run_id=...)

保存两阶段完整证据、父运行内容、输入与科学源码快照。沿用不可覆盖保存器，
写入前重新验证两种分歧口径；失败结果也可保存，不覆盖旧R4运行。
"""
function save_r4_tspa_run(
    c::R4Case,
    r;
    directory = joinpath("results", "runs", "r4"),
    run_id = string(uuid4()),
)
    r["schema"]=="r4-tspa-run-v1" || error("不是TSPA运行")
    validate_r4_tspa(c, r)==r["validation"] || error("TSPA验收改变")
    return save_r4_run(c, r; directory, run_id)
end

"""
    read_r4_tspa_run(directory)

只读核验完整文件清单/哈希，并独立重算AGNB、弹性罚项及两种口径分配。
不求解、不迁移旧文件。哈希检测意外篡改，不替代外部数字签名。
"""
function read_r4_tspa_run(path::AbstractString)
    hashes=TOML.parsefile(joinpath(path, "hashes.toml"))["sha256"]
    actual=Set{String}()
    for (dir, _, files) in walkdir(path), file in files
        rel=replace(relpath(joinpath(dir, file), path), '\\'=>'/')
        rel=="hashes.toml" || push!(actual, rel)
    end
    actual==Set(keys(hashes)) || error("TSPA文件清单改变")
    for (rel, hash) in hashes
        !isabspath(rel) && !(".." in split(rel, '/')) || error("非法保存路径")
        bytes2hex(sha256(read(joinpath(path, rel))))==hash || error("TSPA保存内容哈希不符")
    end
    c=load_r4_case(joinpath(path, "input.toml"))
    r=TOML.parsefile(joinpath(path, "result.toml"))
    r["schema"]=="r4-tspa-run-v1" || error("不是TSPA存档")
    v=validate_r4_tspa(c, r)
    v==r["validation"] || error("TSPA重读验收不一致")
    return (; case = c, result = r, validation = v)
end
