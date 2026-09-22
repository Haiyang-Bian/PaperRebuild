using TOML, SHA

r8_file_hash(p) = bytes2hex(sha256(read(p)))
function r8_archive_files(dir)
    Dict(
        replace(relpath(joinpath(p, f), dir), '\\'=>'/')=>r8_file_hash(joinpath(p, f)) for
        (p, _, fs) in walkdir(dir) for f in fs
    )
end
function r8_checked_path(root, p)
    !isabspath(p)&&!occursin(':', p)&&!occursin('\\', p)&&all(
        x->!(x in ("", ".", "..")),
        split(p, '/'),
    ) || error("R8归档路径非法")
    joinpath(root, split(p, '/')...)
end
function r8_archive_inputs(dir)
    registry=TOML.parsefile(joinpath(dir, "freeze.toml"))
    for (p, h) in registry["files"]
        r8_file_hash(r8_checked_path(dir, p))==h || error("R8冻结文件改变：$p")
    end
    items=TOML.parsefile(joinpath(dir, "inputs.toml"))["records"]
    rule=TOML.parsefile(joinpath(dir, "rule.toml"))
    length(items)==rule["record_count"] || error("R8冻结数量不符")
    ids=[x["id"] for x in items]
    all(occursin(r"^[a-zA-Z0-9_-]+$", x) for x in ids)&&length(ids)==length(unique(ids)) ||
        error("R8运行ID重复/非法")
    items, rule, registry
end
const R8_ARCHIVE_MODULES=Dict{String,Module}()
function r8_archive_module(dir)
    r8_archive_inputs(dir)
    get!(R8_ARCHIVE_MODULES, abspath(dir)) do
        wrapper=Module(gensym(:R8Archive))
        Base.include(wrapper, joinpath(dir, "code/frozen-module.jl"))
        Base.invokelatest(getfield, wrapper, :FrozenR8)
    end
end
function r8_archive_record(dir, x, M)
    p=joinpath(dir, "records", x["id"])
    hashes=TOML.parsefile(joinpath(p, "files.toml"))["files"]
    Set(keys(hashes))==Set(["result.toml"])&&Set(readdir(p))==Set(["result.toml", "files.toml"]) ||
        error("R8单运行文件集合变化")
    r8_file_hash(joinpath(p, "result.toml"))==hashes["result.toml"] || error("R8结果篡改")
    r=TOML.parsefile(joinpath(p, "result.toml"))
    Base.invokelatest() do
        c=M.R7PlanningCase(M.R7NormalCase(x["normal"]), x["planning"])
        c.sha256==x["case_sha256"] &&
        M.r7_digest(x["flow"])==x["flow_sha256"] &&
        M.r7_digest(x["spec"])==x["spec_sha256"] || error("R8冻结输入身份错误")
        science=TOML.parsefile(joinpath(dir, "freeze.toml"))["science"]
        r["source_hashes_at_solve"]==science || error("R8执行源码与冻结不符")
        q=M.validate_r8_solution(c, x["flow"], x["spec"], r)
        isequal(q, r["validation"]) || error("R8数值摘要不符")
        (; case = c, flow = x["flow"], spec = x["spec"], result = r, validation = q)
    end
end
function r8_archive_check(dir; complete = true)
    items, rule, reg=r8_archive_inputs(dir)
    M=r8_archive_module(dir)
    all(reg["files"]["code/"*p]==h for (p, h) in reg["science"]) || error("冻结科学文件清单不一致")
    records=Dict{String,Any}()
    for x in items
        present=isdir(joinpath(dir, "records", x["id"]))
        complete&&!present&&error("R8正式记录缺失："*x["id"])
        present&&(records[x["id"]]=r8_archive_record(dir, x, M))
    end
    if isdir(joinpath(dir, "records"))
        Set(readdir(joinpath(dir, "records")))==Set(keys(records)) ||
            error("R8存在未声明/未完成的记录")
    end
    if isfile(joinpath(dir, "report-hashes.toml"))
        hashes=TOML.parsefile(joinpath(dir, "report-hashes.toml"))["files"]
        actual=r8_archive_files(dir)
        delete!(actual, "report-hashes.toml")
        actual==hashes || error("R8报告文件集合或字节改变")
    end
    (; items, rule, records)
end
