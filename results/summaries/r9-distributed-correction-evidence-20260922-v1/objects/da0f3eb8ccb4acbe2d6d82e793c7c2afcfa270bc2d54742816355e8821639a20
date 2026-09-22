"""
    save_r4_heat_run(path, case, parent, reconstruction)

保存新的热核查证据，拒绝覆盖、源码改变或父结果改变；原始父运行不修改。
文件清单同时保护完整输入、父调度及新状态。
"""
function save_r4_heat_run(path, c, parent, r)
    ispath(path) && error("拒绝覆盖热核查目录")
    r["source_hashes_at_solve"]==r4_science_hashes() || error("源码已改变")
    validate_r4_heat_reconstruction(c, parent, r)
    mkpath(path)
    write(joinpath(path, "case.toml"), c.source_text)
    write(joinpath(path, "parent.toml"), r4_text(parent))
    write(joinpath(path, "reconstruction.toml"), r4_text(r))
    files=("case.toml", "parent.toml", "reconstruction.toml")
    hashes=Dict(f=>bytes2hex(sha256(read(joinpath(path, f)))) for f in files)
    write(joinpath(path, "hashes.toml"), r4_text(Dict("sha256"=>hashes)))
    path
end

"""读取独立热状态核查存档，拒绝文件增删/篡改，重新计算全部声明范围内的残差。"""
function read_r4_heat_run(path)
    hashes=TOML.parsefile(joinpath(path, "hashes.toml"))["sha256"]
    expected=Set(["case.toml", "parent.toml", "reconstruction.toml"])
    Set(keys(hashes))==expected || error("热核查清单不完整")
    Set(readdir(path))==union(expected, Set(["hashes.toml"])) || error("额外或缺失文件")
    for (f, h) in hashes
        bytes2hex(sha256(read(joinpath(path, f))))==h || error("热核查文件篡改")
    end
    c=load_r4_case(joinpath(path, "case.toml"))
    parent=TOML.parsefile(joinpath(path, "parent.toml"))
    r=TOML.parsefile(joinpath(path, "reconstruction.toml"))
    validation=validate_r4_heat_reconstruction(c, parent, r)
    haskey(r, "validation") && r["validation"]!=validation && error("保存与重算判定不同")
    (; case = c, parent, result = r, validation)
end
