# 第3章初步检查，不构建/求解论文优化模型。不把结构通过记成科学复现完成。
include("ch03_data.jl")
using .Ch03Data, CSV, Dates, SHA, TOML, UUIDs

root = Ch03Data.ROOT
run_id = "ch03-data-" * Dates.format(now(UTC), "yyyymmddTHHMMSS") * "-" * first(string(uuid4()), 8)
dir = joinpath(root, "data", "processed", "ch03", run_id)
mkpath(dir)
report = Dict{String,Any}(
    "run_id" => run_id,
    "created_utc" => string(now(UTC)),
    "status" => "running",
    "ready_for_thesis_dispatch" => false,
    "julia" => string(VERSION),
    "scope" => "source bytes, numeric schemas, topology, dimensions and cross-source comparison only",
)
try
    mp = Ch03Data.read_matpower()
    author = Ch03Data.read_barry("qin2021-author-workbook")
    derivative = Ch03Data.read_barry("figshare-14813121-v3")
    thesis_path = joinpath(root, "docs", "reading", "ch03", "thesis-parameters.toml")
    thesis = TOML.parsefile(thesis_path)
    report["thesis"] = Ch03Data.check_thesis(thesis)
    report["matpower"] = mp.metrics
    report["author"] = author.metrics
    report["figshare"] = derivative.metrics
    report["comparison"] = Dict(
        "P_series_max_difference_MW" => maximum(abs.(author.P - derivative.P)),
        "H_series_max_difference_MW" => maximum(abs.(author.H - derivative.H)),
        "pipe_geometry_max_difference" =>
            maximum(abs.(author.pipe[:, 1:6] - derivative.pipe[:, 1:6])),
        "changed_pipe_lower_bounds" => count(!=(0), author.pipe[:, 7] - derivative.pipe[:, 7]),
        "static_PQ_author_equals_1000_figshare" =>
            isapprox(author.bus[:, 3:4], 1000 .* derivative.bus[:, 3:4]),
        "author_static_bus_equals_matpower" => isapprox(author.bus, mp.bus),
        "author_branch_equals_matpower" => isapprox(author.branch, mp.branch),
    )
    differences = NamedTuple[]
    for index in findall(author.H .!= derivative.H)
        t, n = Tuple(index)
        col = Ch03Data.XLSX.encode_column_number(n)
        push!(
            differences,
            (
                kind = "heat_load",
                author_cell = "heat!$(col)$(126+t)",
                figshare_cell = "Modified Barry Island HE-IES!$(col)$(283+t)",
                author_value = author.H[index],
                figshare_value = derivative.H[index],
                unit = "MW",
            ),
        )
    end
    for i in findall(author.pipe[:, 7] .!= derivative.pipe[:, 7])
        push!(
            differences,
            (
                kind = "pipe_flow_min",
                author_cell = "heat!H$(4+i)",
                figshare_cell = "Modified Barry Island HE-IES!H$(197+i)",
                author_value = author.pipe[i, 7],
                figshare_value = derivative.pipe[i, 7],
                unit = "raw; pending",
            ),
        )
    end
    report["comparison"]["heat_load_changed_cells"] =
        count(row -> row.kind == "heat_load", differences)
    report["comparison"]["author_vs_matpower_bus_changed_cells"] = count(!=(0), author.bus - mp.bus)
    CSV.write(joinpath(dir, "source-differences.csv"), differences)
    inputs = [mp.source, author.source, derivative.source]
    report["sources"] = [
        Dict(
            "id" => s["id"],
            "sha256" => s["sha256"],
            "url" => s["url"],
            "license" => s["license"],
        ) for s in inputs
    ]
    report["input_sha256"] = Dict("thesis_parameters" => bytes2hex(sha256(read(thesis_path))))
    report["code_sha256"] = Dict(
        path => bytes2hex(sha256(read(joinpath(root, path)))) for path in
        ("scripts/ch03_data.jl", "scripts/validate_ch03_data.jl", "tools/data/Manifest.toml")
    )
    report["source_ranges"] = Dict("author" => author.ranges, "figshare" => derivative.ranges)
    report["issues"] = [
        Dict(
            "id" => "D01",
            "status" => "blocked",
            "detail" => "Q01：论文正文3台CHP，表3-3只有2台；保留矛盾",
        ),
        Dict(
            "id" => "D02",
            "status" => "blocked",
            "detail" => "作者完整输入包缺口：逐节点P/Q/H/PV时序、支路容量、管道修改映射、初始温度和流量历史",
        ),
        Dict(
            "id" => "D03",
            "status" => "difference",
            "detail" => "公开Barry为33热节点/33管段含1环；论文图3-2为32节点/31条图示连接，无编号映射",
        ),
        Dict(
            "id" => "D04",
            "status" => "blocked",
            "detail" => "Figshare B8:N40静态Pd/Qd比作者小1000倍但A7仍标kW/kvar；不自动认定为MW",
        ),
        Dict(
            "id" => "D05",
            "status" => "blocked",
            "detail" => "96个MW负荷样本；时间间隔/时间戳与温度、流量和传热系数单位尚待关联论文确认；不积分MWh",
        ),
        Dict(
            "id" => "D06",
            "status" => "difference",
            "detail" => "MATPOWER/公开测试床12.66kV不同于论文10kV；不直接改电压或按峰值缩放负荷",
        ),
        Dict(
            "id" => "D07",
            "status" => "unavailable",
            "detail" => "文献[25]PDF的Julia下载收到HTTP403，网页可读不等于本地原件获取成功",
        ),
        Dict(
            "id" => "D08",
            "status" => "blocked",
            "detail" => "公开branch表rateA=0表示未给容量；heat压力±Inf表示未设界，不是有效额定值",
        ),
        Dict(
            "id" => "D09",
            "status" => "difference",
            "detail" => "公开管长求和是表中单组管段口径；论文12.58km的供回统计口径未核，不能直接据此缩放",
        ),
    ]
    # 转换明确单位，其余原样保留，并在列名中标raw。
    CSV.write(
        joinpath(dir, "matpower-buses.csv"),
        [
            (
                node = Int(mp.bus[i, 1]),
                P_MW = mp.bus_MW[i, 3],
                Q_Mvar = mp.bus_MW[i, 4],
                base_kV = mp.bus[i, 10],
            ) for i in axes(mp.bus, 1)
        ],
    )
    CSV.write(
        joinpath(dir, "matpower-branches.csv"),
        [
            (
                branch = i,
                from = Int(mp.branch[i, 1]),
                to = Int(mp.branch[i, 2]),
                r_ohm = mp.branch[i, 3],
                x_ohm = mp.branch[i, 4],
                r_pu = mp.branch_pu[i, 3],
                x_pu = mp.branch_pu[i, 4],
                active = Int(mp.branch[i, 11]),
                rateA_MVA = mp.branch[i, 6] == 0 ? missing : mp.branch[i, 6],
            ) for i in axes(mp.branch, 1)
        ],
    )
    totals = NamedTuple[]
    for case in (author, derivative)
        folder = joinpath(dir, case.id)
        mkpath(folder)
        CSV.write(
            joinpath(folder, "pipes.csv"),
            [
                (
                    pipe = i,
                    from = Int(case.pipe[i, 1]),
                    to = Int(case.pipe[i, 2]),
                    length_m = case.pipe[i, 3],
                    diameter_m = case.pipe[i, 4],
                    roughness_raw = case.pipe[i, 5],
                    conductivity_raw = case.pipe[i, 6],
                    flow_min_raw = case.pipe[i, 7],
                    flow_max_raw = case.pipe[i, 8],
                ) for i in axes(case.pipe, 1)
            ],
        )
        CSV.write(
            joinpath(folder, "loads.csv"),
            [
                (sample = t, node = n, P_MW = case.P[t, n], H_MW = case.H[t, n]) for
                t in axes(case.P, 1) for n in axes(case.P, 2)
            ],
        )
        for t in eachindex(case.P_total)
            push!(
                totals,
                (
                    source_id = case.id,
                    sample = t,
                    P_MW = case.P_total[t],
                    H_MW = case.H_total[t],
                    ambient_raw = case.ambient[t],
                ),
            )
        end
    end
    CSV.write(joinpath(dir, "aggregate-loads.csv"), totals)
    report["output_sha256"] = Dict(
        replace(relpath(joinpath(folder, file), dir), '\\' => '/') =>
            bytes2hex(sha256(read(joinpath(folder, file)))) for
        (folder, _, files) in walkdir(dir) for file in files
    )
    report["status"] = "preliminary_checks_passed_with_open_issues"
catch exception
    report["status"] = "failed"
    report["error"] = sprint(showerror, exception)
    rethrow()
finally
    open(joinpath(dir, "validation.toml"), "w") do io
        TOML.print(io, report; sorted = true)
    end
    println("Saved: ", replace(relpath(dir, root), '\\' => '/'))
end
println("MATPOWER: ", report["matpower"])
println("Author heat: ", report["author"]["heat"])
println("Cross-source: ", report["comparison"])
println("Preliminary checks passed; thesis dispatch readiness = false")
