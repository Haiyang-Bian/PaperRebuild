# 第3章来源和转录

- `sources.toml`：公开来源、固定版本、许可边界及锁定 SHA-256。
- `thesis-parameters.toml`：PDF 55–56 的表3-2至3-5、系统描述、图3-2连接转录。
  表头原单位保留，转换放在 Julia；CHP数量矛盾未消除。
- 原始下载：`data/raw/ch03/<source-id>/<sha256>/`（忽略）。
- 初步验证：`data/processed/ch03/<run-id>/`（忽略）。失败不覆盖前次记录。
- 经审阅摘要：`results/summaries/ch03-data/`；人类入口为 Documenter 的“第3章数据搜集”。

工作簿只读取选定单元格，拒绝空值、表达式和公式缓存作为未经核验输入；不执行MATLAB代码。
Google导出工作簿缺少有效dimension元数据，不能用 `sheet[:]` 判断只有一个单元格。
固定区域已按原表定位并绑定整文件哈希。工业园sheet本批只做目录定位，尚未导入验证。
未知时间步长、温度/流量单位不会根据数字外观猜测，更不会填入论文算例。
