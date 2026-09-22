include("r3_setup.jl")
using Clarabel

# 先按固定规则推导稳态与尾段；不读取优化收益来调整输入。
function mechanism_case(name)
    original=load_r2_case(joinpath("configs", "r2", name*".toml"))
    d=deepcopy(original.data)
    h=d["heat"]
    pipes=h["pipes"]
    nodes=h["nodes"]
    all(p["from"]<p["to"] for p in pipes) || error("本构造器仅支持已冻结的顺序树拓扑")
    E, K=length(pipes), length(nodes)
    m=[first(p["fixed_flow"]) for p in pipes]
    ports=PaperRebuild.r2_fixed_port_flows(d, repeat(reshape(m, :, 1), 1, 4))[:, 1]
    A=first(d["ambient_K"])
    dt=3600d["dt_h"]
    decay=zeros(E)
    cover=zeros(Int, E)
    for (p, e) in enumerate(pipes)
        mass=h["rho_kg_m3"]*e["area_m2"]*e["length_m"]
        cover[p]=ceil(Int, mass/(dt*e["flow_min"]))+1
        decay[p]=r3_transport_jacobian(
            fill(m[p], cover[p]+1),
            mass,
            dt;
            loss_rate = e["epsilon_W_mK"]/(h["cp_J_kgK"]*h["rho_kg_m3"]*e["area_m2"]),
        ).decay
    end
    Sin, Sout, Rin, Rout=zeros(E), zeros(E), zeros(E), zeros(E)
    Smix, Rmix=zeros(K), zeros(K)
    for j in 1:K
        incoming=findall(p->p["to"]==j, pipes)
        flow=sum(m[p] for p in incoming; init = 0.0)+(nodes[j]["role"]=="source" ? ports[j] : 0)
        numerator=sum(m[p]*Sout[p] for p in incoming; init = 0.0) +
                  (nodes[j]["role"]=="source" ? ports[j]*h["S_reference_K"] : 0)
        Smix[j]=numerator/flow
        for p in findall(p->p["from"]==j, pipes)
            Sin[p]=Smix[j]
            Sout[p]=A+(Sin[p]-A)*decay[p]
        end
    end
    for j in K:-1:1
        incoming=findall(p->p["from"]==j, pipes)
        flow=sum(m[p] for p in incoming; init = 0.0)+(nodes[j]["role"]=="load" ? ports[j] : 0)
        numerator=sum(m[p]*Rout[p] for p in incoming; init = 0.0) +
                  (nodes[j]["role"]=="load" ? ports[j]*nodes[j]["return_K"] : 0)
        Rmix[j]=numerator/flow
        for p in findall(p->p["to"]==j, pipes)
            Rin[p]=Rmix[j]
            Rout[p]=A+(Rin[p]-A)*decay[p]
        end
    end
    H=zeros(K)
    for j in 1:K
        n=nodes[j]
        S=n["role"]=="source" ? h["S_reference_K"] : Smix[j]
        R=n["role"]=="load" ? n["return_K"] : Rmix[j]
        H[j]=h["cp_J_kgK"]/1e6*ports[j]*(S-R)
        if n["role"]=="source"
            capacity=sum(g["P_max"]*g["heat_ratio"] for g in d["devices"] if g["heat_node"]==j)
            0<=H[j]<=capacity || error("冻结参考工况设备容量不足")
        end
        h["S_bounds_K"][1]<=S<=h["S_bounds_K"][2] || error("参考供温越界")
        h["R_bounds_K"][1]<=R<=h["R_bounds_K"][2] || error("参考回温越界")
    end
    pathcover=zeros(Int, K)
    for j in 1:K, p in findall(p->p["from"]==j, pipes)
        pathcover[pipes[p]["to"]]=max(pathcover[pipes[p]["to"]], pathcover[j]+cover[p])
    end
    tail=2maximum(pathcover)+2
    T=4+tail
    peak=maximum(sum(n["P_MW"][t] for n in d["electric"]["nodes"]) for t in 1:4) +
         0.8sum(g["P_max"] for g in d["devices"] if g["kind"]=="EB")
    for g in d["devices"]
        if g["kind"]=="PV"
            g["P_max"]=peak
            g["availability"]=vcat(peak .* [0, 0.6, 1, 0.2], zeros(tail))
        else
            append!(g["availability"], fill(last(g["availability"]), tail))
        end
    end
    for n in d["electric"]["nodes"], key in ("P_MW", "Q_Mvar")
        append!(n[key], fill(first(n[key]), tail))
    end
    for (j, n) in enumerate(nodes)
        append!(n["H_MW"], fill(n["role"]=="load" ? H[j] : 0.0, tail))
    end
    for (p, e) in enumerate(pipes)
        e["fixed_flow"]=fill(m[p], T)
        e["flow_history"]=fill(m[p], max(4, cover[p]+1))
        e["S_history_K"]=fill(Sin[p], length(e["flow_history"]))
        e["R_history_K"]=fill(Rin[p], length(e["flow_history"]))
    end
    append!(d["grid_price"], fill(last(d["grid_price"]), tail))
    append!(d["ambient_K"], fill(A, tail))
    d["T"]=T
    d["id"]=name*"-four-modes-v1"
    d["description"]="合成四模式机制案例：稳态历史、有界负荷回水、共同恢复尾段；不是论文原始输入。"
    d["r3_mechanism"]=Dict(
        "schema"=>"r3-mechanism-v1",
        "core_periods"=>4,
        "tail_periods"=>tail,
        "parent_sha256"=>original.sha256,
        "pv_peak_MW"=>peak,
        "pv_profile"=>[0.0, 0.6, 1.0, 0.2],
        "pipe_cover_steps"=>cover,
        "longest_path_cover"=>maximum(pathcover),
        "steady_heat_MW"=>H,
        "S_steady_out_K"=>Sout,
        "R_steady_out_K"=>Rout,
    )
    PaperRebuild.validate_r2_input(d)
    return d
end

for name in ("single-source", "two-source")
    data=mechanism_case(name)
    io=IOBuffer()
    TOML.print(io, data; sorted = true)
    bytes=take!(io)
    path=joinpath("configs", "r3", name*"-four-modes-v1.toml")
    if isfile(path)
        read(path)==bytes || error("已冻结文件不同；禁止覆盖")
    else
        write(path, bytes)
    end
    println(path, " SHA256=", bytes2hex(sha256(bytes)), " T=", data["T"])
end
