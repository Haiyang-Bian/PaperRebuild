include("r5_strategic_report_tables.jl")

# 只分块，不聚合或删除残差。每块保留表头，顺序与独立验算输出完全一致。
function r6_pilot_csv_chunks(tables)
    chunks=Dict{String,Vector{NamedTuple}}()
    for (file, rows) in tables
        if file=="residuals.csv"
            for (part, firstrow) in enumerate(1:5000:length(rows))
                chunks["residuals-"*lpad(part, 3, '0')*".csv"]=rows[firstrow:min(
                    firstrow+4999,
                    length(rows),
                )]
            end
        else
            chunks[file]=rows
        end
    end
    chunks
end

function r6_pilot_tables(dir, meta)
    root=normpath(joinpath(@__DIR__, ".."))
    meta["schema"]=="r6-pilot-result-v1" &&
    meta["status"]=="pilot_completed_not_sample_out_validation" || error("开发批次未完成或版本错误")
    rules=meta["rule"]
    rules==TOML.parsefile(joinpath(root, "configs", "r6", "pilot-rule.toml")) ||
        error("开发规则不同")
    data=read_r6_dataset(joinpath(root, rules["dataset"]))
    physical=load_r6_physical_case(joinpath(root, rules["physical"]))
    physical.sha256==meta["physical_sha256"] && data.protocol.sha256==meta["protocol_sha256"] ||
        error("开发来源不一致")
    for (file, h) in meta["source_hashes"]
        bytes2hex(sha256(read(joinpath(root, file))))==h || error("开发源码版本不同：$file")
    end
    [x["method"] for x in meta["records"]]==rules["methods"] || error("开发记录顺序/完整性错误")
    tables=Dict{String,Vector{NamedTuple}}()
    for method in rules["methods"]
        w=TOML.parsefile(joinpath(dir, "witnesses", method*".toml"))
        c=R5StrategicCase(w["case"])
        r=w["result"]
        radius=method in ("DRO", "DRJCC") ? rules["radius"] : 0.0
        expected=r6_training_case(
            physical,
            data.protocol,
            data.sets["train"],
            data.representatives,
            R6MethodSpec(method; radius, epsilon = rules["epsilon"]);
            development_count = rules["development_count"],
        )
        expected.sha256==c.sha256 || error("公开训练输入不符合冻结规则")
        v=validate_r5_strategic(c, r)
        record=only(x for x in meta["records"] if x["method"]==method)
        w["parent_result_sha256"]==record["result_sha256"] || error("父运行原值身份不同")
        record["run_id"]==r["run_id"] &&
        record["case_sha256"]==c.sha256 &&
        record["status"]==r["status"] &&
        record["elapsed_sec"]==r["elapsed_sec"] || error("开发结果身份不同")
        record["model_pass"]==v["model_pass"] &&
        record["risk_pass"]==v["risk_pass"] &&
        record["cost_complete"]==(r["status"]=="solver_optimal"&&v["optimality_pass"]) ||
            error("开发记录的通过状态不符")
        isequal(record["training_cost_USD"], get(v, "worst_total_cost_USD", NaN)) ||
            error("费用重算不同")
        e=Dict("id"=>method, "case"=>method*"-input.toml", "solver"=>"gurobi", "method"=>method)
        for (file, rows) in r5_strategic_tables(c, r, e)
            append!(get!(tables, file, NamedTuple[]), rows)
        end
    end
    tables
end

function r6_pilot_report(source, output)
    ispath(output) && error("不覆盖开发报告")
    meta=TOML.parsefile(joinpath(source, "pilot.toml"))
    meta["reporter_hashes"]=Dict(
        f=>bytes2hex(sha256(read(joinpath(@__DIR__, f)))) for
        f in ("r6_pilot_report.jl", "r5_strategic_report_tables.jl")
    )
    mkpath(joinpath(output, "witnesses"))
    for method in meta["rule"]["methods"]
        raw=joinpath(source, method)
        x=read_r5_strategic_run(raw)
        write(
            joinpath(output, "witnesses", method*".toml"),
            PaperRebuild.r5_market_text(
                Dict(
                    "case"=>x.case.data,
                    "result"=>r5_strategic_public(x.result),
                    "parent_result_sha256"=>bytes2hex(sha256(read(joinpath(raw, "result.toml")))),
                ),
            ),
        )
    end
    write(joinpath(output, "pilot.toml"), PaperRebuild.r5_market_text(meta))
    tables=r6_pilot_tables(output, meta)
    for (file, rows) in r6_pilot_csv_chunks(tables)
        CSV.write(joinpath(output, file), rows)
    end
    hashes=Dict(
        rel=>bytes2hex(sha256(read(joinpath(output, rel)))) for
        rel in PaperRebuild.r5_market_file_inventory(output)
    )
    write(joinpath(output, "hashes.toml"), PaperRebuild.r5_market_text(Dict("files"=>hashes)))
    r6_check_pilot_report(output)
end

function r6_check_pilot_report(dir)
    inventory=PaperRebuild.r5_market_file_inventory(dir)
    hashes=TOML.parsefile(joinpath(dir, "hashes.toml"))["files"]
    Set(inventory)==Set(keys(hashes)) || error("公开文件清单改变")
    for (rel, h) in hashes
        file=joinpath(dir, rel)
        filesize(file)<=5*1024^2 || error("公开文件过大")
        bytes2hex(sha256(read(file)))==h || error("公开记录被篡改")
        occursin(r"(?i)[A-Z]:[\\/]", read(file, String)) && error("公开记录含主机绝对路径")
    end
    meta=TOML.parsefile(joinpath(dir, "pilot.toml"))
    for (file, h) in meta["reporter_hashes"]
        bytes2hex(sha256(read(joinpath(@__DIR__, file))))==h || error("报告生成器版本不同")
    end
    for (file, rows) in r6_pilot_csv_chunks(r6_pilot_tables(dir, meta))
        io=IOBuffer()
        CSV.write(io, rows)
        take!(io)==read(joinpath(dir, file)) || error("独立重算CSV不一致")
    end
    println("R6 pilot: six training witnesses and CSVs verified; no sample-out risk claim.")
end

if abspath(PROGRAM_FILE)==(@__FILE__)
    if length(ARGS)==3 && ARGS[1]=="create"
        r6_pilot_report(ARGS[2], ARGS[3])
    elseif length(ARGS)==2 && ARGS[1]=="check"
        r6_check_pilot_report(ARGS[2])
    else
        error("usage: r6_pilot_report.jl create <raw> <new-report> | check <report>")
    end
end
