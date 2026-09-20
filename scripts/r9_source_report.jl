module R9SourceReport

using PaperRebuild, TOML, CSV, SHA, Dates

const ROOT=normpath(joinpath(@__DIR__, ".."))
const LEDGERS=("inputs.toml", "topology.toml", "reported-results.toml")
const CODE=("src/core/r9_inputs.jl", "src/verification/r9_sources.jl")
hashfile(path) = bytes2hex(sha256(read(path)))

"""保存原页输入审计和最小冻结源码。不得覆盖目录，不运行优化或下载资料。"""
function write_report(out; root = ROOT)
    ispath(out) && error("不得覆盖已有输入审计")
    bundle=load_r9_sources(joinpath(root, "docs/reading/ch07"))
    audit=audit_r9_sources(bundle)
    mkpath(out)
    for name in LEDGERS
        b=read(joinpath(root, "docs/reading/ch07", name))
        bytes2hex(sha256(b))==bundle.hashes[name] || error("台账在审计期间变化")
        write(joinpath(out, name), b)
    end
    for path in CODE
        dst=joinpath(out, "code", path)
        mkpath(dirname(dst))
        write(dst, read(joinpath(root, path)))
    end
    open(joinpath(out, "audit.toml"), "w") do io
        TOML.print(io, audit; sorted = true)
    end
    columns=(
        :id,
        :label,
        :derived,
        :reported,
        :difference,
        :rounding_tolerance,
        :unit,
        :meaning,
        :status,
    )
    rows=[NamedTuple{columns}(Tuple(row[string(k)] for k in columns)) for row in audit["rows"]]
    CSV.write(joinpath(out, "arithmetic.csv"), rows)
    names=[collect(LEDGERS); "code/" .* collect(CODE); "audit.toml"; "arithmetic.csv"]
    manifest=Dict(
        "schema"=>"r9-source-report-v1",
        "created_utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
        "optimization_performed"=>false,
        "files"=>Dict(p=>hashfile(joinpath(out, p)) for p in names),
    )
    open(joinpath(out, "manifest.toml"), "w") do io
        TOML.print(io, manifest; sorted = true)
    end
    return check_report(out)
end

"""只读核验固定文件清单、字节哈希，并使用冻结源码重算所有作者表格诊断。"""
function check_report(out)
    manifest=TOML.parsefile(joinpath(out, "manifest.toml"))
    manifest["schema"]=="r9-source-report-v1" && !manifest["optimization_performed"] ||
        error("输入审计身份错误")
    names=[collect(LEDGERS); "code/" .* collect(CODE); "audit.toml"; "arithmetic.csv"]
    Set(keys(manifest["files"]))==Set(names) || error("输入审计文件清单错误")
    for name in names
        hashfile(joinpath(out, name))==manifest["files"][name] || error("审计文件已改变：$name")
    end
    # 仅加载已校验的两份仓库科研源码，不需要本地论文、商业许可或当前模型实现。
    frozen=Module(gensym(:R9SourceReplay))
    Core.eval(frozen, :(using TOML, SHA))
    for path in CODE
        Base.include(frozen, joinpath(out, "code", path))
    end
    bundle=Base.invokelatest(() -> getfield(frozen, :load_r9_sources)(out))
    expected=Base.invokelatest(() -> getfield(frozen, :audit_r9_sources)(bundle))
    saved=TOML.parsefile(joinpath(out, "audit.toml"))
    isequal(expected, saved) || error("原始输入独立重算与保存报告不同")
    table=collect(CSV.File(joinpath(out, "arithmetic.csv")))
    length(table)==length(saved["rows"]) || error("算术表长度改变")
    for (csv, row) in zip(table, saved["rows"]), key in propertynames(csv)
        isequal(getproperty(csv, key), row[string(key)]) || error("算术表与TOML不一致")
    end
    return saved
end

end
