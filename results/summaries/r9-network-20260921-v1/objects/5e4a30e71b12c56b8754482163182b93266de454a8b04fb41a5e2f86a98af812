const R5_COMMITMENT_CORE_FILE=@__FILE__
const R5_COMMITMENT_KEYS=("P_DA_MW", "R_up_MW", "R_down_MW")
const R5_COMMITMENT_UNCERTAIN=(
    "ambient_K",
    "electric.P_load_MW",
    "electric.Q_load_Mvar",
    "devices.available_MW",
    "realtime.alpha_up",
    "realtime.alpha_down",
    "realtime.price",
)

"""
    R5CommitmentCase(data)

共同日前购电/上下备用与有限情景实时补救输入，版本r5-commitment-case-v1。
共享设备、网络、初始出力、热历史和外生日前价格；只允许显式声明的未来轨迹不同。
每个情景概率严格为正且总和为1，舒适边界逐情景为硬约束；第二阶段已知完整情景轨迹。
这是第5章固定价格期望费用直接基准，不是市场出清、策略报价、DRO或在线控制。
"""
struct R5CommitmentCase
    data::Dict{String,Any}
    sha256::String
end

function r5_commitment_signature(data, uncertain)
    d=deepcopy(data)
    delete!(d, "name")
    delete!(d, "award") # 模板成交不是共同决策，也不作为初值注入。
    for field in uncertain
        if field=="devices.available_MW"
            for a in d["devices"]
                a["kind"]=="PV"&&delete!(a, "available_MW")
            end
        elseif occursin('.', field)
            parent, child=split(field, '.')
            delete!(d[parent], child)
        else
            delete!(d, field)
        end
    end
    r5_market_text(d)
end

function R5CommitmentCase(input::AbstractDict)
    d=deepcopy(Dict{String,Any}(string(k)=>v for (k, v) in input))
    d["schema"]=="r5-commitment-case-v1"||error("共同承诺输入版本错误")
    d["origin"] in ("synthetic", "public_adapted", "thesis_verified")||error("共同承诺来源缺失")
    !isempty(strip(d["name"]))||error("共同承诺名称为空")
    d["objective"]=="expected_net_cost"&&d["recourse_information"]=="complete_trajectory" &&
    d["comfort"]=="hard_each_scenario"||error("尚未支持该风险或信息结构")
    uncertain=String.(d["uncertain_fields"])
    length(unique(uncertain))==length(uncertain)&&all(x->x in R5_COMMITMENT_UNCERTAIN, uncertain) ||
        error("不支持或重复的不确定字段")
    d["uncertain_fields"]=sort(uncertain)
    scenarios=d["scenarios"]
    !isempty(scenarios)||error("情景不能为空")
    ids=[s["id"] for s in scenarios]
    length(unique(ids))==length(ids)&&all(x->x isa String&&occursin(r"^[A-Za-z0-9_-]+$", x), ids) ||
        error("情景ID重复或不合法")
    all(
        s->s["probability"] isa Real&&isfinite(s["probability"])&&0<s["probability"]<=1,
        scenarios,
    ) || error("情景概率须严格为正；零权重情景不能生成条件对偶")
    abs(sum(s["probability"] for s in scenarios)-1)<=1e-12||error("情景概率未归一；不自动重标定")
    for s in scenarios
        c=R5DispatchCase(s["case"])
        c.data["origin"]==d["origin"]||error("情景来源不一致")
        s["case"]=c.data
        s["case_sha256"]=c.sha256
        s["probability"]=Float64(s["probability"])
    end
    base=first(scenarios)["case"]
    signature=r5_commitment_signature(base, uncertain)
    all(s->r5_commitment_signature(s["case"], uncertain)==signature, scenarios) ||
        error("共同设备/历史或未声明轨迹发生变化")
    T=base["T"]
    Set(keys(d["day_ahead"]))==Set(("energy_price", "up_price", "down_price"))||error(
        "日前价格字段不符",
    )
    for key in ("energy_price", "up_price", "down_price")
        d["day_ahead"][key]=r5_dispatch_vector(d["day_ahead"][key], T, key)
    end
    Set(keys(d["bounds"]))==Set(R5_COMMITMENT_KEYS)||error("共同承诺边界清单不符")
    for key in R5_COMMITMENT_KEYS
        b=d["bounds"][key]
        for side in ("lower", "upper")
            b[side]=r5_dispatch_vector(b[side], T, "$key/$side"; lower = 0)
        end
        all(b["lower"] .<= b["upper"])||error("共同承诺上下界冲突")
    end
    # 参数格式与数值可行性分开；互相矛盾但格式合法的界留给求解器报告不可行。
    R5CommitmentCase(d, bytes2hex(sha256(r5_market_text(d))))
end

"""
    load_r5_commitment_case(path)

读取嵌入全部小型情景、显式概率、共同承诺边界和日前价格的TOML；不抽样、不优化。
规范化输入单独计算哈希，情景模板原成交不作为当前优化量或已认证市场成交。
"""
load_r5_commitment_case(path::AbstractString) = R5CommitmentCase(TOML.parsefile(path))

function r5_commitment_assert_case(c)
    bytes2hex(sha256(r5_market_text(c.data)))==c.sha256||error("共同承诺输入已被修改")
end

function r5_commitment_view(c, scenario, x)
    d=deepcopy(scenario["case"])
    # 数值验算视图保留求解器原值，不裁剪小负数；合法性由共同承诺A1单独检查。
    # 结构、历史及全部物理参数已在输入构造时通过R5DispatchCase核验。
    a=Dict{String,Any}(k=>Float64.(x[k]) for k in R5_COMMITMENT_KEYS)
    merge!(a, deepcopy(c.data["day_ahead"]))
    a["origin"]="synthetic"
    a["commitment_source"]="optimized_fixed_price_not_market_cleared"
    d["award"]=a
    R5DispatchCase(d, bytes2hex(sha256(r5_market_text(d))))
end

function r5_commitment_first_rows(c)
    d=c.data
    e=first(d["scenarios"])["case"]["electric"]
    T=first(d["scenarios"])["case"]["T"]
    rows=Dict{String,Any}()
    for key in R5_COMMITMENT_KEYS, t in 1:T, side in ("lower", "upper")
        rows["$key/$t/$side"]=(
            coefficients = Dict("$key/$t"=>1.0),
            sense = side=="lower" ? :ge : :le,
            rhs = d["bounds"][key][side][t],
        )
    end
    for t in 1:T
        rows["PCC-up/$t"]=(
            coefficients = Dict("P_DA_MW/$t"=>1.0, "R_up_MW/$t"=>-1.0),
            sense = :ge,
            rhs = e["pcc_min_MW"],
        )
        rows["PCC-down/$t"]=(
            coefficients = Dict("P_DA_MW/$t"=>1.0, "R_down_MW/$t"=>1.0),
            sense = :le,
            rhs = e["pcc_max_MW"],
        )
    end
    rows
end

function r5_commitment_day_cost(c, x)
    d=first(c.data["scenarios"])["case"]
    p=c.data["day_ahead"]
    d["dt_h"]*sum(
        p["energy_price"] .* x["P_DA_MW"]-p["up_price"] .* x["R_up_MW"]-p["down_price"] .*
                                                                        x["R_down_MW"],
    )
end
