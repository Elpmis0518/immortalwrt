#!/usr/bin/env bash
set -euo pipefail

echo "=== Applying CatWrt v25.12 customization layer onto ImmortalWrt 25.12 ==="

# 1. Minimal surgical patch on config_generate (preserve ImmortalWrt 25.12 Kernel 6.12 / DSA / netifd logic)
CFG_GEN="package/base-files/files/bin/config_generate"
sed -i 's/192\.168\.1\.1/192.168.1.4/g' "$CFG_GEN"
sed -i "s/hostname='ImmortalWrt'/hostname='CatWrt'/g" "$CFG_GEN"
grep -E "192\.168\.1\.4|hostname='CatWrt'" "$CFG_GEN"

# 1b. Safeguard feeds/packages/lang/rust against expired Rust CI LLVM artifacts (404)
if [ -f feeds/packages/lang/rust/Makefile ]; then
    sed -i 's/download-ci-llvm=true/download-ci-llvm=false/g' feeds/packages/lang/rust/Makefile
fi

# 2. Create clean files/ overlay (never breaks upstream git tracking)
mkdir -p files/etc/uci-defaults \
         files/usr/bin \
         files/www/luci-static/argon/background

# 3. CatWrt ASCII banner & failsafe banner
cat <<'EOF' > files/etc/banner

     _____     _             _
    |     |___| |_ _ _ _ ___| |_
    |   --| .'|  _| | | |  _|  _|
    |_____|__,|_| |_____|_| |_|
   W I R E L E S S   F R E E D O M

======================================
        CatWrt.v25.12.mt798x
   ImmortalWrt 25.12 (LuCI2+nft+fw4)
           Blog: miaoer.net
 %D %V, %C
======================================
EOF

cat <<'EOF' > files/etc/banner.failsafe

     _____     _             _
    |     |___| |_ _ _ _ ___| |_
    |   --| .'|  _| | | |  _|  _|
    |_____|__,|_| |_____|_| |_|
   W I R E L E S S   F R E E D O M

======================================
        CatWrt.v25.12.mt798x
   ImmortalWrt 25.12 (LuCI2+nft+fw4)
           Blog: miaoer.net
 %D %V, %C

================= FAILSAFE MODE active ================
special commands:
* firstboot          reset settings to factory defaults
* mount_root         mount root-partition with config files

after mount_root:
* passwd             change root's password
* /etc/config        directory with config files

for more help see:
https://openwrt.org/docs/guide-user/troubleshooting/
- failsafe_and_factory_reset
- root_password_reset
=======================================================
EOF

# 4. CatWrt release metadata
cat <<'EOF' > files/etc/catwrt_release
version=v25.12
source=immortalwrt
arch=mt798x
stack=luci2-nft-fw4
customization=yes
EOF

# 5. CatWrt Argon Kami wallpaper (native to ImmortalWrt 25.12 luci-theme-argon v3.x)
if curl -fsSL --retry 3 --connect-timeout 15 \
    "https://cdn.miaoer.net/images/bg/kami/background.png" \
    -o files/www/luci-static/argon/background/background.png; then
    echo "Downloaded CatWrt Argon background ($(wc -c < files/www/luci-static/argon/background/background.png) bytes)"
else
    echo "Warning: failed to download Argon background, continuing with theme default"
    rm -f files/www/luci-static/argon/background/background.png
fi

# 6. CatWrt Network Diagnostics utility (catnd), adapted for ImmortalWrt release string
cat <<'EOF' > files/usr/bin/catnd
#!/bin/bash
# CatWrt Network Diagnostics by @miaoermua (adapted for ImmortalWrt 25.12)

if [ "$(id -u)" != "0" ]; then
    echo "Error: You must be root to run this script, please use root user"
    exit 1
fi

release=$(cat /etc/openwrt_release 2>/dev/null || true)
if ! echo "$release" | grep -qiE "OpenWrt|ImmortalWrt|CatWrt"; then
    echo "Abnormal system environment..."
    exit 1
fi

clear
cat /etc/banner
echo ""
echo "$(date) - Starting CatWrt Network Diagnostics"
echo ""

if ping -c 3 223.5.5.5 >/dev/null 2>&1; then
    echo "[Ping] Network connection succeeded!"
elif ping -c 3 119.29.29.99 >/dev/null 2>&1; then
    echo "[Ping] Network connection succeeded, but there may be problems!"
else
    pppoe_config=$(grep 'pppoe' /etc/config/network 2>/dev/null || true)
    if [ -n "$pppoe_config" ]; then
        echo "[PPPoE] Please check if your PPPoE account and password are correct."
    fi
    exit 1
fi

valid_dns="1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 223.6.6.6 223.5.5.5 180.76.76.76 208.67.222.222 208.67.220.220 119.29.29.99"
dns_config=$(grep 'option dns' /etc/config/network 2>/dev/null || true)
dns_servers=$(echo "$dns_config" | awk -F "'" '{print $2}')
for ip in $dns_servers; do
    if ! [[ $valid_dns =~ (^|[ ])$ip($|[ ]) ]]; then
        echo "[DNS] Recommended to check custom DNS $ip"
    fi
done

if ! nslookup bilibili.com >/dev/null 2>&1; then
    if nslookup www.miaoer.net >/dev/null 2>&1; then
        echo "[DNS] DNS resolution succeeded"
    else
        echo "[DNS] Your DNS server may have issues"
    fi
else
    echo "[DNS] DNS resolution succeeded"
fi

echo "CatWrt IPv4 Addr: $(curl --silent --connect-timeout 5 4.ipw.cn || echo N/A)"
if curl -fsS --connect-timeout 5 6.ipw.cn >/dev/null 2>&1; then
    echo "CatWrt IPv6 Addr: $(curl --silent --connect-timeout 5 6.ipw.cn)"
else
    echo "[IPv6] IPv6 network connection timed out"
fi

if ! grep -q '192.168.1.4' /etc/config/network 2>/dev/null; then
    echo "[Default-IP] LAN address is not CatWrt default 192.168.1.4"
fi

if command -v tcping >/dev/null 2>&1; then
    echo "[Tcping] Testing..."
    for host in cn.bing.com bilibili.com github.com google.com.hk; do
        tcping -q -c 1 "$host" || echo "Failed: $host"
    done
fi

echo ""
echo "$(date) - Network check completed"
echo "CatWrt Network Diagnostics by @miaoermua"
EOF
chmod +x files/usr/bin/catnd

# 7. Clean additive UCI defaults for ImmortalWrt 25.12 (LuCI2 + nft + fw4 + apk)
#    Complements ImmortalWrt's built-in 99-default-settings & 99-default-settings-chinese
cat <<'EOF' > files/etc/uci-defaults/99-catwrt-defaults
#!/bin/sh

uci -q get system.@catwrt_init[0] >/dev/null || uci -q add system catwrt_init >/dev/null

# Default LuCI2 theme (Argon) & Simplified Chinese
if ! uci -q get system.@catwrt_init[0].theme >/dev/null; then
	uci -q batch <<-UCI
		set luci.main.mediaurlbase='/luci-static/argon'
		set luci.main.lang='zh_cn'
		commit luci

		set system.@catwrt_init[0].theme='1'
		commit system
	UCI
fi

# CatWrt default root password ('password') only if root password is empty (strictly preserve 9 shadow fields)
if grep -qE '^root::0:0:99999:7:::|^root:::0:99999:7:::' /etc/shadow; then
	sed -i 's|^root::0:0:99999:7:::|root:$1$V4UetPzk$CYXluq4wUazHjmCDBCqXF.:0:0:99999:7:::|' /etc/shadow
	sed -i 's|^root:::0:99999:7:::|root:$1$V4UetPzk$CYXluq4wUazHjmCDBCqXF.:0:0:99999:7:::|' /etc/shadow
fi

# Enable Wi-Fi radios by default on first boot (CatWrt behavior)
if ! uci -q get system.@catwrt_init[0].wifi >/dev/null && [ -f /etc/config/wireless ]; then
	for radio in $(uci -q show wireless | sed -n 's/^wireless\.\([^.=]*\)=wifi-device$/\1/p'); do
		uci -q set "wireless.${radio}.disabled=0"
	done
	uci -q commit wireless
	uci -q set system.@catwrt_init[0].wifi='1'
	uci -q commit system
fi

# CatWrt release description (keep ImmortalWrt apk mirrors & fw4 intact)
sed -i '/DISTRIB_DESCRIPTION/d' /etc/openwrt_release
echo "DISTRIB_DESCRIPTION='CatWrt.v25.12.mt798x (ImmortalWrt) '" >> /etc/openwrt_release

rm -rf /tmp/luci-modulecache/ /tmp/luci-indexcache*

exit 0
EOF
chmod +x files/etc/uci-defaults/99-catwrt-defaults

echo "=== CatWrt customization layer applied cleanly ==="
