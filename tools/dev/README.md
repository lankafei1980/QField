# 开发自测工具（无需 RTK 硬件 / 千寻账号）

三个纯标准库 Python 脚本，用来在没有接收机和差分账号的情况下验证「定位 + NTRIP 差分 + 断线重连」整条链路。

## 1. 模拟 NTRIP caster

```bash
python3 tools/dev/mock_ntrip_caster.py --port 2101 --user demo --password demo --mount AUTO
```

- 支持 NTRIP 1.0（`ICY 200 OK`）与 2.0（`HTTP/1.1 200 OK`）
- `--user/--password` 打开 HTTP Basic 认证（不需要认证就不传）
- 挂载点随便填时回 SOURCETABLE；`--mount` 限定可接受的挂载点
- 每秒下发一组合法的 RTCM 3 帧（1005/1074/1084/1094/1124/1230，仅帧结构与 CRC 真实）
- 记录客户端上报的 GGA 条数（每条连接结束时打印）
- `--drop-after 15` 可主动断链，用来验证自动重连

在 App 里：定位设备连上任意接收机（或第 2 节的模拟接收机）→ 启用 NTRIP 校正 → 主机填电脑局域网 IP、端口 2101、挂载点 `AUTO`、账号 `demo/demo`。

## 2. 模拟 GNSS 接收机（替代 SparkFun 的蓝牙串口）

```bash
python3 tools/dev/mock_gnss_receiver.py --port 2102 --lat 39.9087 --lon 116.3975 --quality 4
```

- 以 4 Hz 输出 GGA/GSA/GST/GSV/RMC，坐标缓慢移动
- `--quality 4` 模拟 RTK 固定解（1 单点、5 浮点）
- 解析并统计客户端回写的 RTCM 帧号，证明差分确实被回写成功

在 App 里：定位设备 → 添加 → **TCP (NMEA)** → 主机填电脑 IP、端口 2102。

## 3. 千寻 caster 连通性探测

```bash
python3 tools/dev/qxwz_probe.py                       # 8001/8002/8003 三个端口
python3 tools/dev/qxwz_probe.py --user U --password P --port 8003
```

- 只验证网络可达与请求格式；没有账号时返回 `HTTP 401 Unauthorized` 属于正常（说明 caster 听懂了请求）
- 用来把「网络不通」和「账号密码错」分开

## 建议的验收顺序

1. 起 caster + 模拟接收机，App 连 TCP 设备 → 定位面板出坐标；
2. 打开 NTRIP → 状态变「已连接」、字节数双向增长；
3. 模拟接收机日志出现 `RTCM 1005 …` → 差分回写成功；
4. 用 `--drop-after` 断链 → 观察 5/10/20 秒后自动重连；
5. 换成真实 SparkFun 与千寻账号，重复 2–4 步并做已知点比对。
