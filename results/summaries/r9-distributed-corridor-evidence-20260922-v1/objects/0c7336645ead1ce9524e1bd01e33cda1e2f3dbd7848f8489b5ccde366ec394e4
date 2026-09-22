"""
    save_r6_dataset(path, protocol, sets, representatives; provenance=Dict())

将R6三分组原始数值分块保存为CSV，附协议、聚类、来源和SHA256；拒绝覆盖已有路径。
每块最多200条完整轨迹，不把小时切成独立样本。不求解模型，也不写任何风险通过结论。
"""
function save_r6_dataset(path, p::R6Protocol, sets, reps; provenance = Dict{String,Any}())
    r6_assert_protocol(p)
    ispath(path) && error("冻结数据目录已存在；必须使用新路径")
    Set(keys(sets)) == Set(R6_SPLITS) || error("三个数据分组不完整")
    for split in R6_SPLITS
        s = sets[split]
        r6_assert_set(s)
        s.split == split && s.protocol_sha256 == p.sha256 || error("分组身份不符")
        size(s.values) == (2, p.data["T"], p.data["samples"][split]) || error("数据规模不符")
    end
    reps["converged"] && reps == r6_fit_representatives(sets["train"], p) || error("聚类未通过重算")
    mkpath(path)
    files, groups = Dict{String,Any}(), Dict{String,Any}()
    for split in R6_SPLITS
        s, names = sets[split], String[]
        for start in 1:200:length(s.ids)
            name = split * "-" * lpad(div(start - 1, 200) + 1, 3, '0') * ".csv"
            rows = [
                (
                    id = s.ids[i],
                    t = t,
                    pv_fraction = s.values[1, t, i],
                    activation_signed = s.values[2, t, i],
                ) for i in start:min(start+199, length(s.ids)) for t in axes(s.values, 2)
            ]
            CSV.write(joinpath(path, name), rows; newline = '\n')
            files[name] = bytes2hex(sha256(read(joinpath(path, name))))
            push!(names, name)
        end
        groups[split] = Dict("files" => names, "sha256" => s.sha256, "count" => length(s.ids))
    end
    write(joinpath(path, "representatives.toml"), r5_market_text(reps))
    files["representatives.toml"] = bytes2hex(sha256(read(joinpath(path, "representatives.toml"))))
    manifest = Dict{String,Any}(
        "schema" => "r6-frozen-data-v1",
        "protocol" => p.data,
        "protocol_sha256" => p.sha256,
        "groups" => groups,
        "files" => files,
        "julia_version" => string(VERSION),
        "provenance" => provenance,
        "status" => "input_frozen_no_method_results",
    )
    text = r5_market_text(manifest)
    write(joinpath(path, "manifest.toml"), text)
    write(joinpath(path, "manifest.sha256"), bytes2hex(sha256(text)) * "\n")
    manifest
end

"""
    read_r6_dataset(path)

只读重建并核验R6协议、逐块哈希、时序完整性、全部原值及训练聚类；不重新抽样或求解。
冻结数值是权威记录，种子不是替代品；哈希检验用于发现意外篡改，不代替可信版本控制。
"""
function read_r6_dataset(path)
    text = read(joinpath(path, "manifest.toml"), String)
    bytes2hex(sha256(text)) == strip(read(joinpath(path, "manifest.sha256"), String)) ||
        error("数据清单哈希改变")
    m = TOML.parse(text)
    m["schema"] == "r6-frozen-data-v1" && m["status"] == "input_frozen_no_method_results" ||
        error("冻结版本错误")
    p = R6Protocol(m["protocol"])
    p.sha256 == m["protocol_sha256"] || error("协议哈希改变")
    Set(keys(m["groups"])) == Set(R6_SPLITS) || error("分组缺失")
    expected = Set(vcat([m["groups"][s]["files"] for s in R6_SPLITS]..., ["representatives.toml"]))
    Set(keys(m["files"])) == expected || error("数据文件清单不符")
    for (name, hash) in m["files"]
        (
            name == "representatives.toml" ||
            occursin(r"^(train|validation|test)-[0-9]{3}\.csv$", name)
        ) || error("非可移植数据路径")
        bytes2hex(sha256(read(joinpath(path, name)))) == hash || error("数据文件改变: $name")
    end
    sets = Dict{String,R6TrajectorySet}()
    for split in R6_SPLITS
        group = m["groups"][split]
        T, n = p.data["T"], p.data["samples"][split]
        group["count"] == n || error("清单样本数不符")
        values, ids, row_index = zeros(2, T, n), String[], 0
        for name in group["files"]
            startswith(name, split * "-") || error("跨分组数据文件")
            f = CSV.File(
                joinpath(path, name);
                types = Dict(
                    :id => String,
                    :t => Int,
                    :pv_fraction => Float64,
                    :activation_signed => Float64,
                ),
                strict = true,
            )
            Set(propertynames(f)) == Set((:id, :t, :pv_fraction, :activation_signed)) ||
                error("CSV列不符")
            for row in f
                i, t = div(row_index, T) + 1, mod(row_index, T) + 1
                i <= n && row.t == t || error("轨迹时段缺失或顺序改变")
                t == 1 && push!(ids, row.id)
                ids[i] == row.id || error("同日轨迹被拆分或顺序改变")
                values[:, t, i] .= (row.pv_fraction, row.activation_signed)
                row_index += 1
            end
        end
        row_index == T * n || error("完整轨迹数不足")
        s = R6TrajectorySet(split, ids, values, p.sha256)
        s.sha256 == group["sha256"] || error("重建轨迹哈希不符")
        sets[split] = s
    end
    reps = TOML.parsefile(joinpath(path, "representatives.toml"))
    reps == r6_fit_representatives(sets["train"], p) && reps["converged"] || error("聚类证据改变")
    (protocol = p, sets = sets, representatives = reps, manifest = m)
end
