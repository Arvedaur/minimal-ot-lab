# Asama 0 - Host Readiness Kontrolu
# Kurulum veya konfigurasyon DEGISTIRMEZ, sadece mevcut durumu raporlar.
# PowerShell'i "Yonetici olarak calistir" ile acmaniza gerek yok.

Write-Host "=== Docker ===" -ForegroundColor Cyan
docker version
docker compose version
docker info | Select-String "Server Version|Operating System|Kernel Version"

Write-Host "`n=== WSL2 ===" -ForegroundColor Cyan
wsl --status
wsl --version

Write-Host "`n=== Windows ===" -ForegroundColor Cyan
Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion, OsBuildNumber

Write-Host "`n=== Ag adaptorleri ===" -ForegroundColor Cyan
Get-NetAdapter | Select-Object Name, Status, LinkSpeed

Write-Host "`n=== hello-world testi ===" -ForegroundColor Cyan
docker run --rm hello-world

Write-Host "`n=== Mevcut Docker durumu ===" -ForegroundColor Cyan
docker ps -a
docker images
docker network ls
docker volume ls

Write-Host "`n=== KRITIK: Production OT izolasyon teyidi ===" -ForegroundColor Yellow
Write-Host "Asagidaki komutlarin ciktisini inceleyin ve bu laptop'un su anda"
Write-Host "hicbir production OT/SCADA VLAN'ina, sahadaki PLC'lere veya"
Write-Host "kurumsal historian'a BAGLI OLMADIGINI teyit edin:"
Get-NetIPConfiguration | Select-Object InterfaceAlias, IPv4Address, IPv4DefaultGateway
Write-Host "`nVPN/kurumsal ag baglantisi aktifse (Cisco AnyConnect, GlobalProtect vb.)"
Write-Host "bu labi baslatmadan once KAPATIN ve tekrar kontrol edin."
