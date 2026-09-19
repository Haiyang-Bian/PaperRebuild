using PaperRebuild, TOML

length(ARGS)==1||error("usage: audit_r7_lp_identity.jl SAVED_ADVERSARY")
dir=abspath(ARGS[1]);
data=TOML.parsefile(joinpath(dir, "case.toml"))
r=TOML.parsefile(joinpath(dir, "result.toml"))
it=first(filter(x->!isempty(x["master"]["topologies"]), r["iterations"]))
z=it["master"]["topologies"][1]
expected=it["master"]["values"]["blocks"][1]["matrix_sha256"]
frozen=Module(gensym(:FrozenLPIdentity))
Core.eval(frozen, :(using JuMP, TOML, SHA, Dates, UUIDs))
Core.eval(frozen, :(const MOI=JuMP.MOI))
for part in ("recovery", "adversary"),
    layer in ("core", "formulations", "verification", "algorithms", "reporting")

    Base.include(frozen, joinpath(dir, "code/src", layer, "r7_$part.jl"))
end
c=Base.invokelatest(frozen.R7RecoveryCase, data)
a=Base.invokelatest(frozen.r7_recovery_lp, c, z)
current_case=PaperRebuild.R7RecoveryCase(data)
current_before=PaperRebuild.r7_recovery_lp(current_case, z)
@eval using JuMP
b=Base.invokelatest(frozen.r7_recovery_lp, c, z)
current_after=PaperRebuild.r7_recovery_lp(current_case, z)
current_before.sha256==current_after.sha256 || error("当前LP身份仍依赖Main导入环境")
isequal(current_after.data, b.data) || error("身份修正改变了规范LP内容")
println("current_namespace_independent=true; current_rows_equal_original_exposed_rows=true")
println("before_import_matches=", a.sha256==expected)
println("after_import_matches=", b.sha256==expected)
for key in sort(collect(keys(a.data)))
    isequal(a.data[key], b.data[key])&&continue
    if key=="rows"
        counts=Dict{String,Int}()
        for (ra, rb) in zip(a.data[key], b.data[key]), k in keys(ra)
            isequal(ra[k], rb[k]) || (counts[k]=get(counts, k, 0)+1)
        end
        println("row_differences=", counts)
        firstdiff=findfirst(i->a.data[key][i]!=b.data[key][i], eachindex(a.data[key]))
        firstdiff===nothing||println(
            "first_label=",
            a.data[key][firstdiff]["source"],
            " => ",
            b.data[key][firstdiff]["source"],
        )
    else
        println("different_field=", key)
    end
end
