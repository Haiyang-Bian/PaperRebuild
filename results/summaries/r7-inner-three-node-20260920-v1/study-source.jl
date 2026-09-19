push!(LOAD_PATH,normpath(joinpath(@__DIR__,"..")))
using PaperRebuild,JuMP,HiGHS,TOML,SHA,Test
!isempty(ARGS) && ARGS[1]=="run" && (@eval import Gurobi)

function read_frozen_inner(path)
    m=Module(gensym(:FrozenInnerStudy))
    Base.include(m,abspath(joinpath(path,"code/replay.jl")))
    Base.invokelatest(getfield,m,:x)
end

function check_reference(c,reference;science=PaperRebuild)
    faults=science.r7_faults(c)
    length(reference["faults"])==length(faults) || error("故障参考缺项")
    lb,ub=0.0,0.0
    for (gamma,entry) in zip(faults,reference["faults"])
        entry["fault"]==gamma || error("故障顺序错误")
        audit=entry["milp"]
        q=science.validate_r7_recovery(c,audit)
        isequal(q,audit["validation"]) || error("MILP参考数值改变")
        enumeration=entry["topologies"]
        L=length(gamma)
        enumeration["all_topologies_scanned"] && enumeration["topologies_scanned"]==2^L || error("拓扑未完整枚举")
        expected=[[(mask>>(i-1))&1 for i in 1:L] for mask in 0:(2^L-1)]
        filter!(z->science.r7_topology_roots(c,gamma,z)!==nothing,expected)
        length(enumeration["runs"])==length(expected) || error("允许拓扑缺项")
        elb,eub=Inf,Inf
        for (z,run) in zip(expected,enumeration["runs"])
            run["fixed_z"]==z && run["fault"]==gamma || error("拓扑LP身份错误")
            v=science.validate_r7_recovery(c,run)
            isequal(v,run["validation"]) || error("LP参考原值改变")
            low=run["status"]=="infeasible_certified" ? Inf : get(run,"lower_bound_MWh",0.0)
            high=v["model_pass"] ? v["loss_MWh"] : Inf
            elb=min(elb,low); eub=min(eub,high)
        end
        elb==enumeration["lower_bound_MWh"] && eub==enumeration["upper_bound_MWh"] || error("拓扑参考界错误")
        mlb=audit["status"]=="infeasible_certified" ? Inf : get(audit,"lower_bound_MWh",0.0)
        mub=q["model_pass"] ? q["loss_MWh"] : Inf
        if isfinite(eub)
            -1e-6<=(eub-elb)/max(1,eub)<=1e-4 || error("枚举未认证")
            q["model_pass"] && abs(mub-eub)<=1e-6*(1+max(1,eub)) || error("MILP/LP枚举不同")
            -1e-6<=(mub-mlb)/max(1,mub)<=1e-4 || error("MILP参考未认证")
        else
            elb==Inf && audit["status"]=="infeasible_certified" || error("不可行参考未闭合")
        end
        lb=max(lb,elb);ub=max(ub,eub)
    end
    (;lower=lb,upper=ub)
end

function run_study(out)
    ispath(out) && error("不覆盖已有研究批次")
    root=normpath(joinpath(@__DIR__,".."))
    freeze=TOML.parsefile(joinpath(root,"configs/r7/inner-freeze.toml"))
    for (p,h) in freeze["files"]
        bytes2hex(sha256(read(joinpath(root,p))))==h || error("冻结输入改变")
    end
    run_loaded(out,freeze,root,Gurobi)
end

function run_loaded(out,freeze,root,G)
    env=G.Env(Dict{String,Any}("OutputFlag"=>0))
    opt=optimizer_with_attributes(()->G.Optimizer(env),"Threads"=>1,"Seed"=>0,
        "FeasibilityTol"=>1e-9,"OptimalityTol"=>1e-9,"IntFeasTol"=>1e-9,
        "MIPGap"=>1e-9,"DualReductions"=>0)
    reference_opt=optimizer_with_attributes(HiGHS.Optimizer,"threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,"dual_feasibility_tolerance"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,"mip_rel_gap"=>1e-9)
    mkpath(out);write(joinpath(out,"rule.toml"),PaperRebuild.r7_text(freeze))
    cp(@__FILE__,joinpath(out,"study-source.jl"))
    rows=String["case,expected_MWh,inner_lower_MWh,inner_upper_MWh,inner_status,iterations,reference_lower_MWh,reference_upper_MWh"]
    for p in sort(collect(keys(freeze["files"])))
        c=load_r7_recovery_case(joinpath(root,p));name=splitext(basename(p))[1]
        r=solve_r7_adversary(c;optimizer=opt,budget_sec=freeze["budget_per_method_sec"])
        save_r7_adversary(c,r,joinpath(out,name,"adversary"))
        stop=time()+freeze["budget_per_method_sec"]
        reference=Dict("faults"=>Any[])
        for gamma in r7_faults(c)
            milp=solve_r7_recovery(c,gamma;optimizer=reference_opt,budget_sec=max(0,stop-time()),deadline=stop)
            modes=enumerate_r7_recovery(c,gamma;optimizer=reference_opt,budget_sec=max(0,stop-time()))
            push!(reference["faults"],Dict("fault"=>gamma,"milp"=>milp,"topologies"=>modes))
        end
        write(joinpath(out,name,"reference.toml"),PaperRebuild.r7_text(reference))
        q=check_reference(c,reference);v=r["validation"];expected=freeze["expected"][name]
        push!(rows,join([name,expected,v["lower_bound_MWh"],v["upper_bound_MWh"],r["status"],length(r["iterations"]),q.lower,q.upper],","))
        write(joinpath(out,"summary.csv"),join(rows,"\n")*"\n")
        @testset "R7-$name-frozen-comparison" begin
            @test isequal(q.lower,expected) || isapprox(q.lower,expected;atol=1e-7)
            @test isequal(q.upper,expected) || isapprox(q.upper,expected;atol=1e-7)
            @test isequal(v["lower_bound_MWh"],expected) || isapprox(v["lower_bound_MWh"],expected;atol=1e-7)
            @test isequal(v["upper_bound_MWh"],expected) || isapprox(v["upper_bound_MWh"],expected;atol=1e-7)
        end
    end
    files=Dict(replace(relpath(joinpath(p,f),out),'\\'=>'/')=>bytes2hex(sha256(read(joinpath(p,f))))
        for (p,_,fs) in walkdir(out) for f in fs)
    write(joinpath(out,"files.toml"),PaperRebuild.r7_text(Dict("files"=>files)))
end

function check_study(out)
    files=TOML.parsefile(joinpath(out,"files.toml"))["files"]
    actual=Set(replace(relpath(joinpath(p,f),out),'\\'=>'/') for (p,_,fs) in walkdir(out) for f in fs)
    actual==union(Set(keys(files)),Set(["files.toml"])) || error("研究文件清单不一致")
    for (p,h) in files
        !isabspath(p) && !occursin(':',p) && !occursin('\\',p) && all(x->!(x in ("",".","..")),split(p,'/')) || error("研究路径错误")
        bytes2hex(sha256(read(joinpath(out,split(p,'/')...))))==h || error("研究原值被修改")
    end
    freeze=TOML.parsefile(joinpath(out,"rule.toml"))
    for p in sort(collect(keys(freeze["files"])))
        name=splitext(basename(p))[1]
        x=read_frozen_inner(joinpath(out,name,"adversary"))
        # 参考回代用该记录的冻结模块；不使用已升级的恢复实现。
        frozen=parentmodule(typeof(x.case))
        q=Base.invokelatest(check_reference,x.case,TOML.parsefile(joinpath(out,name,"reference.toml"));science=frozen)
        v=x.validation;expected=freeze["expected"][name]
        all(y->isequal(y,expected)||isapprox(y,expected;atol=1e-7),
            (q.lower,q.upper,v["lower_bound_MWh"],v["upper_bound_MWh"])) || error("摘要/解析值不同")
    end
    println("R7 inner source-frozen values and full fault/topology references verified without optimization.")
end

length(ARGS)==2 || error("usage: r7_inner_study.jl run|check NEW_DIRECTORY")
ARGS[1]=="run" ? run_study(ARGS[2]) : ARGS[1]=="check" ? check_study(ARGS[2]) : error("unknown action")
