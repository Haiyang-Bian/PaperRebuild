# 求解前环境失败独立分类；不把未知程序错误伪装成缺许可。
function r2_setup_status(err)
    message = lowercase(sprint(showerror, err))
    occursin("license", message) && return "not_run_license"
    err isa ArgumentError && occursin("package", message) && return "dependency_missing"
    return nothing
end

function r2_setup_failure(c, spec, status; fixed_flows, budget_sec)
    status in ("not_run_license", "dependency_missing") || error("非法启动失败状态")
    return Dict{String,Any}(
        "status"=>status,
        "spec"=>PaperRebuild.r2_spec_dict(spec),
        "input_sha256"=>c.sha256,
        "fixed_flows"=>fixed_flows,
        "budget_sec"=>budget_sec,
        "elapsed_sec"=>0.0,
        "case_origin"=>"synthetic",
        "source_hashes_at_solve"=>PaperRebuild.r2_science_hashes(),
        "paper_match"=>"blocked",
    )
end
