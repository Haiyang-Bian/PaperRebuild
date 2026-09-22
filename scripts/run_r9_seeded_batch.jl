using TOML
length(ARGS)==3 || error("usage: COMMON_INPUT SEEDED_FREEZE NEW_OUTPUT")
common, frozen, out=abspath.(ARGS)
ispath(out) && error("Preserve previous batch")
mkpath(out)
m=TOML.parsefile(joinpath(frozen, "manifest.toml"))
for scheme in m["protocol"]["schemes"]
    script=joinpath(frozen, "implementation/scripts/r9_seeded_study.jl")
    project=joinpath(common, "study/code")
    target=joinpath(out, scheme)
    cmd=`$(Base.julia_cmd()) --startup-file=no --depwarn=error --project=$project $script run $common $frozen $scheme $target`
    println("START ", scheme)
    flush(stdout)
    open(joinpath(out, scheme*".log"), "w") do io
        p=run(pipeline(ignorestatus(cmd), stdout = io, stderr = io))
        println("EXIT ", scheme, " ", p.exitcode)
        flush(stdout)
        success(p) || error("Process failure preserved: $scheme")
    end
end
println("Three declared methods finished; scientific pass requires independent validation.")
