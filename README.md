# PaperRebuild

使用 Julia 逐步复现 `docs/摘要.pdf` 中博士论文的模型、算法和算例。

## 当前状态

- 原有 Julia 包为起始模板，尚未实现论文模型。
- 本机 `julia --version` 与现有 `Manifest.toml` 均为 `1.13.0-rc1`。
- 已完成 PDF 文本层检查、目录索引和部分关键页面的初步阅读，未完成全文精读或数值复现。
- 原 PDF 是约 70 MiB、157 页的扫描件，存在方向不一致、重复扫描及部分边缘截断。

从 [论文阅读与复现路线](docs/reading/README.md) 继续，原件校验信息见
[source_manifest.json](docs/reading/source_manifest.json)。

## 按页阅读

`scripts/read_thesis.py` 仅处理文献；科研模型和算法使用 Julia。
脚本需要 Python、`pypdf` 和 `pypdfium2`，当前 Codex 自带运行环境已提供。

```powershell
# 若默认 Python 中已提供上述依赖：
python scripts/read_thesis.py inspect

# PDF 物理页码从 1 开始；按原页内容方向选择顺时针旋转角度。
python scripts/read_thesis.py render --pages 30-32 --rotation 270 --dpi 160
python scripts/read_thesis.py render --pages 55-56 --rotation 90 --dpi 180
```

本次验证使用的 Python 路径：
`C:/Users/King/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`。

渲染每次最多 12 页，图片写入已忽略的 `tmp/pdfs/reading/`；
原 PDF 不会被修改。脚本不执行 OCR，也不自动推断扫描内容的方向。

## 第一阶段

阅读第 2 章设备与网络模型，以及第 3 章完整建模、算法和算例。
先建立带页码出处的公式、参数、原始数据需求及结果目标清单，
再开展 Julia 实现；当前候选为第 3 章的 PDN-33 / DHN-32 热电联合调度算例。
