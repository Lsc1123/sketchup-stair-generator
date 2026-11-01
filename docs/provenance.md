# 代码来源与许可

上游仓库：<https://github.com/Lsc1123/sketchup-spatial-workbench>。

拆分基线：`6792e3e1a4a474df87d28f28a8e47ade21c99d57`，读取日期 2026-11-01。

- `core/independent-stairs.js`：独立楼梯落点搜索、均分踢面与梯型布局的来源，移植到 `src/lsc_stairs/core.rb`。
- `src/lsc_spatial_workbench/independent_stairs.rb`：参考独立组件、捕捉落点和局部坐标组织；适配层独立实现，无方案、空间、墙板或洞口依赖。
- 原代码 MIT License，Copyright (c) 2026 LSC；本仓库和 RBZ 保留完整许可和来源说明。

本次拆分重构了踏步与平台衔接，采用每段 n 个踢面、n−1 个踏面；新增尺寸模式、双跑直梯、扶手、参数更新和界面。原模型与旧插件元数据不转换，也不覆盖。

楼梯几何均为矩形踏步／平台与圆管，不需要多边形布尔库，因此未带入原项目的 Clipper、JSBN 或其他工作台代码。插件命名空间为 `LSC::Stairs`，属性字典 `LSC_Stairs`，加载器 `lsc_stairs.rb`。

界面布局参考 [Apple HIG Layout](https://developer.apple.com/design/human-interface-guidelines/layout) 和 [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)。使用系统自带字体，不分发 Apple 字体、商标或图标资产；插件图标由本项目 `tools/icon.py` 生成。
