using PaperRebuild, TOML, SHA
root=normpath(joinpath(@__DIR__, ".."))
target=joinpath(root, "configs", "r4", "heat-compatibility-study.toml")
ispath(target) && error("不覆盖既有冻结配置")
batch="results/runs/r4/r4-network-20260919"
study_path=joinpath(root, batch, "study.toml")
study=TOML.parsefile(study_path)
records=Dict{String,Any}[]
for x in study["records"]
    path=joinpath(root, batch, x["id"])
    read_r4_run(path)
    push!(
        records,
        Dict(
            "id"=>x["id"],
            "case"=>x["case"],
            "policy"=>x["policy"],
            "electric"=>x["electric"],
            "input_sha256"=>x["input_sha256"],
            "result_sha256"=>x["result_sha256"],
        ),
    )
end
config=Dict(
    "version"=>"r4-heat-study-v1",
    "origin"=>"synthetic",
    "parent_batch"=>batch,
    "parent_study_sha256"=>bytes2hex(sha256(read(study_path))),
    "budget_sec"=>600.0,
    "stages"=>["fixed_envelope", "free_envelope", "fixed_mixing", "free_mixing"],
    "stage_budget_sec"=>[30.0, 30.0, 240.0, 300.0],
    "bands"=>[
        Dict("id"=>"reference10", "supply_K"=>[343.15, 363.15], "return_K"=>[303.15, 323.15]),
        Dict("id"=>"reference20", "supply_K"=>[333.15, 373.15], "return_K"=>[293.15, 333.15]),
    ],
    "interpretation"=>"Reference supply/return 353.15/313.15 K with +/-10 or +/-20 K; project diagnostic bounds, frozen before solving. Parent controls/heat/pipe losses unchanged within old A1.",
    "records"=>records,
)
write(target, PaperRebuild.r4_text(config))
println("Frozen 34 parents × 2 temperature bands; no optimization executed.")
