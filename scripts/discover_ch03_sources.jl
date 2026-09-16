# 只读取公开的版本元数据。原始响应保存在忽略目录，供来源登记复核。
using Downloads
root = normpath(joinpath(@__DIR__, ".."))
folder = joinpath(root, "data", "raw", "ch03", "discovery")
mkpath(folder)
for (name, url) in [
    ("figshare-v3.json", "https://api.figshare.com/v2/articles/14813121/versions/3"),
    (
        "matpower-license.txt",
        "https://raw.githubusercontent.com/MATPOWER/matpower/1a828c7af590714499284e36ee9c81273388c594/LICENSE",
    ),
]
    path = joinpath(folder, name)
    if !isfile(path) || filesize(path) == 0
        temporary = tempname(folder)
        Downloads.download(url, temporary; timeout = 60)
        mv(temporary, path; force = true)
    end
    println("=== ", name, " ===")
    println(read(path, String))
end
