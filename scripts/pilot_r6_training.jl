include("r5_strategic_setup.jl")

function r6_training_pilot(dest)
    VERSION==v"1.12.6" || error("Julia版本错误")
    ispath(dest) && error("不覆盖开发批次")
    root=normpath(joinpath(@__DIR__, ".."))
    rule=TOML.parsefile(joinpath(root, "configs", "r6", "pilot-rule.toml"))
    rule["schema"]=="r6-training-pilot-v1" || error("开发协议错误")
    # 优化前核验来源文件已提交，避免将开发中的代码混入求解证据。
    files=vcat(
        collect(keys(PaperRebuild.r5_strategic_science_paths())),
        [
            "src/core/r6_protocol.jl",
            "src/core/r6_methods.jl",
            "src/algorithms/r6_data.jl",
            "src/algorithms/r6_methods.jl",
            "src/reporting/r6_data.jl",
            "src/PaperRebuild.jl",
            "configs/r6/pilot-rule.toml",
            "configs/r6/physical-rule.toml",
            rule["physical"],
            "scripts/pilot_r6_training.jl",
        ],
    )
    files=sort(unique(files))
    isempty(read(Cmd(Cmd(vcat(["git", "diff", "HEAD", "--"], files)); dir = root), String)) ||
        error("开发求解前须提交科学代码/规则")
    success(
        pipeline(
            Cmd(Cmd(vcat(["git", "ls-files", "--error-unmatch", "--"], files)); dir = root);
            stdout = devnull,
        ),
    ) || error("求解源码尚未追踪")
    data=read_r6_dataset(joinpath(root, rule["dataset"]))
    physical=load_r6_physical_case(joinpath(root, rule["physical"]))
    optimizer=r5_strategic_optimizer(:gurobi)
    oracle=r5_market_optimizer(:highs)
    mkdir(dest)
    sourcehashes=Dict(f=>bytes2hex(sha256(read(joinpath(root, f)))) for f in files)
    meta=Dict{String,Any}(
        "schema"=>"r6-pilot-result-v1",
        "purpose"=>rule["purpose"],
        "git_commit"=>readchomp(Cmd(Cmd(["git", "rev-parse", "HEAD"]); dir = root)),
        "rule"=>rule,
        "physical_sha256"=>physical.sha256,
        "protocol_sha256"=>data.protocol.sha256,
        "source_hashes"=>sourcehashes,
        "records"=>Dict{String,Any}[],
        "status"=>"started",
    )
    function checkpoint()
        for (f, h) in sourcehashes
            bytes2hex(sha256(read(joinpath(root, f))))==h || error("开发求解中源码变化")
        end
        write(joinpath(dest, "pilot.toml"), PaperRebuild.r5_market_text(meta))
    end
    # 全部派生案例先构造并保存，再开始任何一次优化；没有依据结果选择代表或半径。
    cases=Dict{String,R5StrategicCase}()
    for method in rule["methods"]
        radius=method in ("DRO", "DRJCC") ? rule["radius"] : 0.0
        c=r6_training_case(
            physical,
            data.protocol,
            data.sets["train"],
            data.representatives,
            R6MethodSpec(method; radius, epsilon = rule["epsilon"]);
            development_count = rule["development_count"],
        )
        cases[method]=c
        write(joinpath(dest, method*"-input.toml"), PaperRebuild.r5_market_text(c.data))
    end
    checkpoint()
    for method in rule["methods"]
        c=cases[method]
        println("BEGIN ", method, " case=", c.sha256)
        flush(stdout)
        r=Base.invokelatest(
            solve_r6_training,
            c;
            optimizer,
            oracle_optimizer = oracle,
            budget_sec = rule["budget_sec"],
        )
        runpath=joinpath(dest, method)
        save_r5_strategic_run(c, r, runpath)
        replay=read_r5_strategic_run(runpath)
        v=replay.validation
        push!(
            meta["records"],
            Dict(
                "method"=>method,
                "case_sha256"=>c.sha256,
                "run_id"=>r["run_id"],
                "result_sha256"=>bytes2hex(sha256(read(joinpath(runpath, "result.toml")))),
                "status"=>r["status"],
                "elapsed_sec"=>r["elapsed_sec"],
                "model_pass"=>v["model_pass"],
                "risk_pass"=>v["risk_pass"],
                "cost_complete"=>r["cost_optimization_complete"],
                "training_cost_USD"=>get(v, "worst_total_cost_USD", NaN),
            ),
        )
        checkpoint()
        println(
            "END ",
            method,
            " ",
            r["status"],
            " model=",
            v["model_pass"],
            " risk=",
            v["risk_pass"],
            " cost=",
            get(v, "worst_total_cost_USD", NaN),
            " seconds=",
            r["elapsed_sec"],
        )
        flush(stdout)
    end
    c=r6_training_case(
        physical,
        data.protocol,
        data.sets["train"],
        data.representatives,
        R6MethodSpec(rule["full_build_method"]; epsilon = rule["epsilon"]),
    )
    start=time()
    b=build_r6_model(c)
    meta["full_build"]=Dict(
        "method"=>rule["full_build_method"],
        "case_sha256"=>c.sha256,
        "scenarios"=>length(c.data["risk"]["commitment"]["scenarios"]),
        "elapsed_sec"=>time()-start,
        "variables"=>num_variables(b.model),
        "constraints"=>num_constraints(b.model; count_variable_in_set_constraints = true),
        "sos1_count"=>length(b.market.pairs),
        "model_types"=>b.model_types,
        "optimized"=>false,
    )
    meta["status"]="pilot_completed_not_sample_out_validation"
    checkpoint()
    println("Full support build: ", meta["full_build"])
end

if abspath(PROGRAM_FILE)==(@__FILE__)
    length(ARGS)==1 || error("usage: pilot_r6_training.jl <new-directory>")
    r6_training_pilot(ARGS[1])
end
