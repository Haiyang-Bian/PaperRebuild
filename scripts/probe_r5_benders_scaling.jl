using PaperRebuild, JuMP, HiGHS, TOML
include("r5_risk_setup.jl")

length(ARGS)==2 || error("参数：已有边界目录 新缩放审计目录")
source=abspath(ARGS[1]);
target=abspath(ARGS[2])
ispath(target)&&error("不覆盖缩放审计")
c=load_r5_risk_case(joinpath(source, "case.toml"))
old=TOML.parsefile(joinpath(source, "result.toml"))
records=Dict{String,Any}[]
for step in old["iterations"], (_, id) in step["diagnostic_source_ids"]
    r=old["subproblems"][id]
    r["scenario"]==3||continue
    sys=PaperRebuild.r5_benders_system(c, 3, r["first_stage"], r["branch"]; elastic = true)
    x=PaperRebuild.r5_benders_flat(r["first_stage"])
    # 一次预声明的2^10变量缩放：u=1024*y。二进制乘除不改变系数的有效位。
    scale=1024.0
    m=Model(r5_risk_optimizer(:highs))
    set_silent(m)
    u=Dict(k=>@variable(m, base_name=k) for k in keys(sys.cost))
    rows=Dict{String,Any}()
    for (key, row) in sys.rows
        lhs=sum(a*u[k] for (k, a) in row.coefficients)
        rhs=scale*PaperRebuild.r5_benders_rhs_value(row, x)
        rows[key]=row.sense==:eq ? @constraint(m, lhs==rhs) :
                  row.sense==:ge ? @constraint(m, lhs>=rhs) : @constraint(m, lhs<=rhs)
    end
    @objective(m, Min, sum((v/scale)*u[k] for (k, v) in sys.cost))
    optimize!(m)
    rr=Dict{String,Any}(
        "source_run_id"=>id,
        "iteration"=>step["iteration"],
        "scale"=>scale,
        "termination"=>string(termination_status(m)),
    )
    if has_values(m)&&has_duals(m)
        y=Dict(k=>value(v)/scale for (k, v) in u)
        raw=Dict(k=>dual(v) for (k, v) in rows)
        converted=Dict(k=>v*scale for (k, v) in raw)
        check=PaperRebuild.r5_benders_lp_check(sys, x, y, converted, objective_value(m))
        cut=PaperRebuild.r5_benders_rational_minorant(sys, converted)
        merge!(
            rr,
            Dict(
                "values"=>y,
                "raw_scaled_duals"=>raw,
                "converted_original_duals"=>converted,
                "objective"=>objective_value(m),
                "check"=>check,
                "minorant"=>cut,
            ),
        )
        println(
            "iteration ",
            step["iteration"],
            " objective=",
            objective_value(m),
            " kkt=",
            check["kkt_pass"],
            " cutconstant=",
            cut["constant"],
            " minimum_elastic=",
            minimum(v for (k, v) in y if startswith(k, "elastic/")),
        )
    end
    push!(records, rr)
end
mkpath(target)
write(
    joinpath(target, "probe.toml"),
    PaperRebuild.r5_market_text(
        Dict("input_sha256"=>c.sha256, "source_run_id"=>old["run_id"], "records"=>records),
    ),
)
cp(@__FILE__, joinpath(target, "probe-source.jl"))
