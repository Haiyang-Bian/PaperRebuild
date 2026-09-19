include("r5_benders_witness.jl")

"""拆分市场分解原值；保存每轮与每个条件LP，验算表用规范化哈希代替重复副本。"""
function r5_sb_write_witness(c, r, directory, parent_hash)
    ispath(directory) && error("不覆盖策略分解公开见证")
    mkpath(directory)
    d = deepcopy(r)
    checks = Dict{String,String}("result"=>r5_benders_evidence_hash(pop!(d, "validation")))
    files = Dict{String,String}()
    function save(rel, item)
        text = PaperRebuild.r5_market_text(item)
        sizeof(text) < 5*1024^2 || error("公开分块过大：$rel")
        p = joinpath(directory, split(rel, '/')...)
        mkpath(dirname(p))
        write(p, text)
        files[rel] = bytes2hex(sha256(text))
    end
    for (id, src) in pop!(d, "subproblems")
        occursin(r"^[A-Za-z0-9_-]+$", id) || error("子问题标识非法")
        checks[id] = r5_benders_evidence_hash(pop!(src, "validation"))
        save("subproblems/$id.toml", src)
    end
    iterations = pop!(d, "iterations")
    for (i, step) in enumerate(iterations)
        if haskey(step, "master")
            checks["master/$i"] = r5_benders_evidence_hash(pop!(step["master"], "validation"))
        end
        if haskey(step, "candidate")
            p = step["candidate"]
            checks["candidate/$i"] = r5_benders_evidence_hash(pop!(p, "validation"))
            checks["risk/$i"] = r5_benders_evidence_hash(pop!(p["risk_candidate"], "validation"))
        end
        save("iterations/"*lpad(i, 4, '0')*".toml", step)
    end
    w = Dict(
        "schema"=>"r5-strategic-benders-public-v1",
        "case"=>c.data,
        "result"=>d,
        "iteration_count"=>length(iterations),
        "parent_result_sha256"=>parent_hash,
        "raw_result_content_sha256"=>r5_benders_raw_hash(r),
        "validation_sha256"=>checks,
        "files_sha256"=>files,
    )
    write(joinpath(directory, "witness.toml"), PaperRebuild.r5_market_text(w))
end

"""仅从公开分块独立重建市场、情景、割和总费用证据；不依赖本地运行目录、不优化。"""
function r5_sb_read_witness(directory)
    islink(directory) && error("公开见证不得为链接")
    w = TOML.parsefile(joinpath(directory, "witness.toml"))
    w["schema"] == "r5-strategic-benders-public-v1" || error("策略分解公开版本不符")
    inventory = Set(
        replace(relpath(joinpath(base, f), directory), '\\'=>'/') for
        (base, _, fs) in walkdir(directory) for f in fs
    )
    inventory == union(Set(keys(w["files_sha256"])), Set(["witness.toml"])) ||
        error("公开分块清单变化")
    for (rel, hash) in w["files_sha256"]
        occursin(r"^(subproblems/[A-Za-z0-9_-]+|iterations/[0-9]{4})\.toml$", rel) ||
            error("公开路径非法")
        path = joinpath(directory, split(rel, '/')...)
        !islink(path) && bytes2hex(sha256(read(path))) == hash || error("公开分块篡改：$rel")
    end
    checks = w["validation_sha256"]
    used = Set{String}()
    function verified(label, v)
        r5_benders_evidence_hash(v) == checks[label] || error("公开验算变化：$label")
        push!(used, label)
        v
    end
    c = R5StrategicCase(w["case"])
    rc = R5RiskCase(c.data["risk"])
    r = w["result"]
    r["subproblems"] = Dict{String,Any}()
    for rel in sort!(filter(p->startswith(p, "subproblems/"), collect(keys(w["files_sha256"]))))
        src = TOML.parsefile(joinpath(directory, split(rel, '/')...))
        id = src["run_id"]
        rel == "subproblems/$id.toml" || error("条件LP身份不同")
        src["validation"] = verified(id, validate_r5_benders_subproblem(rc, src))
        r["subproblems"][id] = src
    end
    spec = PaperRebuild.r5_benders_spec(r["spec"])
    pattern = get(r, "complementarity_pattern", nothing)
    rebuilt = Dict(
        id=>r5_benders_cut(rc, r["subproblems"][id]; arithmetic = spec.cut_arithmetic) for
        id in r["cut_order"]
    )
    r["iterations"] = Dict{String,Any}[]
    for i in 1:w["iteration_count"]
        step = TOML.parsefile(joinpath(directory, "iterations", lpad(i, 4, '0')*".toml"))
        if haskey(step, "master")
            m = step["master"]
            m["validation"] = verified(
                "master/$i",
                PaperRebuild.r5_strategic_benders_master_check(
                    c,
                    spec,
                    m,
                    [rebuilt[id] for id in m["cut_source_ids"]],
                    pattern,
                ),
            )
        end
        if haskey(step, "candidate")
            p = step["candidate"]
            q = p["risk_candidate"]
            q["validation"] = verified(
                "risk/$i",
                PaperRebuild.r5_benders_candidate_check(rc, q, r["subproblems"]),
            )
            p["validation"] = verified(
                "candidate/$i",
                PaperRebuild.r5_strategic_benders_candidate_check(c, p, r["subproblems"], pattern),
            )
        end
        push!(r["iterations"], step)
    end
    r["validation"] = verified("result", validate_r5_strategic_benders(c, r))
    used == Set(keys(checks)) || error("公开验算清单变化")
    r5_benders_raw_hash(r) == w["raw_result_content_sha256"] || error("公开原值不同于父记录")
    done = PaperRebuild.r5_strategic_benders_completion(r, r["validation"])
    r["cost_optimization_complete"] == done.full &&
    r["declared_branch_cost_complete"] == done.branch || error("完成声明改变")
    (; case = c, result = r, parent_result_sha256 = w["parent_result_sha256"])
end
