# 保留成功与失败运行的可公开合成摘要，不读取许可证或求解器原始控制台。
using PaperRebuild, TOML

length(ARGS) == 3 || error("传入 Clarabel、严格容差Gurobi、默认容差Gurobi 三个运行目录")
root = normpath(joinpath(@__DIR__, "..", "results", "summaries", "r1-first-batch"))
mkpath(root)
records = Dict{String,Any}[]
for (role, dir) in zip(("clarabel", "gurobi_strict", "gurobi_default_failure"), ARGS)
    saved = read_r1_run(dir)
    report = validate_r1_solution(saved.case, saved.result)
    target = joinpath(root, saved.metadata["run_id"])
    if !isdir(target)
        mkdir(target)
        for file in
            ("case.toml", "metadata.toml", "solution.toml", "validation.toml", "residuals.csv")
            cp(joinpath(dir, file), joinpath(target, file))
        end
    end
    push!(
        records,
        Dict(
            "role" => role,
            "run_id" => saved.metadata["run_id"],
            "input_sha256" => saved.case.sha256,
            "objective" => saved.result["objective"],
            "bound" => get(saved.result, "bound", NaN),
            "solver_status" => saved.result["status"],
            "relaxed_pass" => report.relaxed_pass,
            "original_branch_pass" => report.original_branch_pass,
            "max_original_residual" =>
                maximum(r.residual for r in report.rows if r.id == "ch02-025-original"),
            "max_normalized_residual" => maximum(r.residual / r.tolerance for r in report.rows),
        ),
    )
end
length(unique(r["input_sha256"] for r in records)) == 1 || error("不能对照不同输入")
path = joinpath(root, "comparison.toml")
isfile(path) && error("比较摘要已存在；新实验应另设摘要批次")
open(
    io -> TOML.print(
        io,
        Dict("scope" => "synthetic fixed-flow two-node subset", "run" => records);
        sorted = true,
    ),
    path,
    "w",
)
println("Saved comparison including failure: ", path)
