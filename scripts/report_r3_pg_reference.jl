using TOML, SHA

# 从原始求解器对照中提取紧凑证据，保留来源哈希；不重新求解。
length(ARGS)==2 || error("usage: report_r3_pg_reference.jl SOURCE_TOML OUTPUT_TOML")
source, output=ARGS
ispath(output) && error("拒绝覆盖旧对照摘要")
raw=TOML.parsefile(source)
records=Dict{String,Any}[]
for original in raw["records"]
    record=deepcopy(original)
    if haskey(record, "gurobi_kkt")
        delete!(record["gurobi_kkt"], "rows")
    end
    push!(records, record)
end
open(output, "w") do io
    TOML.print(
        io,
        Dict(
            "source_file"=>basename(source),
            "source_sha256"=>bytes2hex(sha256(read(source))),
            "source_hashes"=>raw["source_hashes"],
            "records"=>records,
            "interpretation"=>"Primal comparison passed; four raw dual sets rejected. No validated Gurobi gradient.",
        );
        sorted = true,
    )
end
println(output)
