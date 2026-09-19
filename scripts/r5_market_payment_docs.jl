using TOML

"""从策略报价台账生成支付公式及符号，保持原式和项目采用解释分开。"""
function r5_market_payment_doc_text(ledger)
    io=IOBuffer()
    println(
        io,
        "# 策略报价准备：支付推导与符号\n\n由strategic.toml生成。R5-SP是项目编号，连续策略报价优化尚未实现。\n",
    )
    for x in ledger["equation"]
        println(
            io,
            "## ",
            x["id"],
            "\n\n~~~math\n",
            x["latex"],
            "\n\\tag{",
            x["id"],
            "}\n~~~\n\n",
            x["meaning"],
            "\n\n原式：",
            join(x["source_equations"], "、"),
            "；API：[`",
            x["api"],
            "`](@ref)；测试：`",
            x["test"],
            "`。\n",
        )
    end
    println(
        io,
        "## 符号与作用域\n\n| ID | 数学符号 | 含义 | 单位 | Julia映射 | 作用域 |\n|---|---|---|---|---|---|",
    )
    for x in ledger["symbol"]
        println(
            io,
            "| ",
            x["id"],
            " | ``",
            x["latex"],
            "`` | ",
            x["meaning"],
            " | ",
            x["unit"],
            " | `",
            x["julia"],
            "` | ",
            x["scope"],
            " |",
        )
    end
    println(io, "\n## 原文、采用解释与证据\n")
    for x in ledger["issue"]
        println(
            io,
            "### ",
            x["id"],
            "\n\n**原文：**",
            x["original"],
            "\n\n**采用解释：**",
            x["adopted"],
            "\n\n**证据与边界：**",
            x["evidence"],
            "\n",
        )
    end
    rstrip(String(take!(io)))*"\n"
end

function sync_r5_market_payment_docs()
    root=normpath(joinpath(@__DIR__, ".."))
    ledger=TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "strategic.toml"))
    path=joinpath(root, "docs", "src", "ch05-strategic-equations.md")
    text=r5_market_payment_doc_text(ledger)
    (!isfile(path)||read(path, String)!=text)&&write(path, text)
end
