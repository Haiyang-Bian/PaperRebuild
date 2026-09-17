include("r3_setup.jl")

# 冻结规则与精确初值先于任何本批优化；从v3冻结清单追溯v2来源。
priorfile="configs/r3/v3-study.toml"
prior=TOML.parsefile(priorfile)
root="configs/r3/baseline-inputs"
mkpath(root)
entries=Dict{String,Any}[]
function write_once(path, bytes)
    if isfile(path)
        read(path)==bytes || error("冻结文件已存在且内容不同：$path")
    else
        write(path, bytes)
    end
end
function encoded(data)
    io=IOBuffer()
    TOML.print(io, data; sorted = true)
    return take!(io)
end
function source_entry(id)
    e=only(x for x in prior["entries"] if x["group"]!="ablation" && x["id"]==id)
    c=load_r2_case(e["case_path"])
    c.sha256==e["input_sha256"] || error("历史输入改变")
    PaperRebuild.r2_flow_hash(PaperRebuild.r3_matrix(e["initial_flow"]))==e["initial_flow_sha256"] ||
        error("历史初值改变")
    open(joinpath(e["v2_directory"], "run.toml")) do io
        bytes2hex(sha256(io))==e["run_sha256"] || error("历史运行改变")
    end
    return c, e
end
function add_entry(
    name,
    c,
    e;
    id,
    group,
    initial_label,
    geometry = "physical_euclidean",
    displacement = 0.1,
    boundary = "original",
    operation = nothing,
    initial = e["initial_flow"],
    reference = false,
)
    path=joinpath(root, c.data["id"]*".toml")
    # 普通案例保留原配置字节；派生core_only使用已声明的排序序列化。
    bytes=boundary=="core_only" ? encoded(c.data) : read(e["case_path"])
    bytes2hex(sha256(bytes))==c.sha256 || error("案例序列化哈希不同")
    write_once(path, bytes)
    row=Dict{String,Any}(
        "id"=>id,
        "group"=>group,
        "case_group"=>name,
        "initial_label"=>initial_label,
        "boundary"=>boundary,
        "case_path"=>replace(path, '\\'=>'/'),
        "input_sha256"=>c.sha256,
        "source_run_id"=>e["source_run_id"],
        "source_run_sha256"=>e["run_sha256"],
        "source_directory"=>e["v2_directory"],
        "method"=>reference ? "reference" : "baseline",
    )
    if !reference
        row["geometry"]=geometry
        row["initial_displacement"]=displacement
        row["initial_flow"]=initial
        row["initial_flow_sha256"]=PaperRebuild.r2_flow_hash(PaperRebuild.r3_matrix(initial))
    end
    isnothing(operation) || (row["operation"]=PaperRebuild.r3_operation_dict(operation))
    core=get(get(c.data, "r3_mechanism", Dict()), "core_periods", c.data["T"])
    row["core_sha256"]=PaperRebuild.r3_core_signature(c, core)
    push!(entries, row)
end
for name in ("single-source", "two-source")
    for label in ("schpd", "case_fixed", "box25", "box50", "box75")
        c, e=source_entry(name*"-"*label)
        for (short, geometry) in
            (("physical", "physical_euclidean"), ("normalized", "normalized_euclidean"))
            add_entry(
                name,
                c,
                e;
                id = name*"-"*label*"-"*short,
                group = "initialization",
                initial_label = label,
                geometry,
            )
        end
    end
    c, e=source_entry(name*"-VF_CT-pg")
    for boundary in ("legacy_tail", "bounded_return_tail", "core_only")
        derived=r3_boundary_case(c, Symbol(boundary))
        op=R3OperationSpec(
            derived;
            mode = :VF_CT,
            tail_return_rule = boundary=="bounded_return_tail" ? :bounded : :fixed_reference,
        )
        initial=[x[1:derived.data["T"]] for x in e["initial_flow"]]
        for (short, geometry) in
            (("physical", "physical_euclidean"), ("normalized", "normalized_euclidean"))
            add_entry(
                name,
                derived,
                e;
                id = name*"-"*boundary*"-"*short,
                group = "boundary",
                initial_label = "historical-VF_CT",
                geometry,
                boundary,
                operation = op,
                initial,
            )
        end
        add_entry(
            name,
            derived,
            e;
            id = name*"-"*boundary*"-reference",
            group = "reference",
            initial_label = "none",
            boundary,
            operation = op,
            reference = true,
        )
    end
    c, e=source_entry(name*"-schpd")
    for (tag, displacement) in (("001", 0.01), ("100", 1.0))
        add_entry(
            name,
            c,
            e;
            id = name*"-schpd-step"*tag,
            group = "step",
            initial_label = "schpd",
            displacement,
        )
    end
end
length(entries)==42 || error("设计必须42项")
length(unique(e["id"] for e in entries))==42 || error("重复ID")
study=Dict(
    "schema"=>"r3-baseline-study-inputs-v1",
    "algorithm"=>"r3_paper_structure_v1",
    "origin"=>"synthetic",
    "budget_sec"=>600.0,
    "max_iterations"=>200,
    "prior_manifest"=>priorfile,
    "prior_manifest_sha256"=>bytes2hex(sha256(read(priorfile))),
    "entries"=>entries,
)
write_once("configs/r3/baseline-study.toml", encoded(study))
println("Frozen 36 baseline + 6 independent references; no optimization performed.")
