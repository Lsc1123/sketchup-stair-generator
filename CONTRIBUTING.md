# 参与开发

请先阅读 README 与 `docs/provenance.md`。几何改动集中在 `core.rb`；SketchUp API 仅进入适配层，预览不得自行计算第二套模型。

提交前运行 README 的开发命令。影响踏步、平台、扶手、端点求解时加入能够检出真实回归的几何测试。修改运行文件须重打包，确保 ZIP 只含 allowlist 内的文件。不要上传用户模型、真实项目数据、插件安装目录、鉴权文件或本机日志。

原生测试 `tests/native.rb` **只允许在独立 SketchUp 进程和明确命名的空白测试文件上执行**。运行前检查无人操作该测试进程；不得拿当前用户模型作为测试对象，不得通过删除用户 Plugins 文件来隔离环境。测试入口要求显式传入 fixture、package 和 output 绝对路径，且初始模型必须与 fixture 一致、顶层实体为零。

```ruby
require '/absolute/path/to/extracted-rbz/lsc_stairs/main.rb'
load '/absolute/path/to/tests/native.rb'
LSCStairsNativeTest.run(
  fixture: '/absolute/path/to/empty-fixture.skp',
  package: '/absolute/path/to/extracted-rbz',
  output: '/absolute/path/to/test-results/native'
)
```

直接加载解包入口用于原生 API 测试，不代表扩展管理器安装、签名或加载策略验收通过。

原生测试会创建、清理和保存自己的合成模型。报告必须区分纯 Ruby、模拟接口与真正的 SketchUp 原生结果；不得用语法检查代替交互验收。

建议 Issue 包含 SketchUp 版本、系统、梯型、参数、操作步骤和预期／实际结果。PR 说明用户触发方式、行为变化和验证范围。贡献按 MIT 许可提交。
