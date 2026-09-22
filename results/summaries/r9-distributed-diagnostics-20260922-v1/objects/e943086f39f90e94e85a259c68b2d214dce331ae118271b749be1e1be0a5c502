"""
    save_r4_distributed_run(case, result; directory="results/runs/r4", run_id=...)

只写入新的分布运行目录，保存通信轨迹、原始主体解、输入与科学源码快照。
先重新核验记录；不允许覆盖历史或用更改后的源码冒充原运行。
"""
function save_r4_distributed_run(
    c::R4Case,
    r;
    directory = joinpath("results", "runs", "r4"),
    run_id = string(uuid4()),
)
    isequal(validate_r4_distributed(c, r), r["validation"]) || error("分布验收改变")
    return save_r4_run(c, r; directory, run_id)
end

"""
    read_r4_distributed_run(directory)

只读检查完整文件清单及哈希，重新核验通信递推与合并后的调度；不求解、不迁移旧结果。
哈希用于意外篡改检测，不是密码学身份签名。
"""
function read_r4_distributed_run(path::AbstractString)
    hashes=TOML.parsefile(joinpath(path, "hashes.toml"))["sha256"]
    actual=Set{String}()
    for (dir, _, files) in walkdir(path), file in files
        rel=replace(relpath(joinpath(dir, file), path), '\\'=>'/')
        rel=="hashes.toml" || push!(actual, rel)
    end
    actual==Set(keys(hashes)) || error("分布运行文件清单改变")
    for (rel, hash) in hashes
        !isabspath(rel) && !(".." in split(rel, '/')) || error("非法存档路径")
        bytes2hex(sha256(read(joinpath(path, rel))))==hash || error("分布文件哈希不符")
    end
    c=load_r4_case(joinpath(path, "input.toml"))
    r=TOML.parsefile(joinpath(path, "result.toml"))
    v=validate_r4_distributed(c, r)
    isequal(v, r["validation"]) || error("重读验收不一致")
    return (; case = c, result = r, validation = v)
end
