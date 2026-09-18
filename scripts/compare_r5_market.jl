using PaperRebuild, TOML
length(ARGS)==2 || error("参数：同输入运行目录A 运行目录B")
TOML.print(stdout, compare_r5_market_runs(ARGS[1], ARGS[2]); sorted = true)
