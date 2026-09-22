# 只读核对公开证据、图源及Documenter副本；--seal仅能首次生成交付清单。
using TOML, SHA
length(ARGS) in (2, 3) || error("usage: check_r9_network_delivery.jl SUMMARY DOC_ASSETS [--seal]")
report, assets=abspath.(ARGS[1:2])
hashfile(p) = bytes2hex(sha256(read(p)))
inventory(root) = sort([
    replace(relpath(joinpath(d, f), root), '\\'=>'/') for (d, _, names) in walkdir(root) for
    f in names
])
meta=TOML.parsefile(joinpath(report, "evidence.toml"))
meta["origin"]=="synthetic" &&
!meta["bargaining"] &&
!meta["complete_thermal_certification"] &&
!meta["solver_used_for_replay"] || error("Research boundary changed")
figure=joinpath(report, "figures")
config=TOML.parsefile(joinpath(figure, "figure.toml"))
config["study_manifest_sha256"]==meta["study_manifest_sha256"] &&
!config["optimization_performed"] || error("Figure identity changed")
for (rel, h) in config["files"]
    hashfile(joinpath(figure, rel))==h || error("Figure source changed")
end
for file in ("summary.csv", "topologies.csv", "trajectories.csv")
    read(joinpath(figure, file))==read(joinpath(report, file)) || error("Figure data differ")
end
inventory(figure)==inventory(assets) || error("Documenter figure inventory differs")
for rel in inventory(figure)
    read(joinpath(figure, rel))==read(joinpath(assets, rel)) || error("Figure copy differs")
end
audit=joinpath(report, "independent-heat")
for file in ("hashes.toml", "replay-files.toml")
    for (rel, h) in TOML.parsefile(joinpath(audit, file))["files"]
        hashfile(joinpath(audit, rel))==h || error("Independent heat evidence changed")
    end
end
for name in keys(TOML.parsefile(joinpath(audit, "replay-files.toml"))["files"])
    read(joinpath(audit, name))==read(joinpath(report, "code/scripts", name)) ||
        error("Frozen diagnostic dependency differs")
end
manifest=joinpath(report, "artifact-hashes.toml")
files=filter(!=("artifact-hashes.toml"), inventory(report))
all(filesize(joinpath(report, f))<=5*1024^2 for f in files) || error("Oversized public file")
if length(ARGS)==3
    ARGS[3]=="--seal" && !ispath(manifest) || error("Do not replace a delivery seal")
    open(manifest, "w") do io
        TOML.print(
            io,
            Dict("files"=>Dict(f=>hashfile(joinpath(report, f)) for f in files));
            sorted = true,
        )
    end
end
expected=TOML.parsefile(manifest)["files"]
Set(keys(expected))==Set(files) || error("Delivery inventory changed")
for (rel, h) in expected
    hashfile(joinpath(report, rel))==h || error("Delivery bytes changed")
end
println(
    "R9 network delivery: ",
    length(files),
    " files, frozen diagnostic and figure copies passed.",
)
