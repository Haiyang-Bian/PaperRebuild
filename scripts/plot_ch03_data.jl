# 只读保存的检查产物绘图，不下载、不优化、不积分未知时间步长。
using CairoMakie, CSV, SHA, TOML
root = normpath(joinpath(@__DIR__, ".."))
length(ARGS) == 1 || error("用法：scripts/plot_ch03_data.jl data/processed/ch03/<run-id>")
dir = abspath(ARGS[1])
report = TOML.parsefile(joinpath(dir, "validation.toml"))
report["status"] == "preliminary_checks_passed_with_open_issues" ||
    error("仅绘制完成结构检查的输入")
path = joinpath(dir, "aggregate-loads.csv")
bytes2hex(sha256(read(path))) == report["output_sha256"]["aggregate-loads.csv"] ||
    error("图源数据哈希不符")
rows = filter(r -> r.source_id == "figshare-14813121-v3", collect(CSV.File(path)))
folder = joinpath(dir, "figures")
isdir(folder) && error("图目录已存在；保留原图，使用新检查运行重绘")
mkpath(folder)
figure = Figure(; size = (1050, 720), fontsize = 17)
Label(figure[0, 1], "Public modified Barry Island: preliminary data check"; fontsize = 23)
ax1 = Axis(
    figure[1, 1];
    xlabel = "Sample index (time step not verified)",
    ylabel = "Electric demand (MW)",
)
ax2 = Axis(
    figure[2, 1];
    xlabel = "Sample index (time step not verified)",
    ylabel = "Heat demand (MW)",
)
lines!(
    ax1,
    getproperty.(rows, :sample),
    getproperty.(rows, :P_MW);
    color = :steelblue,
    linewidth = 2.5,
)
lines!(
    ax2,
    getproperty.(rows, :sample),
    getproperty.(rows, :H_MW);
    color = :darkorange,
    linewidth = 2.5,
)
Label(
    figure[3, 1],
    "Source: Chun Qin, Figshare 14813121 v3 (CC BY 4.0). 33 electric / 33 heat nodes.\nNot the thesis PDN33-DHN32 case. Run: " *
    report["run_id"];
    fontsize = 12,
)
for suffix in ("png", "svg")
    save(joinpath(folder, "public-load-profiles." * suffix), figure)
end
CSV.write(joinpath(folder, "public-load-profiles.csv"), rows)
open(joinpath(folder, "figure-config.toml"), "w") do io
    TOML.print(
        io,
        Dict(
            "run_id" => report["run_id"],
            "source_id" => "figshare-14813121-v3",
            "source_url" => "https://doi.org/10.6084/m9.figshare.14813121.v3",
            "license" => "CC BY 4.0",
            "x_unit" => "sample index; not hours",
            "y_unit" => "MW",
            "energy_integration" => false,
            "input_sha256" => bytes2hex(sha256(read(path))),
            "script_sha256" => bytes2hex(sha256(read(@__FILE__))),
            "width" => 1050,
            "height" => 720,
        );
        sorted = true,
    )
end
println("Saved figures: ", replace(relpath(folder, root), '\\' => '/'))
