include("r5_market_payment_tables.jl")
length(ARGS)==2||error("参数：原市场study.toml 新审计目录")
manifest, output=abspath.(ARGS)
ispath(output)&&error("不覆盖支付审计")
root=normpath(joinpath(@__DIR__, ".."))
study=TOML.parsefile(manifest)
study["schema"]=="r5-market-study-v1"&&study["complete"]||error("市场批次未完整保存")
rules=TOML.parsefile(joinpath(root, "configs", "r5", "market", "study.toml"))
Set(x["id"] for x in rules["records"])==Set(x["id"] for x in study["records"])&&length(
    study["records"],
)==18||error("不能挑选成功市场记录")
study["config_sha256"]==bytes2hex(
    sha256(read(joinpath(root, "configs", "r5", "market", "study.toml"))),
)||error("市场规则变化")
mkpath(joinpath(output, "witnesses"))
allw=Dict{String,Any}[];
hashes=Dict{String,String}()
for e in study["records"]
    id=e["id"]
    occursin(r"^[A-Za-z0-9_-]+$", id)||error("记录标识错误")
    dir=joinpath(dirname(manifest), id)
    bytes2hex(sha256(read(joinpath(dir, "result.toml"))))==e["result_sha256"]||error(
        "旧市场原值变化",
    )
    x=read_r5_market_run(dir)
    x.case.sha256==e["case_sha256"]||error("旧输入变化")
    w=Dict(
        "schema"=>"r5-market-payment-witness-v1",
        "record_id"=>id,
        "case"=>x.case.data,
        "result"=>x.result,
        "parent_result_sha256"=>e["result_sha256"],
        "result_content_sha256"=>bytes2hex(sha256(PaperRebuild.r5_market_text(x.result))),
        "payment"=>r5_market_payment_identity(x.case, x.result),
    )
    text=PaperRebuild.r5_market_text(w)
    write(joinpath(output, "witnesses", id*".toml"), text)
    hashes[id*".toml"]=bytes2hex(sha256(text))
    push!(allw, w)
end
sort!(allw; by = w->w["record_id"])
tables=r5_market_payment_tables(allw)
for (file, rows) in tables
    CSV.write(joinpath(output, file), rows)
end
sources=PaperRebuild.r5_market_science_hashes()
sources["src/verification/r5_market_payment.jl"]=bytes2hex(
    sha256(read(joinpath(root, "src", "verification", "r5_market_payment.jl"))),
)
meta=Dict(
    "schema"=>"r5-market-payment-report-v1",
    "origin"=>"synthetic",
    "solver_reexecuted"=>false,
    "parent_batch_id"=>study["batch_id"],
    "parent_study_sha256"=>bytes2hex(sha256(read(manifest))),
    "parent_source_commit"=>study["source_commit"],
    "source_sha256"=>sources,
    "witness_sha256"=>hashes,
    "records"=>length(allw),
    "valid"=>count(x->x.valid, tables["comparison.csv"]),
    "producer_sha256"=>Dict(
        f=>bytes2hex(sha256(read(joinpath(@__DIR__, f)))) for
        f in ("audit_r5_market_payment.jl", "r5_market_payment_tables.jl")
    ),
    "scope"=>"Whole-horizon payment identity on the original fixed-bid clearing records; no strategic bid optimization or price uniqueness claim.",
)
write(joinpath(output, "report.toml"), PaperRebuild.r5_market_text(meta))
println(
    "Payment identity audit: ",
    meta["valid"],
    "/",
    meta["records"],
    " verified; no old optimization rerun.",
)
