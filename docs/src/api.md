# 骨架 API

以下函数来自初始化模板，仅验证包加载、测试和 Documenter 集成。
论文模型尚未实现，后续按研究任务增量添加 API。

```@docs
PaperRebuild.hello
PaperRebuild.domath
```

```jldoctest
julia> using PaperRebuild

julia> PaperRebuild.hello("Julia")
"Hello, Julia"

julia> PaperRebuild.domath(2)
7
```
