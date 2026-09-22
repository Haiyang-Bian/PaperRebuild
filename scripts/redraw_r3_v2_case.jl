include("r3_setup.jl")
include("plot_r3_pg.jl")
include("plot_r3_comparison.jl")
length(ARGS)==3 || error("usage: redraw_r3_v2_case.jl STUDY_TOML RUN_ID NEW_OUTPUT")
studyfile, id, output=ARGS
study=TOML.parsefile(studyfile)
entries=filter(e->e["id"]==id, study["runs"])
length(entries)==1 || error("运行ID必须唯一")
entry=only(entries)
directory=joinpath(dirname(studyfile), entry["directory"])
loaded=read_r3_run(directory)
plot_r3_pg_run(directory; output, loaded)
if entry["group"]=="robustness"
    root=normpath(joinpath(@__DIR__, ".."))
    old=read_r3_run(joinpath(root, entry["old_directory"]))
    plot_r3_pg_comparison(old.result, loaded.result, id, output)
end
println(output)
