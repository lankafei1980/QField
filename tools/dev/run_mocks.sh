#!/usr/bin/env bash
# Start the mock NTRIP caster and the mock NMEA GNSS receiver so that the phone
# can exercise the whole positioning + correction chain on the local network.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASTER_PORT="${CASTER_PORT:-2101}"
GNSS_PORT="${GNSS_PORT:-2102}"
USER_NAME="${NTRIP_USER:-demo}"
PASSWORD="${NTRIP_PASSWORD:-demo}"

LAN_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')"
LAN_IP="${LAN_IP:-$(hostname -I 2>/dev/null | awk '{print $1}')}"

cleanup() {
  echo
  echo "stopping mocks..."
  kill "${PIDS[@]}" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

python3 "$DIR/mock_ntrip_caster.py" --port "$CASTER_PORT" \
  --user "$USER_NAME" --password "$PASSWORD" --mount AUTO --drop-after 90 &
PIDS+=($!)

python3 "$DIR/mock_gnss_receiver.py" --port "$GNSS_PORT" --quality 4 &
PIDS+=($!)

sleep 1
cat <<EOF

=========================================================
 手机与电脑需在同一 Wi-Fi，然后在 App 里这样填：

 1) 定位设备 → 添加 → TCP (NMEA)
      地址：${LAN_IP}    端口：${GNSS_PORT}

 2) 设置 → 定位 → 启用 NTRIP 校正 → 调节按钮
      主机：${LAN_IP}    端口：${CASTER_PORT}
      挂载点：AUTO       用户名：${USER_NAME}
      密码：${PASSWORD}
      协议：NTRIP Revision 1

 预期：
   · 定位面板出现经纬度，1 秒刷新 4 次
   · NTRIP 状态变「已连接」，↑↓ 字节数持续增长
   · 本终端每 90 秒会看到 caster 主动断链，App 应在
     5/10/20 秒后自动重连
   · 按 Ctrl+C 结束
=========================================================
EOF

wait
