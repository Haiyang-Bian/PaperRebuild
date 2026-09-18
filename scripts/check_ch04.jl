include("ch04_docs.jl")
sync_ch04(; check = !("--sync" in ARGS))
if !("--records-only" in ARGS)
    root, forms, _, _=ch04_records()
    source=join(
        read(joinpath(root, p), String) for p in (
            "src/formulations/r4.jl",
            "src/reporting/r4_runs.jl",
            "src/verification/r4.jl",
            "src/formulations/r4_reconfiguration.jl",
        )
    )
    tests=read(joinpath(root, "test", "r4.jl"), String)*read(
        joinpath(root, "test", "r4_reconfiguration.jl"),
        String,
    )
    for r in forms["formula"]
        isempty(r["api"]) && continue
        occursin("function "*r["api"], source) || error("第4章API映射缺失")
        occursin(r["test"], tests) || error("第4章测试映射缺失")
    end
    println("Chapter 4 API and test mappings checked.")
end
