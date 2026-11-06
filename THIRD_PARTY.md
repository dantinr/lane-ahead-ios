# 第三方依赖与素材

- 高德导航 SDK 11.3.100、基础 SDK 1.9.4 No IDFA、搜索 SDK 9.8.1：从高德官方下载，来源及校验值见 `scripts/sdk-manifest.json`。`Vendor/` 不纳入版本控制；SDK 使用受其提供方条款约束。官方隐私清单随本地构建复制进 App 的独立 bundle。
- `LaneAhead/Resources/volkswagen-car-frames.png`：复用同一用户的 LaneAhead 鸿蒙工程车标图集，72 张 112×112 帧纵向排列。原始标识来源为 [Volkswagen logo 2019](https://commons.wikimedia.org/wiki/File:Volkswagen_logo_2019.svg)，该来源页标注 PD-textlogo；大众标识归对应品牌所有。该图仅为车辆装饰标记，不修改 SDK 的定位、车辆朝向或相机。
- 城市索引：复用鸿蒙工程于 2026-10-25 获取的高德公开行政区城市名称，来源为[行政区查询](https://lbs.amap.com/api/webservice/guide/api/district/)，不含个人位置。
- App 图标与首页道路示意由代码绘制；道路示意为装饰图形，不是真实地图或路线。
