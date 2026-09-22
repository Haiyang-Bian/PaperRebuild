# Windows盘符须从单词边界开始；TOML错误说明中的because:\n不是路径。
r5_risk_has_host_path(text::AbstractString) =
    occursin(r"(?i)(?<![A-Z0-9_])[A-Z]:[\\/]|/Users/|/home/", text)
