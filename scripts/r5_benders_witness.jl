using PaperRebuild, TOML, SHA

function r5_benders_evidence_order(v)
    if v isa AbstractDict
        d=Dict{String,Any}(string(k)=>r5_benders_evidence_order(x) for (k, x) in v)
        if haskey(d, "rows")
            # 缓存排序键，避免比较排序反复序列化同一残差行；不改规范化顺序。
            keys=PaperRebuild.r5_market_text.(d["rows"])
            d["rows"]=d["rows"][sortperm(keys)]
        end
        return d
    elseif v isa AbstractVector
        return [r5_benders_evidence_order(x) for x in v]
    end
    v
end
r5_benders_evidence_hash(v) =
    bytes2hex(sha256(PaperRebuild.r5_market_text(r5_benders_evidence_order(v))))
function r5_benders_raw_data(v)
    v isa AbstractDict&&return Dict(
        string(k)=>r5_benders_raw_data(x) for (k, x) in v if k!="validation"
    )
    v isa AbstractVector&&return [r5_benders_raw_data(x) for x in v]
    v
end
r5_benders_raw_hash(v) = bytes2hex(sha256(PaperRebuild.r5_market_text(r5_benders_raw_data(v))))

"""拆分公开分解见证，保留全部原值/乘子/割；可重新计算的验算表只存规范化哈希。"""
function r5_benders_write_witness(c, r, directory, parent_hash)
    ispath(directory)&&error("不覆盖分解公开见证")
    mkpath(joinpath(directory, "subproblems"))
    d=deepcopy(r)
    checks=Dict{String,String}("result"=>r5_benders_evidence_hash(pop!(d, "validation")))
    sources=pop!(d, "subproblems")
    files=Dict{String,String}()
    for id in sort!(collect(keys(sources)))
        occursin(r"^[A-Za-z0-9_-]+$", id)||error("子问题标识非法")
        src=sources[id]
        checks[id]=r5_benders_evidence_hash(pop!(src, "validation"))
        rel="subproblems/$id.toml"
        text=PaperRebuild.r5_market_text(src)
        files[rel]=bytes2hex(sha256(text))
        write(joinpath(directory, split(rel, '/')...), text)
    end
    for (i, step) in enumerate(d["iterations"])
        haskey(step, "master")&&(
            checks["master/$i"]=r5_benders_evidence_hash(pop!(step["master"], "validation"))
        )
        haskey(step, "candidate")&&(
            checks["candidate/$i"]=r5_benders_evidence_hash(pop!(step["candidate"], "validation"))
        )
    end
    witness=Dict(
        "schema"=>"r5-benders-public-witness-v1",
        "case"=>c.data,
        "result"=>d,
        "parent_result_sha256"=>parent_hash,
        "raw_result_content_sha256"=>r5_benders_raw_hash(r),
        "validation_sha256"=>checks,
        "source_files_sha256"=>files,
    )
    write(joinpath(directory, "witness.toml"), PaperRebuild.r5_market_text(witness))
end

"""不依赖results/runs，独立重算公开见证的全部验收；不调用任何求解器。"""
function r5_benders_read_witness(directory)
    w=TOML.parsefile(joinpath(directory, "witness.toml"))
    w["schema"]=="r5-benders-public-witness-v1"||error("公开见证版本错误")
    c=R5RiskCase(w["case"])
    r=w["result"]
    checks=w["validation_sha256"]
    Set(
        replace(relpath(joinpath(base, f), directory), '\\'=>'/') for
        (base, _, fs) in walkdir(joinpath(directory, "subproblems")) for f in fs
    )==Set(keys(w["source_files_sha256"]))||error("子问题公开清单改变")
    r["subproblems"]=Dict{String,Any}()
    used=Set(["result"])
    function verified(label, v)
        r5_benders_evidence_hash(v)==checks[label]||error("公开见证验算改变：$label")
        push!(used, label)
        v
    end
    for rel in sort!(collect(keys(w["source_files_sha256"])))
        occursin(r"^subproblems/[A-Za-z0-9_-]+\.toml$", rel)||error("公开子问题路径非法")
        path=joinpath(directory, split(rel, '/')...)
        islink(path)&&error("公开见证不允许链接")
        bytes2hex(sha256(read(path)))==w["source_files_sha256"][rel]||error("公开子问题篡改")
        src=TOML.parsefile(path)
        id=src["run_id"]
        rel=="subproblems/$id.toml"||error("子问题文件身份不同")
        src["validation"]=verified(id, validate_r5_benders_subproblem(c, src))
        r["subproblems"][id]=src
    end
    spec=PaperRebuild.r5_benders_spec(r["spec"])
    # 与正式验证器使用相同的来源重建割；不能让TOML字典插入顺序改变浮点求和次序。
    rebuilt_cuts=Dict(
        id=>r5_benders_cut(c, r["subproblems"][id]; arithmetic = spec.cut_arithmetic) for
        id in r["cut_order"]
    )
    for (i, step) in enumerate(r["iterations"])
        if haskey(step, "master")
            m=step["master"]
            m["validation"]=verified(
                "master/$i",
                PaperRebuild.r5_benders_master_check(
                    c,
                    spec,
                    m,
                    [rebuilt_cuts[id] for id in m["cut_source_ids"]],
                ),
            )
        end
        if haskey(step, "candidate")
            p=step["candidate"]
            p["validation"]=verified(
                "candidate/$i",
                PaperRebuild.r5_benders_candidate_check(c, p, r["subproblems"]),
            )
        end
    end
    r["validation"]=verified("result", validate_r5_benders(c, r))
    used==Set(keys(checks))||error("公开验算哈希遗漏或多余")
    r5_benders_raw_hash(r)==w["raw_result_content_sha256"]||error("公开原值与父记录内容不同")
    r["cost_optimization_complete"]==(
        r["status"]=="full_domain_gap"&&r["validation"]["optimality_pass"]
    )||error("公开费用完成状态改变")
    (; case = c, result = r, parent_result_sha256 = w["parent_result_sha256"])
end
