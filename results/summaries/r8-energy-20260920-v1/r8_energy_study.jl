include("r8_tradeoff_study.jl")
include("r8_energy_cases.jl")

function r8_energy_records(rule)
    xs=Dict{String,Any}[]
    function add(family, UA, model, mode, solver)
        input=family=="shift_four" ? r8_shift_input(R8_ROOT; UA) :
              r8_mechanism_input(R8_ROOT, family; UA)
        c=input.case
        if family=="shift_four"
            d=c.normal.data
            sum(d["electric"]["load_MW"])==rule["new_electric_load_MW"] ||
                error("协议电负荷与构造器不一致")
            sum(d["heat"]["load_MW"])==rule["new_heat_load_MW"] || error("协议热负荷与构造器不一致")
            for kind in ("CHP", "GT", "EB")
                only(filter(g->g["kind"]==kind, d["devices"]))["P_max_MW"]==rule["new_$(kind)_max_MW"] ||
                    error("协议设备容量与构造器不一致")
            end
        end
        limit=family=="shift_four" ? rule["new_limit_MWh"] : rule["legacy_limit_MWh"]
        s=if model=="detailed"
            r8_spec(
                c,
                input.flow;
                mode,
                penalty_USD_MWh = rule["penalty_USD_MWh"],
                limits_MWh = fill(limit, length(c.specification["events"])),
            )
        else
            h=c.normal.data["heat"]
            cap=[h["c_J_kgK"]*5*(h["S_max_K"]-h["R_min_K"])/1e6 for _ in h["pipes"]]
            r8_energy_spec(
                c;
                mode,
                penalty_USD_MWh = rule["penalty_USD_MWh"],
                pipe_capacity_MW = cap,
                limits_MWh = fill(limit, length(c.specification["events"])),
                loss_rule = UA==0 ? :lossless : :reference_UA,
            )
        end
        id=join((family, "ua$(Int(UA))", model, mode, lowercase(solver)), "_")
        push!(
            xs,
            Dict(
                "id"=>id,
                "family"=>family,
                "UA_W_K"=>UA,
                "model"=>model,
                "mode"=>mode,
                "solver"=>solver,
                "normal"=>c.normal.data,
                "planning"=>c.specification,
                "case_sha256"=>c.sha256,
                "flow"=>input.flow,
                "spec"=>s,
                "spec_sha256"=>PaperRebuild.r7_digest(s),
            ),
        )
    end
    for family in rule["legacy_families"], mode in rule["modes"], solver in rule["solvers"]
        add(family, rule["legacy_UA_W_K"], "energy", mode, solver)
    end
    for UA in rule["new_UA_W_K"],
        model in rule["new_models_to_run"],
        mode in rule["modes"],
        solver in rule["solvers"]

        add("shift_four", UA, model, mode, solver)
    end
    length(xs)==rule["record_count"]==36 || error("稳态对照清单数量错误")
    xs
end

const R8_ENERGY_ORCHESTRATION=(
    "r8_cases.jl",
    "r8_archive.jl",
    "r8_tradeoff_study.jl",
    "r8_energy_cases.jl",
    "r8_energy_study.jl",
    "run_r8_energy_gurobi.jl",
)
function r8_energy_freeze(dest)
    ispath(dest)&&error("不覆盖稳态对照冻结")
    rule=TOML.parsefile(joinpath(R8_ROOT, "configs/r8/energy-flow-study.toml"))
    xs=r8_energy_records(rule)
    parent=joinpath(R8_ROOT, rule["legacy_parent_report"])
    r8_archive_check(parent)
    mkpath(dest)
    write(joinpath(dest, "inputs.toml"), PaperRebuild.r7_text(Dict("records"=>xs)))
    write(joinpath(dest, "rule.toml"), PaperRebuild.r7_text(rule))
    CSV.write(joinpath(dest, "hand-witness.csv"), r8_shift_hand_replay())
    write(
        joinpath(dest, "environment.toml"),
        PaperRebuild.r7_text(
            Dict(
                "origin"=>"synthetic",
                "utc"=>string(now(UTC)),
                "julia_version"=>string(VERSION),
                "git_head"=>strip(r8_capture(`git -C $R8_ROOT rev-parse HEAD`)),
                "git_status"=>r8_capture(`git -C $R8_ROOT status --porcelain`),
                "parent_manifest_sha256"=>r8_file_hash(joinpath(parent, "report-hashes.toml")),
                "seed"=>"deterministic_no_sampling",
            ),
        ),
    )
    for p in keys(PaperRebuild.r8_energy_science_hashes())
        target=joinpath(dest, "code", split(p, '/')...)
        mkpath(dirname(target))
        cp(joinpath(R8_ROOT, p), target)
    end
    # 商用环境与根环境分别锁定；这里只复制锁文件，不读取许可或个人设置内容。
    for p in ("tools/solvers/Project.toml", "tools/solvers/Manifest.toml")
        target=joinpath(dest, "code", split(p, '/')...)
        mkpath(dirname(target))
        cp(joinpath(R8_ROOT, p), target)
    end
    for p in R8_ENERGY_ORCHESTRATION
        cp(joinpath(@__DIR__, p), joinpath(dest, p))
    end
    module_text="module FrozenR8\nusing JuMP,TOML,SHA,Dates,UUIDs\nconst MOI=JuMP.MOI\n"*join(
        "include(\"$p\")\n" for p in PaperRebuild.r8_energy_includes()
    )*"end\n"
    write(joinpath(dest, "code/frozen-module.jl"), module_text)
    write(
        joinpath(dest, "freeze.toml"),
        PaperRebuild.r7_text(
            Dict(
                "files"=>r8_archive_files(dest),
                "science"=>PaperRebuild.r8_energy_science_hashes(),
            ),
        ),
    )
    println("36 same-input comparisons and the analytic witness frozen before optimization.")
end

function r8_energy_current(dir)
    xs, rule, registry=r8_archive_inputs(dir)
    registry["science"]==PaperRebuild.r8_energy_science_hashes() || error("稳态对照科学源码变化")
    for p in R8_ENERGY_ORCHESTRATION
        read(joinpath(dir, p))==read(joinpath(@__DIR__, p)) || error("稳态对照编排改变")
    end
    for p in ("tools/solvers/Project.toml", "tools/solvers/Manifest.toml")
        read(joinpath(dir, "code", p))==read(joinpath(R8_ROOT, p)) || error("商用环境锁文件改变")
    end
    xs, rule
end

function r8_energy_run_group(dir, solver)
    xs, rule=r8_energy_current(dir)
    selected=filter(x->x["solver"]==solver, xs)
    isempty(selected)&&error("求解器未声明")
    any(ispath(joinpath(dir, "records", x["id"])) for x in selected)&&error("不覆盖已开始求解组")
    for x in selected
        r8_energy_current(dir)
        c=R7PlanningCase(R7NormalCase(x["normal"]), x["planning"])
        opt=r8_study_optimizer(solver)
        r=x["model"]=="energy" ?
          solve_r8_energy_case(c, x["spec"]; optimizer = opt, budget_sec = rule["budget_sec"]) :
          solve_r8_case(c, x["flow"], x["spec"]; optimizer = opt, budget_sec = rule["budget_sec"])
        path=joinpath(dir, "records", x["id"])
        stage=path*".writing"
        ispath(stage)&&error("已有未完成记录")
        mkpath(stage)
        write(joinpath(stage, "result.toml"), PaperRebuild.r7_text(r))
        write(
            joinpath(stage, "files.toml"),
            PaperRebuild.r7_text(Dict("files"=>r8_archive_files(stage))),
        )
        mv(stage, path)
        println(
            x["id"],
            " primary=",
            r["primary"]["status"],
            " pass=",
            r["validation"]["primary_model_pass"],
            " evaluation=",
            get(get(r, "evaluation", Dict()), "status", "none"),
            " error=",
            get(r["primary"], "error", "none"),
        )
        flush(stdout)
    end
end

function r8_energy_archive(dir)
    xs, rule, registry=r8_archive_inputs(dir)
    M=r8_archive_module(dir)
    records=Dict{String,Any}()
    for x in xs
        path=joinpath(dir, "records", x["id"])
        files=TOML.parsefile(joinpath(path, "files.toml"))["files"]
        actual=r8_archive_files(path)
        delete!(actual, "files.toml")
        actual==files && Set(keys(files))==Set(["result.toml"]) || error("能流比较原值文件改变")
        r=TOML.parsefile(joinpath(path, "result.toml"))
        records[x["id"]]=Base.invokelatest() do
            c=M.R7PlanningCase(M.R7NormalCase(x["normal"]), x["planning"])
            c.sha256==x["case_sha256"]&&M.r7_digest(x["spec"])==x["spec_sha256"] ||
                error("能流比较输入身份错误")
            expected=x["model"]=="energy" ? M.r8_energy_science_hashes() : M.r8_science_hashes()
            r["source_hashes_at_solve"]==expected || error("运行源码与冻结不符")
            all(registry["science"][p]==h for (p, h) in expected) || error("运行源码未被完整冻结")
            q=x["model"]=="energy" ? M.validate_r8_energy_solution(c, x["spec"], r) :
              M.validate_r8_solution(c, x["flow"], x["spec"], r)
            q==r["validation"] || error("比较摘要与原值不符")
            (; case = c, result = r, validation = q)
        end
    end
    Set(readdir(joinpath(dir, "records")))==Set(keys(records)) || error("存在未声明运行")
    if isfile(joinpath(dir, "report-hashes.toml"))
        actual=r8_archive_files(dir)
        delete!(actual, "report-hashes.toml")
        actual==TOML.parsefile(joinpath(dir, "report-hashes.toml"))["files"] ||
            error("能流报告变更")
    end
    (; items = xs, rule, records)
end

function r8_energy_tables(x)
    [
        begin
            r=x.records[item["id"]].result
            p=r["validation"]["primary"]
            ev=get(r["validation"], "evaluation", Dict())
            (;
                id = item["id"],
                run_id = r["run_id"],
                family = item["family"],
                UA_W_K = item["UA_W_K"],
                model = item["model"],
                mode = item["mode"],
                solver = item["solver"],
                primary_status = r["primary"]["status"],
                primary_pass = p["model_pass"],
                primary_complete = p["objective_complete"],
                normal_cost_USD = get(p, "normal_cost_USD", missing),
                solver_objective = get(r["primary"], "solver_objective", missing),
                objective_kind = r["primary"]["objective_kind"],
                evaluation_status = get(get(r, "evaluation", Dict()), "status", "not_run"),
                evaluation_pass = get(ev, "model_pass", false),
                risk_complete = get(ev, "objective_complete", false),
                worst_upper_MWh = haskey(ev, "event_upper_MWh") ? maximum(ev["event_upper_MWh"]) :
                                  missing,
                worst_lower_MWh = haskey(ev, "event_lower_MWh") ? maximum(ev["event_lower_MWh"]) :
                                  missing,
                elapsed_sec = r["elapsed_sec"],
                wall_budget_pass = r["wall_budget_pass"],
            )
        end for item in x.items
    ]
end

function r8_energy_report(src, dest)
    ispath(dest)&&error("不覆盖能流比较报告")
    x=r8_energy_archive(src)
    cp(src, dest)
    CSV.write(joinpath(dest, "summary.csv"), r8_energy_tables(x))
    write(
        joinpath(dest, "report-hashes.toml"),
        PaperRebuild.r7_text(Dict("files"=>r8_archive_files(dest))),
    )
    r8_energy_archive(dest)
    println("36 energy/detailed records replayed from frozen source and preserved.")
end

if abspath(PROGRAM_FILE)==@__FILE__
    if length(ARGS)==2&&ARGS[1]=="freeze"
        r8_energy_freeze(abspath(ARGS[2]))
    elseif length(ARGS)==3&&ARGS[1]=="run"
        Core.eval(
            @__MODULE__,
            ARGS[3]=="HiGHS" ? :(using HiGHS) :
            ARGS[3]=="Gurobi" ? :(using Gurobi) : error("未知求解器"),
        )
        Base.invokelatest(r8_energy_run_group, abspath(ARGS[2]), ARGS[3])
    elseif length(ARGS)==3&&ARGS[1]=="report"
        r8_energy_report(abspath.(ARGS[2:3])...)
    elseif length(ARGS)==2&&ARGS[1]=="check"
        x=r8_energy_archive(abspath(ARGS[2]))
        io=IOBuffer()
        CSV.write(io, r8_energy_tables(x))
        take!(io)==read(joinpath(ARGS[2], "summary.csv")) || error("能流汇总不符")
        println("36 frozen records checked without optimization.")
    else
        error("usage: freeze NEW | run FROZEN HiGHS/Gurobi | report SRC NEW | check REPORT")
    end
end
