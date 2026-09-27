FROM alpine:3.20

RUN apk add --no-cache iptables ip6tables iproute2 tcpdump bind-tools bash

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# NET_ADMIN + NET_RAW compose'da cap_add ile veriliyor (bkz. compose.yaml).
# Bu container kasitli olarak root calisir: iptables/tcpdump icin gereklidir,
# ama cap_drop: ALL + cap_add: [NET_ADMIN, NET_RAW] disinda hicbir capability
# tasimaz (Asama 10 hardening kabul kriteri).

ENTRYPOINT ["/entrypoint.sh"]
