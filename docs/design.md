# 独立楼梯插件设计

来源：LSC 空间推敲台 `6792e3e1a4a474df87d28f28a8e47ade21c99d57`。

用户明确指定苹果设计参考，因此采用 Overhaul 模式：参考 Apple HIG 的 macOS 布局、侧栏和控件层次。界面定位为桌面参数检查器，近距离操作；安静、中性、清晰。浅灰 #f5f5f7、白 #ffffff、蓝 #007aff、墨色 #1d1d1f，系统字体 -apple-system / BlinkMacSystemFont / Segoe UI。4px 间距基准、10px 分组圆角、8px 控件圆角、轻投影与 120ms 状态反馈。视觉变化 3、动效 1、密度 7、素材依赖 1、既有品牌保留 4。参考苹果的交互层次，不使用 Apple 商标、SF Symbols 或仿系统窗口控制按钮。颜色和系统字体的选择服务于平台操作习惯。

参考来源：https://developer.apple.com/design/human-interface-guidelines/layout 与 https://developer.apple.com/design/human-interface-guidelines/sidebars 。用户已明确授权界面重做及全部功能完善，日常布局和控件选择在此范围内。

单面板顺序：梯型 → 尺寸与转向 → 平台与扶手 → 放置／更新。右侧为真实几何的轴测预览和计算值；窄窗口改为上下布局。参数变动后由 Ruby 核心重新计算；预览与生成共享同一份几何，不维护第二套 JavaScript 求解器。

几何核心由原项目 independent-stairs.js 的落点求解算法移植为纯 Ruby，矩形部件无需 Clipper。新增层高模式、双跑直梯、扶手与立柱。所有参数以 mm 储存，SketchUp 适配层统一转为英寸。模型元数据使用独立字典 LSC_Stairs，旧插件可同时安装。

更新仅重建当前组件实例：先 make_unique，保留实例变换、名称、材质和标签；事务失败回滚。手工修改的组件内部会在参数更新时重建，界面明确说明。普通原生编辑不受限制。模型切换、旧请求、选面取消与关闭面板须使旧预览失效。
