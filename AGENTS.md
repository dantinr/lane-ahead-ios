# LaneAhead iOS

原生 SwiftUI iPhone 项目，包名 `com.laneahead.ios`。功能和规则参照同级 `lane-ahead-harmony` 0.0.32，平台适配必须根据 iOS SDK 的实际公开接口实现。

- 先读 README 和 docs/parity-and-validation.md。真实、历史、未知与虚构演示必须明确区分；不填充虚构的真实车道。
- Swift 纯逻辑位于 LaneAhead/Core；`swift test` 不需要地图 Key。Xcode App 编入相同源文件。高德适配位于 Bridge，Swift 服务位于 Services，页面位于 Views。
- 修改源文件后运行 `python3 scripts/generate-project.py` 同步工程。不要手工编辑生成的 project.pbxproj 后又丢失设置；调整工程配置应修改生成脚本。版本由 VERSION 维护。
- SDK 由 scripts/setup-sdk.py 下载，固定版本和 SHA-256。不要提交 Vendor、.build、build、设备日志或截图。
- 实际 iOS Key 放 `.local/k`，兼容 `.local/gaode-ios`；两者存在时优先使用 `.local/k`。构建生成被忽略的 MapKeys.plist；本机 Team ID 放 `.local/team-id`。不打印、提交、写入文档或测试真实凭据；不要重置钥匙串或修改用户的证书访问控制。
- 导航选路、开始事件、当前 SDK 路线和当前位置必须一致；routeUID 保持字符串精度。旧回调、弱定位、重算、后台和过期状态不得产生真实采集。
- 车道历史永久保存，仅三个月建议更新；不引入静默淘汰。原子写入在 repository actor 中进行；损坏文件不自动覆盖。清除各类历史互不影响。
- 只有真实 GPS 开始创建导航历史，保留最近 200 次，不记录完整轨迹；到达状态不能被晚到的退出或写入降级。搜索只在有效响应且会话未取消时记历史。
- Core Motion userAcceleration 已去重力且单位为 g，gravity 需适配方向。未知、过期、不可用不得显示伪造读数；传感器样本、校准与峰值不持久化或上传。
- 修改逻辑运行相关 Swift 测试；修改界面、桥接或生命周期完成模拟器和真机构建，合适时跑 XCUITest。单独报告逻辑测试、页面检查、真实 SDK 联调与实车验证，不能相互替代。
- 用户明确要求提交或推送时才执行，暂存使用明确文件列表。保持鸿蒙原工程及其真实设备数据不变。
