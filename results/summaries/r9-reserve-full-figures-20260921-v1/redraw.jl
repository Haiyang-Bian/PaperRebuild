# 正式批次没有原始候选时，画终止状态和输入风险几何，不画虚构费用/残差。
using CairoMakie, CSV, TOML, SHA
length(ARGS)==2 || error("usage: plot_r9_reserve_limits.jl EVIDENCE NEW_FIGURES")
input,out=abspath.(ARGS)
ispath(out) && error("Preserve previous figures")
hashfile(p)=bytes2hex(sha256(read(p)))
hashes=TOML.parsefile(joinpath(input,"artifact-hashes.toml"))["files"]
for p in ("summary.csv","support.csv")
    hashfile(joinpath(input,p))==hashes[p] || error("Changed figure source")
end
s=collect(CSV.File(joinpath(input,"summary.csv");types=Dict(:scheme=>String,:method=>String,:run_id=>String,:status=>String,:case_sha256=>String)))
q=collect(CSV.File(joinpath(input,"support.csv");types=Dict(:method=>String,:scenario=>String)))
all(!x.pilot && !x.model_pass && x.status=="time_limit_no_incumbent" for x in s) || error("This figure is only for declared no-candidate batch")
schemes=["3A","3B","3C"]
r=[only(filter(x->x.scheme==k,s)) for k in schemes]
f=Figure(size=(1280,1000),fontsize=19)
Label(f[0,1],"F43 | Synthetic 100-scenario reserve batch | No primal candidate",fontsize=24)
a=Axis(f[1,1],ylabel="Complete process time (s)",xticks=(1:3,schemes),title="All methods reached the solver time limit; no infeasibility proof")
barplot!(a,1:3,[x.elapsed_sec for x in r];color=[:steelblue,:darkorange,:seagreen])
hlines!(a,[600.0];color=:firebrick,linestyle=:dash,label="600 s total budget")
ylims!(a,0,650)
axislegend(a;position=:lb)
for (i,x) in enumerate(r)
    text!(a,i,x.elapsed_sec+10;text=string(round(x.elapsed_sec;digits=2))*" s",align=(:center,:bottom),fontsize=16)
end
b=Axis(f[2,1],xlabel="Frozen representative index (not time)",ylabel="Worst probability of one event",title="Input-only audit; 3C permits only 2 of 100 single-event choices")
for (k,color) in (("3B",:darkorange),("3C",:seagreen))
    method=only(filter(x->x.scheme==k,r)).method
    rows=filter(x->x.method==method,q)
    lines!(b,1:100,[x.worst_single_event for x in rows];color,label=k)
end
hlines!(b,[.05];color=:black,linestyle=:dash,label="epsilon = 0.05")
ylims!(b,0,.10)
axislegend(b;position=:rt)
Label(f[3,1],"3A: every single-event bound equals 1, with epsilon = 0. No cost ranking or held-out guarantee.",fontsize=16)
mkpath(out)
for ext in ("png","pdf")
    save(joinpath(out,"F43-scale-and-risk-boundary."*ext),f)
end
meta=Dict("schema"=>"r9-reserve-limit-figure-v1","origin"=>"synthetic",
    "run_ids"=>[x.run_id for x in r],"source_evidence_sha256"=>hashfile(joinpath(input,"artifact-hashes.toml")),
    "source_tables"=>Dict(p=>hashes[p] for p in ("summary.csv","support.csv")),
    "script_sha256"=>hashfile(@__FILE__),"optimization_performed"=>false)
open(io->TOML.print(io,meta;sorted=true),joinpath(out,"figure-source.toml"),"w")
cp(@__FILE__,joinpath(out,"redraw.jl"))
println("F43 rendered from terminal statuses and frozen support geometry.")
