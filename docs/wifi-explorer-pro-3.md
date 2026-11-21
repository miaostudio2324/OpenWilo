# WiFi Explorer Pro 3 调研与 OpenWilo 功能对照

此文档记录设计初期的功能调研，当前功能以项目 README 为准。
调研日期为 2026 年 11 月 21 日。依据 Intuitibits 的产品说明、扫描模式文章和版本记录，其中最新列出的版本为 3.10.6。

| 功能 | WiFi Explorer Pro 3 | OpenWilo 0.1 |
| --- | --- | --- |
| 网络发现 | 主动扫描、按已知 SSID 定向扫描、使用监控模式的被动扫描 | 通过 CoreWLAN 提供主动和定向扫描，可连续刷新，可请求包含隐藏结果 |
| 无线环境图 | 逐频段查看信道、信号与历史，可结合频谱仪数据 | 2.4、5、6 GHz 信道分布，RSSI 时间线，接入点重叠估算 |
| 网络检查 | 基础和高级字段、信息元素、对比、关联客户端 | BSSID、主信道、带宽、RSSI、噪声、SNR、制式、安全、区域、BSS Load、部分信息元素识别及原始十六进制、所选接入点对比 |
| 整理与标注 | 按 SSID、物理 AP 或厂商组织，有表达式筛选、颜色规则、自定义字段及列配置 | 可排序表格，频段、SSID、BSSID、备注、制式、安全、信道及最低 RSSI 筛选，BSSID 备注 |
| 保存和交换 | 保存结果，导入抓包和第三方扫描数据，支持导出 CSV；3.10 加入 PCAP/PCAPNG 导出 | 本地 JSON 会话保存与恢复，导出筛选结果或所选项为 CSV |
| 专业采集 | 远程传感器、外部适配器、RF 频谱仪、BLE 近距信标等 | 使用 Mac 的默认 Wi-Fi 接口 |

## 实现边界

- 被动扫描依赖监控模式以及可靠的信道切换。厂商版本记录也列出了部分 Apple 芯片搭配 macOS Tahoe 时的限制。本版采用标准 CoreWLAN 路径，保持既有 Wi-Fi 连接。
- 信道分布基于广播信息、频宽和扫描 RSSI。通过独立频谱仪才能测量非 Wi-Fi 射频干扰。BSS Load 字段只在接入点提供该信息时显示。
- 6 GHz 和 Wi-Fi 7 字段受系统返回的扫描数据限制。提供 EHT 信息元素时可识别 Wi-Fi 7 和相应带宽。缺少中心信道时用虚线展示以主信道为中心的估算。明确识别出的 VHT 80+80 MHz 配置只在详情中呈现。
- 远程扫描、抓包导入导出、物理 AP 或厂商归组、完整信息元素解码、关联客户端、频谱和 BLE 集成属于独立功能模块，本版尚未实现。

## 来源

- [Intuitibits 产品页和版本对照](https://www.intuitibits.com/products/wifiexplorerpro3/)
- [Intuitibits 扫描模式说明](https://www.intuitibits.com/2017/08/11/understanding-scan-modes-wifiexplorerpro/)
- [Intuitibits 版本记录](https://www.intuitibits.com/release-notes/wifiexplorerpro3/)
- [Apple CoreWLAN](https://developer.apple.com/documentation/CoreWLAN)
- [Apple 定位授权](https://developer.apple.com/documentation/CoreLocation/requesting-authorization-to-use-location-services)
- [Linux 内核 802.11 EHT 信息元素定义](https://github.com/torvalds/linux/blob/master/include/linux/ieee80211-eht.h)
