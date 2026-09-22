"""
    save_r9_distributed_run(case, result; directory="results/runs/r9-distributed", run_id=...)

保存完整迭代、块原控制、输入和求解时源码/锁文件；先数值核验，再写最后的哈希清单。
拒绝覆盖、求解后源码改变或伪造验收。存档包含全量主体数据，仅供研究审计，不宣称隐私部署。
"""
function save_r9_distributed_run(
    c::R9TradingCase,
    r;
    directory = joinpath("results", "runs", "r9-distributed"),
    run_id = string(uuid4()),
)
    occursin(r"^[A-Za-z0-9_-]+$", run_id) || error("运行ID非法")
    r["source_unchanged"] && r["source_hashes_at_solve"]==r9_trading_science_hashes() ||
        error("求解源码已变")
    isequal(validate_r9_distributed(c, r), r["validation"]) || error("保存前验收改变")
    path=abspath(joinpath(directory, run_id))
    ispath(path) && error("不覆盖已有分布运行")
    mkpath(path)
    out=deepcopy(r)
    out["run_id"]=run_id
    write(joinpath(path, "input.toml"), c.source_text)
    write(joinpath(path, "result.toml"), r4_text(out))
    root=normpath(joinpath(@__DIR__, "..", ".."))
    for (rel, hash) in r["source_hashes_at_solve"]
        source=r9_trading_path(root, rel)
        bytes2hex(sha256(read(source)))==hash || error("快照源文件并发变化")
        target=r9_trading_path(path, "snapshot/"*rel)
        mkpath(dirname(target))
        cp(source, target)
    end
    files=Dict(
        rel=>bytes2hex(sha256(read(r9_trading_path(path, rel)))) for
        rel in r9_trading_inventory(path)
    )
    write(
        joinpath(path, "hashes.toml"),
        r4_text(Dict("schema"=>"r9-distributed-archive-v1", "files"=>files)),
    )
    path
end

"""验证完整分布存档字节、白名单与快照来源；不执行存档源码。"""
function r9_distributed_check_files(path)
    meta=TOML.parsefile(r9_trading_path(path, "hashes.toml"))
    meta["schema"]=="r9-distributed-archive-v1" || error("分布存档版本错误")
    files=meta["files"]
    Set(r9_trading_inventory(path))==union(Set(keys(files)), Set(["hashes.toml"])) ||
        error("存档清单改变")
    for (rel, hash) in files
        bytes2hex(sha256(read(r9_trading_path(path, rel))))==hash || error("存档字节改变：$rel")
    end
    r=TOML.parsefile(r9_trading_path(path, "result.toml"))
    for (rel, hash) in r["source_hashes_at_solve"]
        get(files, "snapshot/"*rel, "")==hash || error("求解来源与快照不符")
    end
    Set(keys(files))==union(
        Set(["input.toml", "result.toml"]),
        Set("snapshot/"*x for x in keys(r["source_hashes_at_solve"])),
    ) || error("分布存档含未声明文件")
    nothing
end

"""使用已经核验的当前库进行数值重放，不重新优化。"""
function r9_distributed_read_current(path)
    r9_distributed_check_files(path)
    c=load_r9_trading_case(r9_trading_path(path, "input.toml"))
    r=TOML.parsefile(r9_trading_path(path, "result.toml"))
    val=validate_r9_distributed(c, r)
    isequal(val, r["validation"]) || error("分布原值重验与历史不符")
    (; case = c, result = r, validation = val)
end

"""
    read_r9_distributed_run(path; frozen=true)

核验存档全部哈希后，以冻结源码重算每轮消息、递推、费用及合并约束；不重新求解。
frozen=false仅供当前验证器兼容测试。移动目录不改变身份；篡改、缺项或历史判定漂移明确拒绝。
"""
function read_r9_distributed_run(path::AbstractString; frozen = true)
    r9_distributed_check_files(path)
    if frozen
        wrapper=Module(gensym(:R9DistributedReplay))
        Base.include(wrapper, r9_trading_path(path, "snapshot/src/PaperRebuild.jl"))
        lib=Base.invokelatest(getfield, wrapper, :PaperRebuild)
        reader=Base.invokelatest(getfield, lib, :r9_distributed_read_current)
        loaded=Base.invokelatest(reader, path)
        return (;
            case = load_r9_trading_case(joinpath(path, "input.toml")),
            result = loaded.result,
            validation = loaded.validation,
        )
    end
    r9_distributed_read_current(path)
end
