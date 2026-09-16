# 只读工作簿定位工具：输出有内容的行及准确坐标，不改写原件。
using XLSX, TOML
root = normpath(joinpath(@__DIR__, ".."))
for id in ("qin2021-author-workbook", "figshare-14813121-v3")
    receipt = TOML.parsefile(joinpath(root, "data", "raw", "ch03", id, "receipt.toml"))
    xf = XLSX.readxlsx(joinpath(root, receipt["path"]))
    println("SOURCE ", id)
    println(xf)
    for name in XLSX.sheetnames(xf)
        sheet = xf[name]
        cells = sheet["A1:AZ1500"]
        occupied = findall(!ismissing, cells)
        nr = maximum(i -> i[1], occupied)
        nc = maximum(i -> i[2], occupied)
        (nr < 1500 && nc < 52) || error("检查窗口不足，请扩大显式范围")
        cells = cells[1:nr, 1:nc]
        println("SHEET ", name, " size=", size(cells))
        # 先看标题和尾部；按参数可以只看指定表的指定行。
        rows =
            isempty(ARGS) ?
            unique(
                vcat(
                    1:min(12, size(cells, 1)),
                    [
                        r for r in axes(cells, 1) if any(
                            v ->
                                v isa AbstractString && occursin(
                                    r"(?i)\bdata|\bload|\bpipe|\bnode|\bbase|\bunit|heat\.|mpc\.|rho|Cp",
                                    v,
                                ),
                            cells[r, :],
                        )
                    ],
                    max(1, size(cells, 1)-3):size(cells, 1),
                ),
            ) :
            (
                length(ARGS) == 3 && ARGS[1] == name ? (parse(Int, ARGS[2]):parse(Int, ARGS[3])) :
                Int[]
            )
        for row in rows
            entries = [
                "$(XLSX.encode_column_number(col))$row=$(cells[row,col])" for
                col in axes(cells, 2) if !ismissing(cells[row, col])
            ]
            println(join(entries, " | "))
        end
    end
end
