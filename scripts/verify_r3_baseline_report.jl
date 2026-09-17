include("r3_setup.jl")
using CSV
function main()
    length(ARGS)==1 || error("usage: verify_r3_baseline_report.jl REPORT_DIRECTORY")
    dir=only(ARGS)
    manifest=TOML.parsefile(joinpath(dir, "artifact-hashes.toml"))
    copyroot=joinpath("docs", "src", "assets", "r3-baseline", basename(dir))
    for (path, hash) in manifest["files"]
        bytes2hex(open(sha256, joinpath(dir, path))) == hash || error("报告哈希不符：$path")
        bytes2hex(open(sha256, joinpath(copyroot, path))) == hash || error("文档副本不同：$path")
    end
    study=TOML.parsefile(joinpath(dir, "study.toml"))
    study["science_hashes"]==PaperRebuild.r2_science_hashes() || error("科学源码与正式批次不符")
    length(study["runs"])==42 || error("不是完整42项")
    fields=(:stage, :name, :equation, :scope, :entity, :t, :residual, :unit, :tolerance, :pass)
    total=0
    for entry in study["runs"]
        raw=joinpath("results", "runs", study["batch"], entry["directory"], "residuals.csv")
        a=CSV.File(raw)
        b=CSV.File(joinpath(dir, entry["id"]*"-F04.csv.gz"))
        length(a)==length(b) || error("残差行数不同")
        for (x, y) in zip(a, b), f in fields
            isequal(getproperty(x, f), getproperty(y, f)) ||
                error("压缩重读残差不同：$(entry["id"]) $f")
        end
        total+=length(a)
    end
    println(
        "Verified ",
        length(manifest["files"]),
        " report/doc artifacts and ",
        total,
        " unabridged residual rows; 42 runs share current scientific source.",
    )
end
main()
