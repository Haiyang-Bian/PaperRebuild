using Test
include("r8_tradeoff_study.jl")
rule=TOML.parsefile(joinpath(R8_ROOT, "configs/r8/tradeoff-study.toml"))
xs=r8_study_records(rule)
@testset "R8 frozen input controls and report protocol" begin
    @test length(xs)==34
    @test length(unique(x["id"] for x in xs))==34
    @test count(x->x["solver"]=="HiGHS", xs)==12
    @test count(x->x["solver"]=="Gurobi", xs)==22
    for x in xs
        c=R7PlanningCase(R7NormalCase(x["normal"]), x["planning"])
        @test PaperRebuild.r8_check(c, x["flow"], x["spec"])===nothing
        @test x["normal"]["battery_rule"]=="per_period_exclusive_v1"
        @test PaperRebuild.r8_loss_caps(c)≈[1.2, 1.2]
    end
    for solver in ("HiGHS", "Gurobi")
        rows=filter(x->x["family"]=="legacy"&&x["control"]=="fixed"&&x["solver"]==solver, xs)
        @test length(unique(x["case_sha256"] for x in rows))==1
        @test length(unique(x["flow_sha256"] for x in rows))==1
    end
    base=only(
        filter(
            x->x["family"]=="tie_three"&&x["resource"]=="all"&&x["control"]=="fixed"&&x["mode"]=="threshold"&&x["limit_MWh"]==0.4,
            xs,
        ),
    )
    for resource in ("no_net_heat_charge", "no_reconfiguration")
        y=only(
            filter(x->x["family"]=="tie_three"&&x["resource"]==resource&&x["solver"]=="Gurobi", xs),
        )
        a, b=deepcopy(base["normal"]), deepcopy(y["normal"])
        delete!(a, "name")
        delete!(b, "name")
        @test a==b
        @test base["planning"]==y["planning"]
    end
    no_bes=only(filter(x->x["resource"]=="no_battery"&&x["solver"]=="Gurobi", xs))
    a, b=deepcopy(base["normal"]), deepcopy(no_bes["normal"])
    delete!(a, "name")
    delete!(b, "name")
    filter!(g->g["kind"]!="BES", a["devices"])
    a["electric"]["root_eligible"][3]=0
    @test a==b
    mktempdir() do dir
        batch=joinpath(dir, "batch")
        r8_study_freeze(batch)
        y=r8_archive_check(batch; complete = false)
        @test isempty(y.records)
        @test length(y.items)==34
        item=first(y.items)
        c=R7PlanningCase(R7NormalCase(item["normal"]), item["planning"])
        r=solve_r8_case(
            c,
            item["flow"],
            item["spec"];
            optimizer = ()->error("must not run"),
            budget_sec = 0,
        )
        record=joinpath(batch, "records", item["id"])
        mkpath(record)
        write(joinpath(record, "result.toml"), PaperRebuild.r7_text(r))
        write(
            joinpath(record, "files.toml"),
            PaperRebuild.r7_text(Dict("files"=>r8_archive_files(record))),
        )
        reread=r8_archive_check(batch; complete = false)
        @test only(values(reread.records)).result["primary"]["status"]=="budget_exhausted"
        @test_throws ErrorException r8_archive_check(batch)
        @test_throws ErrorException r8_study_freeze(batch)
        open(joinpath(batch, "rule.toml"), "a") do io
            write(io, "\n# modified\n")
        end
        @test_throws ErrorException r8_archive_inputs(batch)
    end
end
