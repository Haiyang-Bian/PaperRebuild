using TOML, SHA, CSV
length(ARGS) in (2, 3) || error("usage: check_r9_trading_delivery.jl SUMMARY DOC_ASSETS [--seal]")
report, assets=abspath.(ARGS[1:2])
hashfile(p) = bytes2hex(sha256(read(p)))
inventory(root) = sort([
    replace(relpath(joinpath(dir, f), root), '\\'=>'/') for (dir, _, names) in walkdir(root) for
    f in names
])
meta=TOML.parsefile(joinpath(report, "evidence.toml"))
meta["origin"]=="synthetic" && !meta["bargaining"] && !meta["distributed_algorithm"] ||
    error("Research scope changed")
figure=joinpath(report, "figures")
config=TOML.parsefile(joinpath(figure, "figure.toml"))
config["input_sha256"]==meta["input_sha256"] && !config["optimization_performed"] ||
    error("Figure identity changed")
for (rel, h) in config["files"]
    hashfile(joinpath(figure, rel))==h || error("Figure source changed")
end
read(joinpath(figure, "heat-cut.csv"))==read(joinpath(report, "heat-cut.csv")) ||
    error("Figure values differ from the report")
inventory(figure)==inventory(assets) || error("Documenter figure file set differs")
for rel in inventory(figure)
    read(joinpath(figure, rel))==read(joinpath(assets, rel)) ||
        error("Documenter figure bytes differ")
end
manifest=joinpath(report, "artifact-hashes.toml")
files=filter(!=("artifact-hashes.toml"), inventory(report))
all(filesize(joinpath(report, p))<=5*1024^2 for p in files) || error("Oversized public file")
if length(ARGS)==3
    ARGS[3]=="--seal" && !ispath(manifest) || error("Do not replace a delivery seal")
    open(
        io->TOML.print(
            io,
            Dict("files"=>Dict(p=>hashfile(joinpath(report, p)) for p in files));
            sorted = true,
        ),
        manifest,
        "w",
    )
end
expected=TOML.parsefile(manifest)["files"]
Set(keys(expected))==Set(files) || error("Delivery inventory changed")
for (rel, h) in expected
    hashfile(joinpath(report, rel))==h || error("Delivery bytes changed")
end
println("R9 delivery hashes and figure copies passed: ", length(files), " files; no optimization.")
