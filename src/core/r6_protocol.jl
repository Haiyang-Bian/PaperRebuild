const R6_METHODS = ["D", "SP", "RO", "DRO", "CCP", "DRJCC"]
const R6_SPLITS = ("train", "validation", "test")

"""
    R6Protocol(data)

R6完整日轨迹、训练/验证/测试和统计规则，项目版本r6-protocol-v1。
当前只支持明确标注的合成PV与备用调用轨迹；每条24小时，轨迹内允许时间相关。
生成规则、分组种子、聚类和风险阈值显式输入。读取/构造不抽样、不求解、不写文件。
来源核查见第5.6节；数据隔离对应项目式R6-S1，测试R6-SPLIT。
"""
struct R6Protocol
    data::Dict{String,Any}
    sha256::String
end

function R6Protocol(input::AbstractDict)
    d = deepcopy(Dict{String,Any}(string(k) => v for (k, v) in input))
    d["schema"] == "r6-protocol-v1" || error("R6协议版本错误")
    d["origin"] == "synthetic" || error("本生成器不是作者或公开实测数据")
    d["sample_unit"] == "complete_day" || error("独立单位必须为完整日轨迹")
    d["recourse_information"] == "complete_trajectory" || error("当前补救不是在线控制")
    d["T"] isa Integer && d["T"] > 0 || error("时段数须为正整数")
    isfinite(d["dt_h"]) && d["dt_h"] > 0 && abs(d["T"] * d["dt_h"] - 24) <= 1e-12 ||
        error("一条轨迹必须覆盖24小时")
    d["methods"] == R6_METHODS || error("六类比较方法须完整且顺序固定")
    d["generator"]["version"] == "r6_correlated_pv_call_v1" || error("未知生成器")
    for k in ("weather_ar", "activation_ar")
        x = d["generator"][k]
        isfinite(x) && 0 <= x < 1 || error("AR系数须在[0,1)")
    end
    for k in ("cloud_intercept", "cloud_daily_scale", "cloud_hourly_scale", "call_scale")
        x = d["generator"][k]
        x isa Real && isfinite(x) || error("生成参数必须有限")
    end
    all(k -> d["generator"][k] >= 0, ("cloud_daily_scale", "cloud_hourly_scale", "call_scale")) ||
        error("随机幅度不得为负")
    clear = Float64.(d["generator"]["clear_sky_fraction"])
    length(clear) == d["T"] && all(x -> isfinite(x) && 0 <= x <= 1, clear) ||
        error("晴空出力比例维度或边界错误")
    d["generator"]["clear_sky_fraction"] = clear
    for split in R6_SPLITS
        n = d["samples"][split]
        n isa Integer && n > 0 || error("样本数须为正整数")
        s = d["seeds"][split]
        s isa Integer && 0 <= s <= typemax(Int) || error("种子须为非负Int")
    end
    length(unique(d["seeds"][s] for s in R6_SPLITS)) == 3 || error("三个数据分组不可共享种子")
    d["samples"]["test"] >= 1000 || error("正式R6协议至少1000条独立测试日")
    c = d["clustering"]
    c["algorithm"] == "lloyd_farthest_first_observed_representative_v1" || error("聚类版本错误")
    c["count"] isa Integer && 1 <= c["count"] <= d["samples"]["train"] || error("聚类数错误")
    c["max_iterations"] isa Integer && c["max_iterations"] > 0 || error("聚类预算错误")
    isfinite(c["tolerance"]) && c["tolerance"] >= 0 || error("聚类容差错误")
    c["distance"] == "rms_pv_and_signed_call_half" || error("距离尺度必须预声明")
    s = d["statistics"]
    isfinite(s["epsilon"]) && 0 <= s["epsilon"] <= 1 || error("风险上限错误")
    s["confidence"] == 0.95 || error("A5采用单侧95%界")
    s["primary_claim"] == "DRJCC_joint_comfort" || error("正式主要检验须预声明")
    s["unknown_rule"] == "keep_denominator_upper_counts_all" || error("未知轨迹不可删除")
    s["bootstrap_replicates"] isa Integer && s["bootstrap_replicates"] >= 1000 ||
        error("自助次数须显式且至少1000")
    s["bootstrap_seed"] isa Integer && s["bootstrap_seed"] >= 0 || error("自助种子错误")
    R6Protocol(d, bytes2hex(sha256(r5_market_text(d))))
end

"""
    load_r6_protocol(path)

读取并验证R6协议TOML，保留规范化内容哈希；不访问测试数据、不运行优化。
"""
load_r6_protocol(path::AbstractString) = R6Protocol(TOML.parsefile(path))

function r6_assert_protocol(p)
    bytes2hex(sha256(r5_market_text(p.data))) == p.sha256 || error("R6协议被修改")
end

"""
    R6TrajectorySet(split, ids, values, protocol_sha256)

完整轨迹数据；values维度为通道×时段×轨迹，通道固定为PV额定出力比例、正上调的调用比例。
PV在[0,1]、调用在[-1,1]，均无量纲；对应R6-S2。相同数值可自然重复，身份ID不能重复。
独立采样由生成协议给出，数据格式检查本身不能证明真实观测之间独立。
"""
struct R6TrajectorySet
    split::String
    ids::Vector{String}
    values::Array{Float64,3}
    protocol_sha256::String
    sha256::String
end

function r6_trajectory_digest(split, ids, values, protocol_hash)
    bytes2hex(
        sha256(
            r5_market_text(
                Dict(
                    "split" => split,
                    "ids" => ids,
                    "shape" => collect(size(values)),
                    "values" => vec(values),
                    "protocol_sha256" => protocol_hash,
                ),
            ),
        ),
    )
end

function R6TrajectorySet(split::AbstractString, ids, values::AbstractArray{<:Real,3}, protocol_hash)
    split in R6_SPLITS || error("未知数据分组")
    names = String.(ids)
    size(values, 1) == 2 && size(values, 2) > 0 && size(values, 3) == length(names) > 0 ||
        error("轨迹数据维度错误")
    length(unique(names)) == length(names) || error("轨迹ID重复")
    all(x -> occursin(Regex("^" * split * "_[0-9]+\$"), x), names) || error("轨迹ID分组不一致")
    occursin(r"^[0-9a-f]{64}$", protocol_hash) || error("协议哈希格式错误")
    v = Float64.(values)
    all(isfinite, v) && all(x -> 0 <= x <= 1, v[1, :, :]) && all(x -> -1 <= x <= 1, v[2, :, :]) ||
        error("轨迹非有限或超出物理比例范围")
    R6TrajectorySet(
        String(split),
        names,
        v,
        String(protocol_hash),
        r6_trajectory_digest(split, names, v, protocol_hash),
    )
end

function r6_assert_set(s)
    r6_trajectory_digest(s.split, s.ids, s.values, s.protocol_sha256) == s.sha256 ||
        error("轨迹原值被修改")
end
