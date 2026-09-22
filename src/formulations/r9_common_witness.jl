function r9_common_identity(c)
    d=c.data["commitment"]
    allowed=["devices.available_MW", "realtime.alpha_up", "realtime.alpha_down"]
    signatures=[r5_commitment_signature(s["case"], allowed) for s in d["scenarios"]]
    all(==(first(signatures)), signatures) || error("共同见证要求相同物理、历史和价格")
    r5_market_digest(
        Dict("physics"=>first(signatures), "bounds"=>d["bounds"], "day_ahead"=>d["day_ahead"]),
    )
end

"""
    build_r9_common_witness(case; optimizer=nothing)

构建硬舒适、零备用及实际PV出力为零的单日共同调度，不求解、不写文件。
原PV可用量、设备、价格及历史保留；仅在情景间差异为PV可用量/备用调用时适用。
若找到候选，仍须逐一回代原情景；受限最优值仅能给原问题可行上界。
项目式R9-CW1；不复现作者的分解算法，也不保证这种保守调度存在。
"""
function build_r9_common_witness(c::R5RiskCase; optimizer = nothing)
    r5_risk_assert_case(c)
    identity=r9_common_identity(c)
    sc=c.data["commitment"]["scenarios"]
    d=deepcopy(c.data["commitment"])
    d["name"]*="-common-zero-PV-reserve"
    d["scenarios"]=[deepcopy(first(sc))]
    only(d["scenarios"])["probability"]=1.0
    one=R5CommitmentCase(d)
    b=build_r5_commitment(one; optimizer)
    m=b.model
    T=first(sc)["case"]["T"]
    extra=Dict{String,Any}()
    for key in ("R_up_MW", "R_down_MW"), t in 1:T
        extra["$key/$t"]=@constraint(m, b.first_stage[key][t]==0)
    end
    id=first(sc)["id"]
    for (j, a) in enumerate(first(sc)["case"]["devices"])
        a["kind"]=="PV" || continue
        for t in 1:T
            # 选择全部弃光，不降低原输入的可用量；原上下界继续保留。
            extra["PV/$j/$t"]=@constraint(m, b.variables[id]["P_DER/$j/$t"]==0)
        end
    end
    (; model = m, base = b, one, extra, parent_sha256 = c.sha256, common_identity = identity)
end
