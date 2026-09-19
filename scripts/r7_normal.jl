using PaperRebuild, JuMP, HiGHS, TOML, SHA

function normal_cli(args)
    usage="r7_normal.jl run CASE OUTPUT | check RUN | event RUN START PERIODS RENEWABLE_FACTOR LOSS_LIMIT_MWh OUTPUT | check-event NORMAL_RUN EVENT_RUN"
    !isempty(args) || error(usage)
    opt=optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,
        "mip_rel_gap"=>1e-9,
    )
    if args[1]=="run" && length(args)==3
        ispath(args[3])&&error("不覆盖旧运行")
        c=load_r7_normal_case(args[2])
        r=solve_r7_normal(c; optimizer = opt, budget_sec = 600)
        save_r7_normal(c, r, args[3])
        println(
            "normal status=",
            r["status"],
            " model=",
            r["candidate_accepted"],
            " conditional_cost_complete=",
            r["conditional_cost_complete"],
        )
    elseif args[1]=="check" && length(args)==2
        r=read_r7_normal(args[2])
        println(
            "normal original values revalidated: ",
            r.validation["model_pass"],
            " pipe reference=",
            r.validation["pipe_reference_pass"],
        )
    elseif args[1]=="event" && length(args)==7
        started=time()
        deadline=started+600
        dest=args[7]
        ispath(dest)&&error("不覆盖旧事件目录")
        parent=read_r7_normal(args[2])
        event=r7_normal_event(
            parent.case,
            parent.result;
            event_start = parse(Int, args[3]),
            periods = parse(Int, args[4]),
            renewable_factor = parse(Float64, args[5]),
            loss_limit_MWh = parse(Float64, args[6]),
        )
        mkpath(dest)
        write(joinpath(dest, "case.toml"), PaperRebuild.r7_text(event.case.data))
        write(joinpath(dest, "handoff.toml"), PaperRebuild.r7_text(event.evidence))
        records=Dict{String,Any}[]
        for (i, fault) in enumerate(r7_faults(event.case))
            r=solve_r7_recovery(
                event.case,
                fault;
                optimizer = opt,
                budget_sec = max(0, deadline-time()),
                deadline,
            )
            r["parent_normal_run_id"]=parent.result["run_id"]
            r["parent_normal_result_sha256"]=event.evidence["parent_result_sha256"]
            path="fault-"*lpad(string(i), 3, '0')
            save_r7_recovery(event.case, r, joinpath(dest, path))
            push!(
                records,
                Dict(
                    "fault"=>fault,
                    "directory"=>path,
                    "run_id"=>r["run_id"],
                    "status"=>r["status"],
                    "model_pass"=>r["candidate_accepted"],
                ),
            )
        end
        write(
            joinpath(dest, "event.toml"),
            PaperRebuild.r7_text(
                Dict(
                    "schema"=>"r7-normal-event-runs-v1",
                    "parent_case_sha256"=>parent.case.sha256,
                    "parent_run_id"=>parent.result["run_id"],
                    "elapsed_sec"=>time()-started,
                    "budget_sec"=>600.0,
                    "records"=>records,
                    "scope"=>"conditional_preplan_given_fault_recovery_not_full_planning",
                ),
            ),
        )
        hashes=Dict(
            replace(relpath(joinpath(path, file), dest), '\\'=>'/')=>bytes2hex(
                sha256(read(joinpath(path, file))),
            ) for (path, _, files) in walkdir(dest) for file in files
        )
        write(joinpath(dest, "event-files.toml"), PaperRebuild.r7_text(Dict("files"=>hashes)))
        println(
            "event inherited from ",
            parent.result["run_id"],
            "; recorded ",
            length(records),
            " allowed faults",
        )
    elseif args[1]=="check-event" && length(args)==3
        parent=read_r7_normal(args[2])
        dest=args[3]
        manifest=TOML.parsefile(joinpath(dest, "event-files.toml"))["files"]
        actual=Set(
            replace(relpath(joinpath(path, file), dest), '\\'=>'/') for
            (path, _, files) in walkdir(dest) for file in files
        )
        actual==union(Set(keys(manifest)), Set(["event-files.toml"])) || error("事件存档清单不完整")
        for (p, hash) in manifest
            !isabspath(p)&&!occursin(':', p)&&!occursin('\\', p)&&all(
                x->!(x in ("", ".", "..")),
                split(p, '/'),
            ) || error("事件路径非法")
            bytes2hex(sha256(read(joinpath(dest, split(p, '/')...))))==hash ||
                error("事件存档被改变")
        end
        ec=load_r7_recovery_case(joinpath(dest, "case.toml"))
        ev=TOML.parsefile(joinpath(dest, "handoff.toml"))
        rebuilt=r7_normal_event(
            parent.case,
            parent.result;
            event_start = ec.data["event_start"],
            periods = ec.data["periods"],
            renewable_factor = ec.data["renewable_factor"],
            loss_limit_MWh = ec.data["loss_limit_MWh"],
        )
        rebuilt.case.sha256==ec.sha256 && isequal(rebuilt.evidence, ev) ||
            error("事件初值与原正常轨迹不同")
        meta=TOML.parsefile(joinpath(dest, "event.toml"))
        meta["schema"]=="r7-normal-event-runs-v1" &&
        meta["parent_case_sha256"]==parent.case.sha256 &&
        meta["parent_run_id"]==parent.result["run_id"] || error("事件父计划身份错误")
        [x["fault"] for x in meta["records"]]==r7_faults(ec) || error("事件记录未覆盖冻结故障集合")
        for record in meta["records"]
            dir=record["directory"]
            occursin(r"^fault-[0-9]+$", dir) || error("故障记录目录非法")
            x=read_r7_recovery(joinpath(dest, dir))
            x.case.sha256==ec.sha256 &&
            x.result["fault"]==record["fault"] &&
            x.result["run_id"]==record["run_id"] &&
            x.result["status"]==record["status"] &&
            x.validation["model_pass"]==record["model_pass"] &&
            x.result["parent_normal_run_id"]==parent.result["run_id"] &&
            x.result["parent_normal_result_sha256"]==ev["parent_result_sha256"] ||
                error("恢复与父轨迹或摘要不同")
        end
        println("event original values and normal-state handoff revalidated; no optimization")
    else
        error(usage)
    end
end

abspath(PROGRAM_FILE)==(@__FILE__) && normal_cli(ARGS)
