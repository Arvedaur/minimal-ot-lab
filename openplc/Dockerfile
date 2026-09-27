# -----------------------------------------------------------------------
# ONEMLI KARAR NOTU (bkz. README.md "Karar Gerekli" bolumu):
#
# Dokumandaki "OpenPLC Runtime" referansi iki farkli, birbiriyle UYUMSUZ
# projeye isaret edebilir:
#
#   1) Autonomy-Logic/openplc-runtime (yeni v3 rewrite)
#      -> SADECE :8443 REST API sunar. Web UI YOK, Modbus TCP :502 YOK.
#      -> Bu plandaki FUXA/Telegraf Modbus okuma mimarisiyle UYUMSUZ.
#
#   2) thiagoralves/OpenPLC_v3 (klasik OpenPLC: webserver + runtime)
#      -> Web UI :8080 + Modbus TCP :502 sunar.
#      -> Register haritasi (40001-40005, 00001-00002) ve tum register-map
#         varsayimlari BU projeyle uyumludur.
#
# Bu Dockerfile klasik (2) projeyi kaynaktan derler, cunku Docker Hub'da
# guncel/resmi bir "openplc/openplc_v3" imaji artik yayinlanmiyor.
# Baslamadan once bunu dogrulayin; degistirmek isterseniz README'deki
# alternatifi (community image jpaffrath/docker-openplc) kullanin.
# -----------------------------------------------------------------------

FROM ubuntu:22.04 AS builder

ARG OPENPLC_REPO=https://github.com/thiagoralves/OpenPLC_v3.git
ARG OPENPLC_REF=master

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    git build-essential automake autoconf libtool pkg-config \
    bison flex python3 python3-pip python3-venv sqlite3 \
    ca-certificates cmake sudo \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN git clone --depth 1 --branch ${OPENPLC_REF} ${OPENPLC_REPO} OpenPLC_v3

WORKDIR /build/OpenPLC_v3
# ONEMLI: install.sh -> background_installer.sh, cikisini `tee install.log`'a
# PIPE EDIYOR ve pipefail KAPALI. Bu yuzden background_installer.sh icindeki
# "sudo make install" gibi adimlar (root container'da 'sudo' paketi kurulu
# olmadigi icin) SESSIZCE basarisiz olsa bile, pipeline'in exit kodu tee'den
# geldigi icin Docker build "basarili" gorunur - opendnp3/libmodbus/snap7
# hic /usr/local'a kurulmaz. Once 'sudo' paketini kurup (yukarida), sonra
# install.sh calistiktan SONRA kritik ciktilarin GERCEKTEN var oldugunu
# ayrica dogruluyoruz - dogrulama basarisiz olursa build BURADA patlar.
RUN chmod +x install.sh && ./install.sh linux
RUN set -e; \
    test -f webserver/iec2c || (echo "HATA: matiec (iec2c) kurulmamis"; exit 1); \
    test -f /usr/local/lib/libmodbus.so || (echo "HATA: libmodbus kurulmamis"; exit 1); \
    test -f /usr/local/lib/libopendnp3.so || (echo "HATA: opendnp3 kurulmamis"; exit 1); \
    test -f /usr/lib/libsnap7.so || (echo "HATA: libsnap7 kurulmamis"; exit 1); \
    test -f webserver/active_program || (echo "HATA: active_program (finalize_install) olusmamis"; exit 1); \
    echo "install.sh dogrulamasi basarili: tum kritik kutuphaneler ve dosyalar mevcut."

# -----------------------------------------------------------------------
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
# ONEMLI: OpenPLC, ST programini "Compile" dendiginde RUNTIME'DA (bu container
# icinde, her seferinde) C++'a cevirip derliyor (compile_program.sh -> g++/make).
# Bu yuzden final image sadece Python degil, TAM bir C/C++ toolchain de tasimali.
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip sqlite3 libssl3 ca-certificates \
    build-essential g++ make pkg-config \
  && rm -rf /var/lib/apt/lists/* \
  && useradd -m -u 10001 -s /usr/sbin/nologin openplc

# install.sh (builder stage) opendnp3/libmodbus/snap7'yi "make install" ile
# /usr/local'a kuruyor - compile_program.sh her ST derlemesinde bunlara
# (-lasiodnp3, -lmodbus, -lsnap7) LINK EDIYOR, opsiyonel degil. Bu yuzden
# /usr/local'i de builder'dan kopyalayip ldconfig ile linker cache'i
# yenilememiz sart.
COPY --from=builder /usr/local /usr/local
# install_libsnap7, diger ikisinden farkli olarak /usr/local'a DEGIL dogrudan
# /usr/lib'e kopyaliyor ("cp -f libsnap7.so /usr/lib") - onu ayrica aliyoruz.
COPY --from=builder /usr/lib/libsnap7.so /usr/lib/libsnap7.so
RUN ldconfig

# install.sh (builder stage) kurdugu paketleri kendi venv'ine koyar; bu final
# stage sistem python3'unu calistirdigi icin webserver'in gerektirdigi
# paketleri burada AYRICA kuruyoruz (bkz. background_installer.sh - ayni
# surumler pinlendi).
RUN pip3 install --no-cache-dir \
    flask==2.3.3 werkzeug==2.3.7 flask-login==0.6.2 pyserial \
    pymodbus==2.5.3 flask_jwt_extended flask_sqlalchemy python-dotenv

COPY --from=builder --chown=openplc:openplc /build/OpenPLC_v3 /workdir

# ONEMLI: webserver.py, "active_program" ve "./core/..." gibi dosyalari
# RELATIF yoldan acar (webserver/active_program repo'da hazir gelir, icinde
# "blank_program.st" yazar). Bu yuzden process'i /workdir'DAN DEGIL,
# /workdir/webserver ICINDEN calistirmak ZORUNLU - aksi halde run_http()
# thread'i "active_program" dosyasini bulamayip sessizce cokuyor ve dashboard
# (8080) hic acilmiyor, sadece REST API (8443) ayakta kaliyor.
WORKDIR /workdir/webserver
USER openplc

# webserver.py ayni anda iki thread acar: run_http -> dashboard/login (8080,
# HTTP), run_https -> OpenPLC Editor REST API (8443, HTTPS self-signed).
# Bizim icin onemli olan insan arayuzu/login = 8080.
EXPOSE 8080 8443 502

HEALTHCHECK --interval=30s --timeout=5s --retries=5 --start-period=20s \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/login', timeout=3)" || exit 1

CMD ["python3", "webserver.py"]
