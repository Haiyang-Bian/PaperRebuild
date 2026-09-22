using Test, TOML, SHA
include("r7_normal_flow_study.jl")
length(ARGS)==2 || error("usage: check_r7_normal_flow_audit.jl REPORT AUDIT")
report, audit=abspath.(ARGS)
hashes=TOML.parsefile(joinpath(audit, "files.toml"))["files"]
for (p, h) in hashes
    !isabspath(p)&&!occursin(':', p)&&!occursin('\\', p)&&all(
        x->!(x in ("", ".", "..")),
        split(p, '/'),
    ) || error("审计路径非法")
    bytes2hex(sha256(read(joinpath(audit, p))))==h || error("费用审计被篡改")
end
read(joinpath(report, "inputs.toml"))==read(joinpath(audit, "inputs.toml")) ||
    error("费用审计未使用该冻结输入")
d=TOML.parsefile(joinpath(audit, "audit.toml"));
items, _=flow_inputs(report)
@testset "R7-F5 conservation lower bound and independent witness" begin
    for r in d["records"]
        group=r["group"]
        fixed=only(
            filter(x->x["group"]==group&&x["control"]=="prescribed"&&x["solver"]=="HiGHS", items),
        )
        a=flow_read(joinpath(report, "records", fixed["id"]))
        @test a.result["run_id"]==r["fixed_run_id"]
        @test PaperRebuild.r7_digest(a.result)==r["fixed_record_sha256"]
        @test a.validation["model_pass"]
        if group=="varying_prices"
            @test r["status"]=="not_applicable"
            @test !r["hypotheses"]["constant_price"]
        else
            @test all(values(r["hypotheses"]))
            @test r["status"]=="declared_continuous_domain_closed_by_embedding_A2"
            @test r["analytic_lower_bound_USD"]≈(group=="original_hand" ? 118.4 : 192) atol=1e-10
            @test a.validation["cost_USD"]≈r["analytic_lower_bound_USD"] atol=1e-6
            @test r["bound_kind"]=="analytic_conservation_not_solver_bound"
        end
    end
end
