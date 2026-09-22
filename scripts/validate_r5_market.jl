using PaperRebuild, TOML, SHA
length(ARGS)==1 || error("参数：运行目录或完整study.toml")
target=abspath(only(ARGS))
if isdir(target)
    loaded=read_r5_market_run(target)
    println(
        loaded.result["run_id"],
        " | ",
        loaded.result["status"],
        " | primal=",
        loaded.validation["model_pass"],
        " | KKT=",
        loaded.validation["kkt_pass"],
    )
else
    study=TOML.parsefile(target)
    study["schema"]=="r5-market-study-v1" && study["complete"] || error("市场批次未完整结束")
    expected=Set(x["id"] for x in study["rules"]["records"])
    length(study["records"])==length(expected) &&
    Set(x["id"] for x in study["records"])==expected || error("正式清单缺失或重复")
    for x in study["records"]
        path=joinpath(dirname(target), x["id"])
        bytes2hex(sha256(read(joinpath(path, "result.toml"))))==x["result_sha256"] ||
            error("原结果变化")
        loaded=read_r5_market_run(path)
        loaded.case.sha256==x["case_sha256"]==study["rules"]["input_sha256"][x["case"]] ||
            error("输入变化")
    end
    println(
        "Verified ",
        length(expected),
        " saved market runs, including failures; no optimization performed.",
    )
end
