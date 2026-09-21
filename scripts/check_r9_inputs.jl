using PaperRebuild, TOML
include("r9_docs.jl")
root=normpath(joinpath(@__DIR__, ".."))
ARGS in (String[], ["--sync"]) || error("usage: check_r9_inputs.jl [--sync]")
b=load_r9_sources(joinpath(root, "docs/reading/ch07"))
a=audit_r9_sources(b)
m=TOML.parsefile(joinpath(root, "docs/reading/ch07/migration.toml"))
m["schema"]=="r9-migration-route-v1" &&
m["status"]=="partial_72_duals_open_73_central_network_verified_disagreement_open" ||
    error("迁移状态变更需新验收；此处仍保留对偶、分歧点和后续章节缺口")
Set(r["section"] for r in m["route"])==Set(["7.2", "7.3", "7.4", "7.5"]) || error("场景迁移缺失")
testname="R9 original topology, units, arithmetic and missing-input gates"
occursin(testname, read(joinpath(root, "test/r9_sources.jl"), String)) || error("缺少输入核查测试")
for api in (:load_r9_sources, :r9_tariff, :r9_original_input_gate, :audit_r9_sources)
    isdefined(PaperRebuild, api) || error("API不存在")
end
page=joinpath(root, "docs/src/ch07-inputs-generated.md")
expected=r9_markdown(root)
"--sync" in ARGS && write(page, expected)
read(page, String)==expected || error("第7章生成页失步")
println(
    "R9 source/migration mapping passed; ",
    length(a["rows"]),
    " arithmetic rows; this source check does not run optimization.",
)
