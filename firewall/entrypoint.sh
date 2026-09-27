#!/bin/bash
# -----------------------------------------------------------------------
# Firewall/router container entrypoint
# Zorunlu transit: collection_net (Telegraf) <-> central_ot_net (InfluxDB)
# Politika: Bolum 7'deki tabloyu birebir uygular (default-deny + explicit allow)
# -----------------------------------------------------------------------
set -euo pipefail

COLLECTION_SUBNET="${COLLECTION_NET_SUBNET:-172.20.20.0/24}"
CENTRAL_SUBNET="${CENTRAL_OT_NET_SUBNET:-172.20.30.0/24}"
INFLUX_PORT=8086

log() { echo "[firewall-entrypoint] $*"; }

log "IP forwarding kontrolu: $(cat /proc/sys/net/ipv4/ip_forward)"

# Interface isimlerini VARSAYMIYORUZ (Docker network sirasi garanti degildir).
# Bunun yerine subnet bazli eslesme kullaniyoruz - bu daha guvenilir.
COLLECTION_IF=$(ip -o addr show | awk -v net="${COLLECTION_SUBNET%/*}" '$4 ~ /^172\.20\.20\./ {print $2; exit}')
CENTRAL_IF=$(ip -o addr show | awk '$4 ~ /^172\.20\.30\./ {print $2; exit}')
log "collection_net arayuzu: ${COLLECTION_IF:-bulunamadi}"
log "central_ot_net arayuzu: ${CENTRAL_IF:-bulunamadi}"

# InfluxDB'nin gercek container IP'sini Docker'in embedded DNS'inden coz
INFLUXDB_IP=""
for i in $(seq 1 15); do
  INFLUXDB_IP=$(getent hosts influxdb | awk '{print $1}' || true)
  [ -n "$INFLUXDB_IP" ] && break
  log "influxdb DNS cozulemedi, tekrar deneniyor ($i/15)..."
  sleep 2
done
if [ -z "$INFLUXDB_IP" ]; then
  log "HATA: influxdb servisi DNS ile cozulemedi. Cikiliyor."
  exit 1
fi
log "influxdb IP: ${INFLUXDB_IP}"

# --- Temizle ---
iptables -F
iptables -t nat -F
iptables -X 2>/dev/null || true

# --- Default-deny (Bolum 4 ve Bolum 7) ---
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT   # container'in kendi trafigi (DNS/log vb.)

# Loopback ve kendi container'ina yonelik trafik
iptables -A INPUT -i lo -j ACCEPT

# Kurulmus/iliskili oturumlara donus trafigi (Bolum 7 - "Herhangi -> Established/related")
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# ALLOW: Telegraf(collection_net) -> InfluxDB(central_ot_net):8086
iptables -A FORWARD -s "${COLLECTION_SUBNET}" -d "${INFLUXDB_IP}" -p tcp --dport ${INFLUX_PORT} \
  -m conntrack --ctstate NEW -j ACCEPT

# central_ot_net -> plc_net veya collection_net'e giden YENI baglanti YASAK
# (bu kural gereksiz gorunebilir cunku firewall zaten plc_net'e bagli degil,
#  ama collection_net -> central_ot_net disinda central_ot_net'ten geri
#  baslatilan hicbir yeni baglantiya izin vermemek icin defense-in-depth)
iptables -A FORWARD -s "${CENTRAL_SUBNET}" -m conntrack --ctstate NEW -j LOG --log-prefix "OTLAB-DENY-CENTRAL-INITIATED: "
iptables -A FORWARD -s "${CENTRAL_SUBNET}" -m conntrack --ctstate NEW -j DROP

# Diger her sey: logla ve dusur (default-deny izlenebilirligi)
iptables -A FORWARD -j LOG --log-prefix "OTLAB-DEFAULT-DENY: " --log-level 4
iptables -A FORWARD -j DROP

# --- NAT: DNAT + MASQUERADE ---
# Telegraf, firewall'in collection_net IP'sine baglanir; firewall bu trafigi
# influxdb:8086'ya yonlendirir (DNAT) ve central_ot_net tarafinda masquerade
# yapar (influxdb geri trafigi firewall'e route edebilsin diye ekstra route
# tanimlamaya gerek kalmaz).
iptables -t nat -A PREROUTING -p tcp --dport ${INFLUX_PORT} -j DNAT --to-destination "${INFLUXDB_IP}:${INFLUX_PORT}"
iptables -t nat -A POSTROUTING -d "${INFLUXDB_IP}" -p tcp --dport ${INFLUX_PORT} -j MASQUERADE

log "Kurallar uygulandi. Ozet:"
iptables -L -n -v --line-numbers
iptables -t nat -L -n -v --line-numbers

log "Firewall aktif. Loglar icin: docker exec otlab-firewall dmesg | grep OTLAB  (veya journalctl host'ta)"
log "PCAP icin: docker exec otlab-firewall tcpdump -i any -w /captures/<isim>.pcap"

# Container'i canli tut ve conntrack/log'u izlenebilir birak
tail -f /dev/null
