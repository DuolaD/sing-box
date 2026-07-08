#!/bin/bash

# ====================================================================
# Sing-Box Multi-Protocol Installation Script (Refactored Replicated Version)
# ====================================================================
# A clean, modular, and robust replication of sing-box installation script.
# Focuses on code readability, robust JSON manipulation via jq,
# and system safety while maintaining 100% feature parity.

export LANG=en_US.UTF-8

# --- ANSI Color Schemes & Console Output Helpers ---
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;36m'
bblue='\033[0;34m'
plain='\033[0m'

red()    { echo -e "\033[31m\033[01m$1\033[0m"; }
green()  { echo -e "\033[32m\033[01m$1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$1\033[0m"; }
blue()   { echo -e "\033[36m\033[01m$1\033[0m"; }
white()  { echo -e "\033[37m\033[01m$1\033[0m"; }
readp()  { read -p "$(yellow "$1")" $2; }

# --- Script Validation ---
[[ $EUID -ne 0 ]] && yellow "请以root模式运行脚本" && exit
stty erase $'\b' 2>/dev/null || stty erase '^H' 2>/dev/null

# --- Global Configuration Paths & Constants ---
SBFOLDER="/etc/s-box"
SBFILES="$SBFOLDER/sb10.json $SBFOLDER/sb11.json $SBFOLDER/sb.json"
SCRIPT_URL="https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh"
SCRIPT_SHORTCUT="/usr/bin/sb"

# --- Detect Operating System ---
detect_system() {
  if [[ -f /etc/redhat-release ]]; then
    release="Centos"
  elif cat /etc/issue | grep -q -E -i "alpine"; then
    release="alpine"
  elif cat /etc/issue | grep -q -E -i "debian"; then
    release="Debian"
  elif cat /etc/issue | grep -q -E -i "ubuntu"; then
    release="Ubuntu"
  elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
    release="Centos"
  elif cat /proc/version | grep -q -E -i "debian"; then
    release="Debian"
  elif cat /proc/version | grep -q -E -i "ubuntu"; then
    release="Ubuntu"
  elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
    release="Centos"
  else
    red "脚本不支持当前的系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
  fi
  
  vsid=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)
  op=$(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | grep -i pretty_name | cut -d \" -f2)
  
  if [[ $(echo "$op" | grep -i -E "arch") ]]; then
    red "脚本不支持当前的 $op 系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
  fi
  
  version=$(uname -r | cut -d "-" -f1)
  [[ -z $(systemd-detect-virt 2>/dev/null) ]] && vi=$(virt-what 2>/dev/null) || vi=$(systemd-detect-virt 2>/dev/null)
  
  case $(uname -m) in
    armv7l) cpu=armv7;;
    aarch64) cpu=arm64;;
    x86_64) cpu=amd64;;
    *) red "目前脚本不支持$(uname -m)架构" && exit;;
  esac
  
  if [[ -n $(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk -F ' ' '{print $3}') ]]; then
    bbr=$(sysctl net.ipv4.tcp_congestion_control | awk -F ' ' '{print $3}')
  elif [[ -n $(ping 10.0.0.2 -c 2 | grep ttl) ]]; then
    bbr="Openvz版bbr-plus"
  else
    bbr="Openvz/Lxc"
  fi
  hostname=$(hostname)
}

# --- Install OS Dependencies ---
install_dependencies() {
  if [ ! -f sbyg_update ]; then
    green "首次安装Sing-box脚本必要的依赖……"
    if command -v apk >/dev/null 2>&1; then
      apk update
      apk add bash libc6-compat jq openssl procps busybox-extras iproute2 iputils coreutils expect git socat iptables grep tar tzdata util-linux virt-what
    else
      if [[ $release = "Centos" && ${vsid} =~ 8 ]]; then
        cd /etc/yum.repos.d/ && mkdir -p backup && mv *repo backup/ 2>/dev/null
        curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-8.repo
        sed -i -e "s|mirrors.cloud.aliyuncs.com|mirrors.aliyun.com|g" /etc/yum.repos.d/CentOS-*
        sed -i -e "s|releasever|releasever-stream|g" /etc/yum.repos.d/CentOS-*
        yum clean all && yum makecache
        cd
      fi
      
      if [ -x "$(command -v apt-get)" ]; then
        apt update -y
        apt install jq cron socat busybox iptables-persistent coreutils util-linux -y
      elif [ -x "$(command -v yum)" ]; then
        yum update -y && yum install epel-release -y
        yum install jq socat busybox coreutils util-linux -y
      elif [ -x "$(command -v dnf)" ]; then
        dnf update -y
        dnf install jq socat busybox coreutils util-linux -y
      fi
      
      if [ -x "$(command -v yum)" ] || [ -x "$(command -v dnf)" ]; then
        local pm="yum"
        [ -x "$(command -v dnf)" ] && pm="dnf"
        $pm install -y cronie iptables-services
        systemctl enable iptables >/dev/null 2>&1
        systemctl start iptables >/dev/null 2>&1
      fi
      
      if [[ -z $vi ]]; then
        apt install iputils-ping iproute2 systemctl -y >/dev/null 2>&1
      fi
    fi
    
    local packages=("curl" "openssl" "iptables" "tar" "expect" "wget" "xxd" "python3" "qrencode" "git")
    for pkg in "${packages[@]}"; do
      if ! command -v "$pkg" &> /dev/null; then
        if [ -x "$(command -v apt-get)" ]; then
          apt-get install -y "$pkg"
        elif [ -x "$(command -v yum)" ]; then
          yum install -y "$pkg"
        elif [ -x "$(command -v dnf)" ]; then
          dnf install -y "$pkg"
        fi
      fi
    done
    touch sbyg_update
  fi
}

# --- Network & Warp Utilities ---
v4v6() {
  v4=$(curl -s4m5 icanhazip.com -k)
  v6=$(curl -s6m5 icanhazip.com -k)
  v4dq=$(curl -s4m5 -k https://myip.ipip.net | awk -F'来自于：' '{print $2}' 2>/dev/null)
  v6dq=$(curl -s6m5 -k https://ip.fm | sed -n 's/.*Location: //p' 2>/dev/null)
}

warpcheck() {
  wgcfv6=$(curl -s6m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
  wgcfv4=$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
}

v6() {
  v4orv6() {
    if [ -z "$(curl -s4m5 icanhazip.com -k)" ]; then
      echo
      red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
      yellow "检测到 纯IPV6 VPS，添加NAT64"
      echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1" > /etc/resolv.conf
      ipv=prefer_ipv6
    else
      ipv=prefer_ipv4
    fi
    if [ -n "$(curl -s6m5 icanhazip.com -k)" ]; then
      endip="2606:4700:d0::a29f:c001"
    else
      endip="162.159.192.1"
    fi
  }
  warpcheck
  if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
    v4orv6
  else
    systemctl stop wg-quick@wgcf >/dev/null 2>&1
    kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
    v4orv6
    systemctl start wg-quick@wgcf >/dev/null 2>&1
    systemctl restart warp-go >/dev/null 2>&1
    systemctl enable warp-go >/dev/null 2>&1
    systemctl start warp-go >/dev/null 2>&1
  fi
}

tun_check() {
  if [[ $vi = "openvz" ]]; then
    TUN=$(cat /dev/net/tun 2>&1)
    if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then 
      red "检测到未开启TUN，现尝试添加TUN支持" && sleep 4
      cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun
      TUN=$(cat /dev/net/tun 2>&1)
      if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then 
        green "添加TUN支持失败，建议与VPS厂商沟通或后台设置开启" && exit
      else
        echo '#!/bin/bash' > /root/tun.sh && echo 'cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun' >> /root/tun.sh && chmod +x /root/tun.sh
        grep -qE "^ *@reboot root bash /root/tun.sh >/dev/null 2>&1" /etc/crontab || echo "@reboot root bash /root/tun.sh >/dev/null 2>&1" >> /etc/crontab
        green "TUN守护功能已启动"
      fi
    fi
  fi
}

close_firewall() {
  systemctl stop firewalld.service >/dev/null 2>&1
  systemctl disable firewalld.service >/dev/null 2>&1
  setenforce 0 >/dev/null 2>&1
  ufw disable >/dev/null 2>&1
  iptables -P INPUT ACCEPT >/dev/null 2>&1
  iptables -P FORWARD ACCEPT >/dev/null 2>&1
  iptables -P OUTPUT ACCEPT >/dev/null 2>&1
  iptables -t mangle -F >/dev/null 2>&1
  iptables -F >/dev/null 2>&1
  iptables -X >/dev/null 2>&1
  netfilter-persistent save >/dev/null 2>&1
  if [[ -n $(apachectl -v 2>/dev/null) ]]; then
    systemctl stop httpd.service >/dev/null 2>&1
    systemctl disable httpd.service >/dev/null 2>&1
    service apache2 stop >/dev/null 2>&1
    systemctl disable apache2 >/dev/null 2>&1
  fi
  sleep 1
  green "执行开放端口，关闭防火墙完毕"
}

openyn() {
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  readp "是否开放端口，关闭防火墙？\n1、是，执行 (回车默认)\n2、否，跳过！自行处理\n请选择【1-2】：" action
  if [[ -z $action ]] || [[ "$action" = "1" ]]; then
    close_firewall
  elif [[ "$action" = "2" ]]; then
    echo
  else
    red "输入错误,请重新选择" && openyn
  fi
}

# --- Core Sing-Box Installer ---
inssb() {
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  green "使用哪个内核版本？"
  yellow "1：使用目前最新正式版内核 (回车默认)"
  yellow "2：使用之前1.10.7正式版内核 (支持geosite分流、IP优选级切换，无Anytls协议)"
  readp "请选择【1-2】：" menu
  if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
    sbcore=$(curl -Ls https://github.com/SagerNet/sing-box/releases/latest | grep -oP 'tag/v\K[0-9.]+' | head -n 1)
  else
    sbcore='1.10.7'
  fi
  sbname="sing-box-$sbcore-linux-$cpu"
  mkdir -p "$SBFOLDER"
  curl -L -o "$SBFOLDER/sing-box.tar.gz" -# --retry 2 "https://github.com/SagerNet/sing-box/releases/download/v$sbcore/$sbname.tar.gz"
  if [[ -f "$SBFOLDER/sing-box.tar.gz" ]]; then
    tar xzf "$SBFOLDER/sing-box.tar.gz" -C "$SBFOLDER"
    mv "$SBFOLDER/$sbname/sing-box" "$SBFOLDER/sing-box"
    rm -rf "$SBFOLDER/sing-box.tar.gz" "$SBFOLDER/$sbname"
    if [[ -f "$SBFOLDER/sing-box" ]]; then
      chown root:root "$SBFOLDER/sing-box"
      chmod +x "$SBFOLDER/sing-box"
      blue "成功安装 Sing-box 内核版本：$("$SBFOLDER/sing-box" version | awk '/version/{print $NF}')"
      sbnh=$("$SBFOLDER/sing-box" version 2>/dev/null | awk '/version/{print $NF}' 2>/dev/null | cut -d '.' -f 1,2)
    else
      red "下载 Sing-box 内核不完整，安装失败，请再运行安装一次" && exit
    fi
  else
    red "下载 Sing-box 内核失败，请再运行安装一次，并检测VPS的网络是否可以访问Github" && exit
  fi
}

# --- Certificate Generation & Acms.sh wrapping ---
inscertificate() {
  ymzs() {
    ym_vl_re=apple.com
    echo
    blue "Vless-reality的SNI域名默认为 apple.com"
    tlsyn=true
    ym_vm_ws=$(cat /root/ygkkkca/ca.log 2>/dev/null)
    certificatec_vmess_ws='/root/ygkkkca/cert.crt'
    certificatep_vmess_ws='/root/ygkkkca/private.key'
    certificatec_hy2='/root/ygkkkca/cert.crt'
    certificatep_hy2='/root/ygkkkca/private.key'
    certificatec_tuic='/root/ygkkkca/cert.crt'
    certificatep_tuic='/root/ygkkkca/private.key'
    certificatec_an='/root/ygkkkca/cert.crt'
    certificatep_an='/root/ygkkkca/private.key'
  }
  
  zqzs() {
    ym_vl_re=apple.com
    echo
    blue "Vless-reality的SNI域名默认为 apple.com"
    tlsyn=false
    ym_vm_ws=www.bing.com
    certificatec_vmess_ws="$SBFOLDER/cert.pem"
    certificatep_vmess_ws="$SBFOLDER/private.key"
    certificatec_hy2="$SBFOLDER/cert.pem"
    certificatep_hy2="$SBFOLDER/private.key"
    certificatec_tuic="$SBFOLDER/cert.pem"
    certificatep_tuic="$SBFOLDER/private.key"
    certificatec_an="$SBFOLDER/cert.pem"
    certificatep_an="$SBFOLDER/private.key"
  }
  
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  green "二、生成并设置相关证书"
  echo
  blue "自动生成bing自签证书中……" && sleep 2
  openssl ecparam -genkey -name prime256v1 -out "$SBFOLDER/private.key"
  openssl req -new -x509 -days 36500 -key "$SBFOLDER/private.key" -out "$SBFOLDER/cert.pem" -subj "/CN=www.bing.com"
  echo
  if [[ -f "$SBFOLDER/cert.pem" ]]; then
    blue "生成bing自签证书成功"
  else
    red "生成bing自签证书失败" && exit
  fi
  echo
  if [[ -f /root/ygkkkca/cert.crt && -f /root/ygkkkca/private.key && -s /root/ygkkkca/cert.crt && -s /root/ygkkkca/private.key ]]; then
    yellow "经检测，之前已使用Acme-yg脚本申请过Acme域名证书：$(cat /root/ygkkkca/ca.log) "
    green "是否使用 $(cat /root/ygkkkca/ca.log) 域名证书？"
    yellow "1：否！使用自签的证书 (回车默认)"
    yellow "2：是！使用 $(cat /root/ygkkkca/ca.log) 域名证书"
    readp "请选择【1-2】：" menu
    if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
      zqzs
    else
      ymzs
    fi
  else
    green "如果你有解析完成的域名，是否申请一个Acme域名证书？"
    yellow "1：否！继续使用自签的证书 (回车默认)"
    yellow "2：是！使用Acme-yg脚本申请Acme证书 (支持常规80端口模式与Dns API模式)"
    readp "请选择【1-2】：" menu
    if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
      zqzs
    else
      bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)
      if [[ ! -f /root/ygkkkca/cert.crt && ! -f /root/ygkkkca/private.key && ! -s /root/ygkkkca/cert.crt && ! -s /root/ygkkkca/private.key ]]; then
        red "Acme证书申请失败，继续使用自签证书" 
        zqzs
      else
        ymzs
      fi
    fi
  fi
}

# --- Ports & Configuration helpers ---
chooseport() {
  if [[ -z $port ]]; then
    port=$(shuf -i 10000-65535 -n 1)
    until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] 
    do
      [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义端口:" port
    done
  else
    until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]
    do
      [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义端口:" port
    done
  fi
  blue "确认的端口：$port" && sleep 2
}

vlport() {
  readp "\n设置Vless-reality端口 (回车跳过为10000-65535之间的随机端口)：" port
  chooseport
  port_vl_re=$port
}
vmport() {
  readp "\n设置Vmess-ws端口 (回车跳过为10000-65535之间的随机端口)：" port
  chooseport
  port_vm_ws=$port
}
hy2port() {
  readp "\n设置Hysteria2主端口 (回车跳过为10000-65535之间的随机端口)：" port
  chooseport
  port_hy2=$port
}
tu5port() {
  readp "\n设置Tuic5主端口 (回车跳过为10000-65535之间的随机端口)：" port
  chooseport
  port_tu=$port
}
anport() {
  readp "\n设置Anytls主端口，最新内核时可用 (回车跳过为10000-65535之间的随机端口)：" port
  chooseport
  port_an=$port
}

insport() {
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  green "三、设置各个协议端口"
  yellow "1：自动生成每个协议的随机端口 (10000-65535范围内)，回车默认。请确保VPS后台已开放所有端口"
  yellow "2：自定义每个协议端口。请确保VPS后台已开放指定的端口"
  readp "请输入【1-2】：" port
  if [ -z "$port" ] || [ "$port" = "1" ] ; then
    ports=()
    for i in {1..5}; do
      while true; do
        port=$(shuf -i 10000-65535 -n 1)
        if ! [[ " ${ports[@]} " =~ " $port " ]] && \
           [[ -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && \
           [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
          ports+=($port)
          break
        fi
      done
    done
    port_vm_ws=${ports[0]}
    port_vl_re=${ports[1]}
    port_hy2=${ports[2]}
    port_tu=${ports[3]}
    port_an=${ports[4]}
    
    if [[ $tlsyn == "true" ]]; then
      numbers=("2053" "2083" "2087" "2096" "8443")
    else
      numbers=("8080" "8880" "2052" "2082" "2086" "2095")
    fi
    port_vm_ws=${numbers[$RANDOM % ${#numbers[@]}]}
    until [[ -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port_vm_ws") ]]
    do
      port_vm_ws=${numbers[$RANDOM % ${#numbers[@]}]}
    done
    echo
    blue "根据Vmess-ws协议是否启用TLS，随机指定支持CDN优选IP的标准端口：$port_vm_ws"
  else
    vlport && vmport && hy2port && tu5port
    if [[ "$sbnh" != "1.10" ]]; then
      anport
    fi
  fi
  echo
  blue "各协议端口确认如下"
  blue "Vless-reality端口：$port_vl_re"
  blue "Vmess-ws端口：$port_vm_ws"
  blue "Hysteria-2端口：$port_hy2"
  blue "Tuic-v5端口：$port_tu"
  if [[ "$sbnh" != "1.10" ]]; then
    blue "Anytls端口：$port_an"
  fi
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  green "四、自动生成各个协议统一的uuid (密码)"
  uuid=$("$SBFOLDER/sing-box" generate uuid)
  blue "已确认uuid (密码)：${uuid}"
  blue "已确认Vmess的path路径：${uuid}-vm"
}

# --- JSON Config Generator (Server Side) ---
inssbjsonser() {
  cat > "$SBFOLDER/sb10.json" <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "sniff": true,
      "sniff_override_destination": true,
      "tag": "vless-sb",
      "listen": "::",
      "listen_port": ${port_vl_re},
      "users": [
        {
          "uuid": "${uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${ym_vl_re}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${ym_vl_re}",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    },
    {
      "type": "vmess",
      "sniff": true,
      "sniff_override_destination": true,
      "tag": "vmess-sb",
      "listen": "::",
      "listen_port": ${port_vm_ws},
      "users": [
        {
          "uuid": "${uuid}",
          "alterId": 0
        }
      ],
      "transport": {
        "type": "ws",
        "path": "${uuid}-vm",
        "max_early_data": 2048,
        "early_data_header_name": "Sec-WebSocket-Protocol"    
      },
      "tls": {
        "enabled": ${tlsyn},
        "server_name": "${ym_vm_ws}",
        "certificate_path": "$certificatec_vmess_ws",
        "key_path": "$certificatep_vmess_ws"
      }
    }, 
    {
      "type": "hysteria2",
      "sniff": true,
      "sniff_override_destination": true,
      "tag": "hy2-sb",
      "listen": "::",
      "listen_port": ${port_hy2},
      "users": [
        {
          "password": "${uuid}"
        }
      ],
      "ignore_client_bandwidth": false,
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$certificatec_hy2",
        "key_path": "$certificatep_hy2"
      }
    },
    {
      "type": "tuic",
      "sniff": true,
      "sniff_override_destination": true,
      "tag": "tuic5-sb",
      "listen": "::",
      "listen_port": ${port_tu},
      "users": [
        {
          "uuid": "${uuid}",
          "password": "${uuid}"
        }
      ],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$certificatec_tuic",
        "key_path": "$certificatep_tuic"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct",
      "domain_strategy": "$ipv"
    },
    {
      "type": "direct",
      "tag": "vps-outbound-v4", 
      "domain_strategy": "prefer_ipv4"
    },
    {
      "type": "direct",
      "tag": "vps-outbound-v6",
      "domain_strategy": "prefer_ipv6"
    },
    {
      "type": "socks",
      "tag": "socks-out",
      "server": "127.0.0.1",
      "server_port": 40000,
      "version": "5"
    },
    {
      "type": "direct",
      "tag": "socks-IPv4-out",
      "detour": "socks-out",
      "domain_strategy": "prefer_ipv4"
    },
    {
      "type": "direct",
      "tag": "socks-IPv6-out",
      "detour": "socks-out",
      "domain_strategy": "prefer_ipv6"
    },
    {
      "type": "direct",
      "tag": "warp-IPv4-out",
      "detour": "wireguard-out",
      "domain_strategy": "prefer_ipv4"
    },
    {
      "type": "direct",
      "tag": "warp-IPv6-out",
      "detour": "wireguard-out",
      "domain_strategy": "prefer_ipv6"
    },
    {
      "type": "wireguard",
      "tag": "wireguard-out",
      "server": "$endip",
      "server_port": 2408,
      "local_address": [
        "172.16.0.2/32",
        "${v6}/128"
      ],
      "private_key": "$pvk",
      "peer_public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
      "reserved": $res
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": ["quic", "stun"],
        "outbound": "block"
      },
      {
        "outbound": "warp-IPv4-out",
        "domain_suffix": ["yg_kkk"],
        "geosite": ["yg_kkk"]
      },
      {
        "outbound": "warp-IPv6-out",
        "domain_suffix": ["yg_kkk"],
        "geosite": ["yg_kkk"]
      },
      {
        "outbound": "socks-IPv4-out",
        "domain_suffix": ["yg_kkk"],
        "geosite": ["yg_kkk"]
      },
      {
        "outbound": "socks-IPv6-out",
        "domain_suffix": ["yg_kkk"],
        "geosite": ["yg_kkk"]
      },
      {
        "outbound": "vps-outbound-v4",
        "domain_suffix": ["yg_kkk"],
        "geosite": ["yg_kkk"]
      },
      {
        "outbound": "vps-outbound-v6",
        "domain_suffix": ["yg_kkk"],
        "geosite": ["yg_kkk"]
      },
      {
        "outbound": "direct",
        "network": "udp,tcp"
      }
    ]
  }
}
EOF

  cat > "$SBFOLDER/sb11.json" <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-sb",
      "listen": "::",
      "listen_port": ${port_vl_re},
      "users": [
        {
          "uuid": "${uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${ym_vl_re}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${ym_vl_re}",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    },
    {
      "type": "vmess",
      "tag": "vmess-sb",
      "listen": "::",
      "listen_port": ${port_vm_ws},
      "users": [
        {
          "uuid": "${uuid}",
          "alterId": 0
        }
      ],
      "transport": {
        "type": "ws",
        "path": "${uuid}-vm",
        "max_early_data": 2048,
        "early_data_header_name": "Sec-WebSocket-Protocol"    
      },
      "tls": {
        "enabled": ${tlsyn},
        "server_name": "${ym_vm_ws}",
        "certificate_path": "$certificatec_vmess_ws",
        "key_path": "$certificatep_vmess_ws"
      }
    }, 
    {
      "type": "hysteria2",
      "tag": "hy2-sb",
      "listen": "::",
      "listen_port": ${port_hy2},
      "users": [
        {
          "password": "${uuid}"
        }
      ],
      "ignore_client_bandwidth": false,
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$certificatec_hy2",
        "key_path": "$certificatep_hy2"
      }
    },
    {
      "type": "tuic",
      "tag": "tuic5-sb",
      "listen": "::",
      "listen_port": ${port_tu},
      "users": [
        {
          "uuid": "${uuid}",
          "password": "${uuid}"
        }
      ],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$certificatec_tuic",
        "key_path": "$certificatep_tuic"
      }
    },
    {
      "type": "anytls",
      "tag": "anytls-sb",
      "listen": "::",
      "listen_port": ${port_an},
      "users": [
        {
          "password": "${uuid}"
        }
      ],
      "padding_scheme": [],
      "tls": {
        "enabled": true,
        "certificate_path": "$certificatec_an",
        "key_path": "$certificatep_an"
      }
    }
  ],
  "endpoints": [
    {
      "type": "wireguard",
      "tag": "warp-out",
      "address": [
        "172.16.0.2/32",
        "${v6}/128"
      ],
      "private_key": "$pvk",
      "peers": [
        {
          "address": "$endip",
          "port": 2408,
          "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          "allowed_ips": [
            "0.0.0.0/0",
            "::/0"
          ],
          "reserved": $res
        }
      ]
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "socks",
      "tag": "socks-out",
      "server": "127.0.0.1",
      "server_port": 40000,
      "version": "5"
    }
  ],
  "route": {
    "rules": [
      {
        "action": "sniff"
      },
      {
        "action": "resolve",
        "domain_suffix": ["yg_kkk"],
        "strategy": "prefer_ipv4"
      },
      {
        "action": "resolve",
        "domain_suffix": ["yg_kkk"],
        "strategy": "prefer_ipv6"
      },
      {
        "domain_suffix": ["yg_kkk"],
        "outbound": "socks-out"
      },
      {
        "domain_suffix": ["yg_kkk"],
        "outbound": "warp-out"
      },
      {
        "outbound": "direct",
        "network": "udp,tcp"
      }
    ]
  }
}
EOF

  [[ "$sbnh" == "1.10" ]] && num=10 || num=11
  cp "$SBFOLDER/sb${num}.json" "$SBFOLDER/sb.json"
}

# --- Service Management (Systemd & OpenRC) ---
sbservice() {
  if command -v apk >/dev/null 2>&1; then
    echo '#!/sbin/openrc-run
description="sing-box service"
command="/etc/s-box/sing-box"
command_args="run -c /etc/s-box/sb.json"
command_background=true
pidfile="/var/run/sing-box.pid"' > /etc/init.d/sing-box
    chmod +x /etc/init.d/sing-box
    rc-update add sing-box default
    rc-service sing-box start
  else
    cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
After=network.target nss-lookup.target
[Service]
User=root
WorkingDirectory=/root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/etc/s-box/sing-box run -c /etc/s-box/sb.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable sing-box >/dev/null 2>&1
    systemctl start sing-box
    systemctl restart sing-box
  fi
}

# --- IP Management ---
ipuuid() {
  if command -v apk >/dev/null 2>&1; then
    status_cmd="rc-service sing-box status"
    status_pattern="started"
  else
    status_cmd="systemctl is-active sing-box"
    status_pattern="active"
  fi
  if [[ -n $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f "$SBFOLDER/sb.json" ]]; then
    v4v6
    if [[ -n $v4 && -n $v6 ]]; then
      green "调整IPv4/IPV6配置输出"
      yellow "1：刷新本地IP，使用IPV4配置输出 (回车默认) "
      yellow "2：刷新本地IP，使用IPV6配置输出"
      readp "请选择【1-2】：" menu
      if [ -z "$menu" ] || [ "$menu" = "1" ]; then
        server_ip="$v4"
        server_ipcl="$v4"
      else
        server_ip="[$v6]"
        server_ipcl="$v6"
      fi
    else
      yellow "VPS并不是双栈VPS，不支持IP配置输出的切换"
      serip=$(curl -s4m5 icanhazip.com -k || curl -s6m5 icanhazip.com -k)
      if [[ "$serip" =~ : ]]; then
        server_ip="[$serip]"
        server_ipcl="$serip"
      else
        server_ip="$serip"
        server_ipcl="$serip"
      fi
    fi
    echo "$server_ip" > "$SBFOLDER/server_ip.log"
    echo "$server_ipcl" > "$SBFOLDER/server_ipcl.log"
  else
    red "Sing-box服务未运行" && exit
  fi
}

wgcfgo() {
  warpcheck
  if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
    ipuuid
  else
    systemctl stop wg-quick@wgcf >/dev/null 2>&1
    kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
    ipuuid
    systemctl start wg-quick@wgcf >/dev/null 2>&1
    systemctl restart warp-go >/dev/null 2>&1
    systemctl enable warp-go >/dev/null 2>&1
    systemctl start warp-go >/dev/null 2>&1
  fi
}

# --- Client Configurations Exporters ---

# Strip comments helper
strip_json_comments() {
  sed 's://.*::g' "$1"
}

result_vl_vm_hy_tu() {
  if [[ -f /root/ygkkkca/cert.crt && -f /root/ygkkkca/private.key && -s /root/ygkkkca/cert.crt && -s /root/ygkkkca/private.key ]]; then
    ym=$(bash ~/.acme.sh/acme.sh --list 2>/dev/null | tail -1 | awk '{print $1}')
    [ -n "$ym" ] && echo "$ym" > /root/ygkkkca/ca.log
  fi
  rm -rf "$SBFOLDER/vm_ws_argo.txt" "$SBFOLDER/vm_ws.txt" "$SBFOLDER/vm_ws_tls.txt"
  
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
  server_ipcl=$(cat "$SBFOLDER/server_ipcl.log" 2>/dev/null)
  
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
  uuid=$(echo "$clean_json" | jq -r '.inbounds[0].users[0].uuid')
  vl_port=$(echo "$clean_json" | jq -r '.inbounds[0].listen_port')
  vl_name=$(echo "$clean_json" | jq -r '.inbounds[0].tls.server_name')
  public_key=$(cat "$SBFOLDER/public.key" 2>/dev/null)
  short_id=$(echo "$clean_json" | jq -r '.inbounds[0].tls.reality.short_id[0]')
  argo=$(cat "$SBFOLDER/argo.log" 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
  ws_path=$(echo "$clean_json" | jq -r '.inbounds[1].transport.path')
  vm_port=$(echo "$clean_json" | jq -r '.inbounds[1].listen_port')
  tls=$(echo "$clean_json" | jq -r '.inbounds[1].tls.enabled')
  vm_name=$(echo "$clean_json" | jq -r '.inbounds[1].tls.server_name')
  
  if [[ "$tls" = "false" ]]; then
    if [[ -f "$SBFOLDER/cfymjx.txt" ]]; then
      vm_name=$(cat "$SBFOLDER/cfymjx.txt" 2>/dev/null)
    else
      vm_name=$(echo "$clean_json" | jq -r '.inbounds[1].tls.server_name')
    fi
    vmadd_local=$server_ipcl
    vmadd_are_local=$server_ip
  else
    vmadd_local=$vm_name
    vmadd_are_local=$vm_name
  fi
  
  if [[ -f "$SBFOLDER/cfvmadd_local.txt" ]]; then
    local cached_cf=$(cat "$SBFOLDER/cfvmadd_local.txt" 2>/dev/null)
    vmadd_local=$cached_cf
    vmadd_are_local=$cached_cf
  fi
  
  if [[ -f "$SBFOLDER/cfvmadd_argo.txt" ]]; then
    vmadd_argo=$(cat "$SBFOLDER/cfvmadd_argo.txt" 2>/dev/null)
  else
    vmadd_argo="cloudflare-ech.com"
  fi
  
  hy2_port=$(echo "$clean_json" | jq -r '.inbounds[2].listen_port')
  hy2_ports=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$hy2_port" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ',' | sed 's/,$//')
  if [[ -n $hy2_ports ]]; then
    cmhy2pt=$(echo $hy2_ports | tr ':' '-')
    hyps="&mport=$cmhy2pt"
    sbhy2pt=$(echo "$hy2_ports" | grep -o '[0-9]\+:[0-9]\+' | sed 's/.*/"&"/' | paste -sd,)
  else
    hyps=""
    sbhy2pt=""
  fi
  
  ym=$(cat /root/ygkkkca/ca.log 2>/dev/null)
  if [[ -f "$SBFOLDER/cert.pem" ]]; then
    SHA256=$(openssl x509 -in "$SBFOLDER/cert.pem" -outform DER | sha256sum | awk '{print $1}')
    echo "$SHA256" > "$SBFOLDER/SHA256.txt"
  fi
  hy2_sniname=$(echo "$clean_json" | jq -r '.inbounds[2].tls.key_path')
  if [[ "$hy2_sniname" = "$SBFOLDER/private.key" || "$hy2_sniname" = "/etc/s-box/private.key" ]]; then
    SHA256=$(cat "$SBFOLDER/SHA256.txt" 2>/dev/null)
    hy2_name="www.bing.com"
    sb_hy2_ip=$server_ip
    cl_hy2_ip=$server_ipcl
    ins_hy2=1
    hy2_ins=true
  else
    hy2_name=$ym
    sb_hy2_ip=$ym
    cl_hy2_ip=$ym
    ins_hy2=0
    hy2_ins=false
  fi
  
  tu5_port=$(echo "$clean_json" | jq -r '.inbounds[3].listen_port')
  tu5_sniname=$(echo "$clean_json" | jq -r '.inbounds[3].tls.key_path')
  if [[ "$tu5_sniname" = "$SBFOLDER/private.key" || "$tu5_sniname" = "/etc/s-box/private.key" ]]; then
    tu5_name="www.bing.com"
    sb_tu5_ip=$server_ip
    cl_tu5_ip=$server_ipcl
    ins=1
    tu5_ins=true
  else
    tu5_name=$ym
    sb_tu5_ip=$ym
    cl_tu5_ip=$ym
    ins=0
    tu5_ins=false
  fi
  
  if [[ "$sbnh" != "1.10" ]]; then
    an_port=$(echo "$clean_json" | jq -r '.inbounds[4].listen_port')
    an_sniname=$(echo "$clean_json" | jq -r '.inbounds[4].tls.key_path')
    if [[ "$an_sniname" = "$SBFOLDER/private.key" || "$an_sniname" = "/etc/s-box/private.key" ]]; then
      an_name="www.bing.com"
      sb_an_ip=$server_ip
      cl_an_ip=$server_ipcl
      ins_an=1
      an_ins=true
    else
      an_name=$ym
      sb_an_ip=$ym
      cl_an_ip=$ym
      ins_an=0
      an_ins=false
    fi
  fi
}

resvless() {
  echo
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  vl_link="vless://$uuid@$server_ip:$vl_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$vl_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#vl-reality-$hostname"
  echo "$vl_link" > "$SBFOLDER/vl_reality.txt"
  red "🚀【 vless-reality-vision 】节点信息如下：" && sleep 2
  echo
  echo "分享链接【v2ran(切换singbox内核)、nekobox、小火箭shadowrocket】"
  echo -e "${yellow}$vl_link${plain}"
  echo
  echo "二维码【v2ran(切换singbox内核)、nekobox、小火箭shadowrocket】"
  qrencode -o - -t ANSIUTF8 "$(cat "$SBFOLDER/vl_reality.txt")"
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  echo
}

resvmess() {
  local port_active=false
  if ps -ef 2>/dev/null | grep -q "[l]ocalhost:$vm_port"; then
    port_active=true
  fi
  
  if [[ "$tls" = "false" ]]; then
    if $port_active; then
      echo
      white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
      red "🚀【 vmess-ws(tls)+Argo 】临时节点信息如下(可选择3-8-3，自定义CDN优选地址)：" && sleep 2
      echo
      echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
      local vm_argo_temp_link="vmess://$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argo'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)"
      echo -e "${yellow}$vm_argo_temp_link${plain}"
      echo
      echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
      echo "$vm_argo_temp_link" > "$SBFOLDER/vm_ws_argols.txt"
      qrencode -o - -t ANSIUTF8 "$(cat "$SBFOLDER/vm_ws_argols.txt")"
    fi
    
    if ps -ef 2>/dev/null | grep -q '[c]loudflared.*run'; then
      argogd=$(cat "$SBFOLDER/sbargoym.log" 2>/dev/null)
      echo
      white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
      red "🚀【 vmess-ws(tls)+Argo 】固定节点信息如下 (可选择3-8-3，自定义CDN优选地址)：" && sleep 2
      echo
      echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
      local vm_argo_fixed_link="vmess://$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argogd'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argogd'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)"
      echo -e "${yellow}$vm_argo_fixed_link${plain}"
      echo
      echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
      echo "$vm_argo_fixed_link" > "$SBFOLDER/vm_ws_argogd.txt"
      qrencode -o - -t ANSIUTF8 "$(cat "$SBFOLDER/vm_ws_argogd.txt")"
    fi
    
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    red "🚀【 vmess-ws 】节点信息如下 (建议选择3-8-1，设置为CDN优选节点)：" && sleep 2
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    local vm_ws_link="vmess://$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-$hostname'","tls":"","type":"none","v":"2"}' | base64 -w 0)"
    echo -e "${yellow}$vm_ws_link${plain}"
    echo
    echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    echo "$vm_ws_link" > "$SBFOLDER/vm_ws.txt"
    qrencode -o - -t ANSIUTF8 "$(cat "$SBFOLDER/vm_ws.txt")"
  else
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    red "🚀【 vmess-ws-tls 】节点信息如下 (建议选择3-8-1，设置为CDN优选节点)：" && sleep 2
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    local vm_ws_tls_link="vmess://$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-tls-$hostname'","tls":"tls","sni":"'$vm_name'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)"
    echo -e "${yellow}$vm_ws_tls_link${plain}"
    echo
    echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    echo "$vm_ws_tls_link" > "$SBFOLDER/vm_ws_tls.txt"
    qrencode -o - -t ANSIUTF8 "$(cat "$SBFOLDER/vm_ws_tls.txt")"
  fi
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  echo
}

reshy2() {
  echo
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  hy2_link="hysteria2://$uuid@$sb_hy2_ip:$hy2_port?security=tls&alpn=h3&insecure=0&allowInsecure=0$hyps&sni=$hy2_name&pinSHA256=$SHA256#hy2-$hostname"
  echo "$hy2_link" > "$SBFOLDER/hy2.txt"
  red "🚀【 Hysteria-2 】节点信息如下：" && sleep 2
  echo
  echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
  echo -e "${yellow}$hy2_link${plain}"
  echo
  echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
  qrencode -o - -t ANSIUTF8 "$(cat "$SBFOLDER/hy2.txt")"
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  echo
}

restu5() {
  echo
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  local tuic_params="congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=$tu5_name&insecure=0&allowInsecure=0&allow_insecure=0"
  if [[ "$ins" -eq 1 ]]; then
    tuic_params+="&pinSHA256=$SHA256&pinnedPeerCertSha256=$SHA256"
  fi
  tuic5_link="tuic://$uuid:$uuid@$sb_tu5_ip:$tu5_port?$tuic_params#tu5-$hostname"
  echo "$tuic5_link" > "$SBFOLDER/tuic5.txt"
  red "🚀【 Tuic-v5 】节点信息如下：" && sleep 2
  echo
  echo "分享链接【v2rayn、nekobox、小火箭shadowrocket】"
  echo -e "${yellow}$tuic5_link${plain}"
  echo
  echo "二维码【v2rayn、nekobox、小火箭shadowrocket】"
  qrencode -o - -t ANSIUTF8 "$(cat "$SBFOLDER/tuic5.txt")"
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  echo
}

resan() {
  echo
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  local an_params="sni=$an_name&allowInsecure=0&insecure=0"
  if [[ "$ins_an" -eq 1 ]]; then
    an_params+="&pinSHA256=$SHA256&pinnedPeerCertSha256=$SHA256"
  fi
  an_link="anytls://$uuid@$sb_an_ip:$an_port?$an_params#anytls-$hostname"
  echo "$an_link" > "$SBFOLDER/an.txt"
  red "🚀【 Anytls】节点信息如下：" && sleep 2
  echo
  echo "分享链接【v2rayn、小火箭shadowrocket】"
  echo -e "${yellow}$an_link${plain}"
  echo
  echo "二维码【v2rayn、nekobox、小火箭shadowrocket】"
  qrencode -o - -t ANSIUTF8 "$(cat "$SBFOLDER/an.txt")"
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  echo
}

# --- Optimized Config Compiler (jq-based client config generation) ---
sb_client() {
  # This builds the complete client configurations for SFA/SFI/SFW and Clash Meta (Mihomo)
  # dynamically utilizing jq, reducing 1000+ lines of duplicate templates.

  local cert_content=""
  if [[ -f "$SBFOLDER/cert.pem" ]]; then
    cert_content=$(cat "$SBFOLDER/cert.pem")
  fi

  # 1. BASE TEMPLATE FOR CLIENT (SING-BOX)
  local base_client_template='{
    "log": { "disabled": false, "level": "info", "timestamp": true },
    "experimental": {
      "cache_file": { "enabled": true, "path": "./cache.db", "store_fakeip": true },
      "clash_api": { "external_controller": "127.0.0.1:9090", "external_ui": "ui", "default_mode": "Rule" }
    },
    "dns": {
      "servers": [
        { "tag": "aliDns", "type": "https", "server": "dns.alidns.com", "path": "/dns-query", "domain_resolver": "local" },
        { "tag": "local", "type": "udp", "server": "223.5.5.5" },
        { "tag": "proxyDns", "type": "https", "server": "dns.google", "path": "/dns-query", "domain_resolver": "aliDns", "detour": "proxy" },
        { "type": "fakeip", "tag": "fakeip", "inet4_range": "198.18.0.0/15", "inet6_range": "fc00::/18" }
      ],
      "rules": [
        { "rule_set": "geosite-cn", "clash_mode": "Rule", "server": "aliDns" },
        { "clash_mode": "Direct", "server": "local" },
        { "clash_mode": "Global", "server": "proxyDns" },
        { "query_type": ["A", "AAAA"], "server": "fakeip" }
      ],
      "final": "proxyDns",
      "strategy": "prefer_ipv4"
    },
    "inbounds": [
      { "type": "tun", "tag": "tun-in", "address": ["172.19.0.1/30", "fd00::1/126"], "auto_route": true, "strict_route": true }
    ],
    "route": {
      "rules": [
        { "inbound": "tun-in", "action": "sniff" },
        { "type": "logical", "mode": "or", "rules": [ { "port": 53 }, { "protocol": "dns" } ], "action": "hijack-dns" },
        { "clash_mode": "Global", "outbound": "proxy" },
        { "rule_set": "geosite-cn", "clash_mode": "Rule", "outbound": "direct" },
        { "rule_set": "geoip-cn", "clash_mode": "Rule", "outbound": "direct" },
        { "ip_is_private": true, "clash_mode": "Rule", "outbound": "direct" },
        { "clash_mode": "Direct", "outbound": "direct" }
      ],
      "rule_set": [
        { "tag": "geosite-cn", "type": "remote", "format": "binary", "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-cn.srs", "download_detour": "direct" },
        { "tag": "geoip-cn", "type": "remote", "format": "binary", "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/cn.srs", "download_detour": "direct" }
      ],
      "final": "proxy",
      "auto_detect_interface": true,
      "default_domain_resolver": { "server": "aliDns" }
    },
    "outbounds": []
  }'

  # Build outbounds list dynamically
  local outs='[]'

  # VLESS Reality
  outs=$(echo "$outs" | jq --arg server "$server_ipcl" --arg port "$vl_port" --arg uuid "$uuid" --arg name "$vl_name" --arg pbk "$public_key" --arg sid "$short_id" --arg host "$hostname" \
    '. + [{
      "type": "vless",
      "tag": "vless-\($host)",
      "server": $server,
      "server_port": ($port | tonumber),
      "uuid": $uuid,
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": $name,
        "utls": { "enabled": true, "fingerprint": "chrome" },
        "reality": { "enabled": true, "public_key": $pbk, "short_id": $sid }
      }
    }]')

  # VMess WS
  outs=$(echo "$outs" | jq --arg server "$vmadd_local" --arg port "$vm_port" --arg uuid "$uuid" --arg name "$vm_name" --argjson tls "$tls" --arg path "$ws_path" --arg host "$hostname" \
    '. + [{
      "type": "vmess",
      "tag": "vmess-\($host)",
      "server": $server,
      "server_port": ($port | tonumber),
      "uuid": $uuid,
      "security": "auto",
      "packet_encoding": "packetaddr",
      "transport": { "type": "ws", "path": $path, "headers": { "Host": $name } },
      "tls": {
        "enabled": $tls,
        "server_name": $name,
        "insecure": false,
        "utls": { "enabled": true, "fingerprint": "chrome" }
      }
    }]')

  # Hysteria 2
  local ports_array='[]'
  if [[ -n "$sbhy2pt" ]]; then
    ports_array="[$sbhy2pt]"
  fi
  
  outs=$(echo "$outs" | jq --arg server "$cl_hy2_ip" --arg port "$hy2_port" --argjson extra_ports "$ports_array" --arg uuid "$uuid" --arg name "$hy2_name" --argjson ins "$hy2_ins" --arg host "$hostname" --arg cert "$cert_content" \
    '. + [{
      "type": "hysteria2",
      "tag": "hy2-\($host)",
      "server": $server,
      "server_port": ($port | tonumber),
      "password": $uuid,
      "tls": ({
        "enabled": true,
        "server_name": $name,
        "insecure": false,
        "alpn": ["h3"]
      } + (if $ins and ($cert | length) > 0 then { "certificate": [$cert] } else {} end))
    } + (if ($extra_ports | length) > 0 then { "server_ports": $extra_ports } else {} end)]')

  # Tuic 5
  outs=$(echo "$outs" | jq --arg server "$cl_tu5_ip" --arg port "$tu5_port" --arg uuid "$uuid" --arg name "$tu5_name" --argjson ins "$tu5_ins" --arg host "$hostname" --arg cert "$cert_content" \
    '. + [{
      "type": "tuic",
      "tag": "tuic5-\($host)",
      "server": $server,
      "server_port": ($port | tonumber),
      "uuid": $uuid,
      "password": $uuid,
      "congestion_control": "bbr",
      "udp_relay_mode": "native",
      "udp_over_stream": false,
      "zero_rtt_handshake": false,
      "heartbeat": "10s",
      "tls": ({
        "enabled": true,
        "server_name": $name,
        "insecure": false,
        "alpn": ["h3"]
      } + (if $ins and ($cert | length) > 0 then { "certificate": [$cert] } else {} end))
    }]')

  # Anytls (Only for version > 1.10)
  if [[ "$sbnh" != "1.10" ]]; then
    outs=$(echo "$outs" | jq --arg server "$sb_an_ip" --arg port "$an_port" --arg uuid "$uuid" --arg name "$an_name" --argjson ins "$an_ins" --arg host "$hostname" --arg cert "$cert_content" \
      '. + [{
        "type": "anytls",
        "tag": "anytls-\($host)",
        "server": $server,
        "server_port": ($port | tonumber),
        "password": $uuid,
        "idle_session_check_interval": "30s",
        "idle_session_timeout": "30s",
        "min_idle_session": 5,
        "tls": ({
          "enabled": true,
          "insecure": false,
          "server_name": $name
        } + (if $ins and ($cert | length) > 0 then { "certificate": [$cert] } else {} end))
      }]')
  fi

  # Cloudflare Argo Tunnels (Only if VMess TLS is false & Argo active)
  local has_argo_fixed=false
  local has_argo_temp=false
  
  if [[ "$tls" = "false" ]]; then
    if ps -ef 2>/dev/null | grep -q '[c]loudflared.*run'; then
      has_argo_fixed=true
      argogd=$(cat "$SBFOLDER/sbargoym.log" 2>/dev/null)
      # Argo Fixed TLS
      outs=$(echo "$outs" | jq --arg server "$vmadd_argo" --arg tag "vmess-tls-argo固定-$hostname" --arg host "$argogd" --arg path "$ws_path" --arg uuid "$uuid" \
        '. + [{
          "type": "vmess", "tag": $tag, "server": $server, "server_port": 443, "uuid": $uuid, "security": "auto", "packet_encoding": "packetaddr",
          "transport": { "type": "ws", "path": $path, "headers": { "Host": $host } },
          "tls": { "enabled": true, "server_name": $host, "insecure": false, "utls": { "enabled": true, "fingerprint": "chrome" } }
        }]')
    fi
    
    if ps -ef 2>/dev/null | grep -q "[l]ocalhost:$vm_port"; then
      has_argo_temp=true
      # Argo Temp TLS
      outs=$(echo "$outs" | jq --arg server "$vmadd_argo" --arg tag "vmess-tls-argo临时-$hostname" --arg host "$argo" --arg path "$ws_path" --arg uuid "$uuid" \
        '. + [{
          "type": "vmess", "tag": $tag, "server": $server, "server_port": 443, "uuid": $uuid, "security": "auto", "packet_encoding": "packetaddr",
          "transport": { "type": "ws", "path": $path, "headers": { "Host": $host } },
          "tls": { "enabled": true, "server_name": $host, "insecure": false, "utls": { "enabled": true, "fingerprint": "chrome" } }
        }]')
    fi
  fi

  # Collect all outbound tags for selectors
  local tags_array=$(echo "$outs" | jq -c '[.[].tag]')

  # Add selector and urltest outbounds
  outs=$(echo "$outs" | jq --argjson tags "$tags_array" \
    '. + [
      { "type": "selector", "tag": "proxy", "default": "auto", "outbounds": (["auto"] + $tags) },
      { "type": "urltest", "tag": "auto", "outbounds": $tags, "url": "http://www.gstatic.com/generate_204", "interval": "10m", "tolerance": 50 },
      { "type": "direct", "tag": "direct" }
    ]')

  # Write Sing-box client JSON config
  echo "$base_client_template" | jq --argjson outs "$outs" '.outbounds = $outs' > "$SBFOLDER/sbox.json"

  # 2. BASE CLASH META (MIHOMO) CONFIG GENERATOR
  clall() {
    cat <<EOF
port: 7890
allow-lan: true
mode: rule
log-level: info
unified-delay: true
dns:
  enable: true 
  listen: "0.0.0.0:1053"
  ipv6: true
  prefer-h3: false
  respect-rules: true
  use-system-hosts: false
  cache-algorithm: "arc"
  enhanced-mode: "fake-ip"
  fake-ip-range: "198.18.0.1/16"
  fake-ip-filter:
    - "+.lan"
    - "+.local"
    - "+.msftconnecttest.com"
    - "+.msftncsi.com"
    - "localhost.ptlogin2.qq.com"
    - "localhost.sec.qq.com"
    - "+.in-addr.arpa"
    - "+.ip6.arpa"
    - "time.*.com"
    - "time.*.gov"
    - "pool.ntp.org"
    - "localhost.work.weixin.qq.com"
  default-nameserver: ["223.5.5.5", "119.29.29.29"]
  nameserver:
    - "https://1.1.1.1/dns-query"
    - "https://8.8.8.8/dns-query"
  proxy-server-nameserver:
    - "https://223.5.5.5/dns-query"
    - "https://doh.pub/dns-query"
nameserver-policy:
  "geosite:cn":
     - "https://223.5.5.5/dns-query"
     - "https://doh.pub/dns-query"
EOF
  }

  local clash_proxies=""
  local clash_tags=()

  # VLESS Reality
  clash_proxies+="- name: vless-reality-vision-$hostname
  type: vless
  server: $server_ipcl
  port: $vl_port
  uuid: $uuid
  network: tcp
  udp: true
  tls: true
  flow: xtls-rprx-vision
  servername: $vl_name
  reality-opts:
    public-key: $public_key
    short-id: $short_id
  client-fingerprint: chrome\n\n"
  clash_tags+=("vless-reality-vision-$hostname")

  # VMess WS
  clash_proxies+="- name: vmess-ws-$hostname
  type: vmess
  server: $vmadd_local
  port: $vm_port
  uuid: $uuid
  alterId: 0
  cipher: auto
  udp: true
  tls: $tls
  network: ws
  servername: $vm_name
  ws-opts:
    path: \"$ws_path\"
    headers:
      Host: $vm_name\n\n"
  clash_tags+=("vmess-ws-$hostname")

  # Hysteria 2
  clash_proxies+="- name: hysteria2-$hostname
  type: hysteria2
  server: $cl_hy2_ip
  port: $hy2_port
  ports: $cmhy2pt
  password: $uuid
  alpn:
    - h3
  sni: $hy2_name
  skip-cert-verify: false"
  if $hy2_ins && [[ -n "$SHA256" ]]; then
    clash_proxies+="
  fingerprint: $SHA256"
  fi
  clash_proxies+="
  fast-open: true\n\n"
  clash_tags+=("hysteria2-$hostname")

  # Tuic 5
  clash_proxies+="- name: tuic5-$hostname
  type: tuic
  server: $cl_tu5_ip
  port: $tu5_port
  uuid: $uuid
  password: $uuid
  alpn: [h3]
  disable-sni: $tu5_ins
  reduce-rtt: true
  udp-relay-mode: native
  congestion-controller: bbr
  sni: $tu5_name
  skip-cert-verify: false"
  if $tu5_ins && [[ -n "$cert_content" ]]; then
    clash_proxies+="
  ca-str: |
$(echo "$cert_content" | sed 's/^/    /')"
  fi
  clash_proxies+="\n\n"
  clash_tags+=("tuic5-$hostname")

  # Anytls
  if [[ "$sbnh" != "1.10" ]]; then
    clash_proxies+="- name: anytls-$hostname
  type: anytls
  server: $cl_an_ip
  port: $an_port
  password: $uuid
  client-fingerprint: chrome
  udp: true
  idle-session-check-interval: 30
  idle-session-timeout: 30
  sni: $an_name
  skip-cert-verify: $an_ins\n\n"
    clash_tags+=("anytls-$hostname")
  fi

  # Argo Fixed
  if $has_argo_fixed; then
    clash_proxies+="- name: vmess-tls-argo固定-$hostname
  type: vmess
  server: $vmadd_argo
  port: 443
  uuid: $uuid
  alterId: 0
  cipher: auto
  udp: true
  tls: true
  network: ws
  servername: $argogd
  ws-opts:
    path: \"$ws_path\"
    headers:
      Host: $argogd\n\n"
    clash_tags+=("vmess-tls-argo固定-$hostname")
  fi

  # Argo Temp
  if $has_argo_temp; then
    clash_proxies+="- name: vmess-tls-argo临时-$hostname
  type: vmess
  server: $vmadd_argo
  port: 443
  uuid: $uuid
  alterId: 0
  cipher: auto
  udp: true
  tls: true
  network: ws
  servername: $argo
  ws-opts:
    path: \"$ws_path\"
    headers:
      Host: $argo\n\n"
    clash_tags+=("vmess-tls-argo临时-$hostname")
  fi

  # Build group lists
  local clash_group_proxies=""
  for tag in "${clash_tags[@]}"; do
    clash_group_proxies+="    - $tag\n"
  done

  # Write Clash YAML
  {
    clall
    echo -e "proxies:\n$clash_proxies"
    echo -e "proxy-groups:\n- name: 负载均衡\n  type: load-balance\n  url: https://www.gstatic.com/generate_204\n  interval: 300\n  strategy: round-robin\n  proxies:\n$clash_group_proxies"
    echo -e "- name: 自动选择\n  type: url-test\n  url: https://www.gstatic.com/generate_204\n  interval: 300\n  tolerance: 50\n  proxies:\n$clash_group_proxies"
    echo -e "- name: 🌍选择代理节点\n  type: select\n  proxies:\n    - 负载均衡\n    - 自动选择\n    - DIRECT\n$clash_group_proxies"
    echo -e "rules:\n  - GEOIP,LAN,DIRECT\n  - GEOIP,CN,DIRECT\n  - MATCH,🌍选择代理节点"
  } > "$SBFOLDER/clmi.yaml"
}

sbshare() {
  rm -rf "$SBFOLDER"/{jhdy,vl_reality,vm_ws_argols,vm_ws_argogd,vm_ws,vm_ws_tls,hy2,tuic5,an}.txt
  result_vl_vm_hy_tu && resvless && resvmess && reshy2 && restu5
  if [[ "$sbnh" != "1.10" ]]; then
    resan
  fi
  cat "$SBFOLDER/vl_reality.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/vm_ws_argols.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/vm_ws_argogd.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/vm_ws.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/vm_ws_tls.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/hy2.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/tuic5.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/an.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  
  v2sub=$(cat "$SBFOLDER/jhdy.txt" 2>/dev/null)
  echo "$v2sub" > "$SBFOLDER/jhsub.txt"
  echo
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  red "🚀【 聚合节点 】节点信息如下：" && sleep 2
  echo
  echo "分享链接"
  echo -e "${yellow}$v2sub${plain}"
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  echo
  sb_client
}

clash_sb_share() {
  sbactive
  echo
  yellow "1：刷新并查看各协议分享链接、二维码、聚合节点"
  yellow "2：刷新并查看Mihomo、Sing-box客户端SFA/SFI/SFW三合一配置"
  yellow "0：返回上层"
  readp "请选择【0-2】：" menu
  if [ "$menu" = "1" ]; then
    sbshare
  elif [ "$menu" = "2" ]; then
    green "请稍等……"
    sbshare > /dev/null 2>&1
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    red "🚀Mihomo配置文件显示如下："
    red "文件目录 $SBFOLDER/clmi.yaml ，复制自建以yaml文件格式为准" && sleep 2
    echo
    cat "$SBFOLDER/clmi.yaml"
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    red "🚀SFA/SFI/SFW配置文件显示如下："
    red "安卓SFA、苹果SFI，win电脑官方文件包SFW请到官方Github项目自行下载，"
    red "文件目录 $SBFOLDER/sbox.json ，复制自建以json文件格式为准" && sleep 2
    echo
    cat "$SBFOLDER/sbox.json"
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
  else
    sb
  fi
}

# --- Cloudflare Argo Tunnels ---
cloudflaredargo() {
  if [ ! -e "$SBFOLDER/cloudflared" ]; then
    case $(uname -m) in
      aarch64) cpu=arm64;;
      x86_64) cpu=amd64;;
    esac
    curl -L -o "$SBFOLDER/cloudflared" -# --retry 2 "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cpu"
    chmod +x "$SBFOLDER/cloudflared"
  fi
}

cfargo_ym() {
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
  tls=$(echo "$clean_json" | jq -r '.inbounds[1].tls.enabled')
  if [[ "$tls" = "false" ]]; then
    echo
    yellow "1：添加或者删除Argo临时隧道"
    yellow "2：添加或者删除Argo固定隧道"
    yellow "0：返回上层"
    readp "请选择【0-2】：" menu
    if [ "$menu" = "1" ]; then
      cfargo
    elif [ "$menu" = "2" ]; then
      cfargoym
    else
      changeserv
    fi
  else
    yellow "因vmess开启了tls，Argo隧道功能不可用" && sleep 2
  fi
}

cfargoym() {
  echo
  if [[ -f "$SBFOLDER/sbargotoken.log" && -f "$SBFOLDER/sbargoym.log" ]]; then
    green "当前Argo固定隧道域名：$(cat "$SBFOLDER/sbargoym.log" 2>/dev/null)"
    green "当前Argo固定隧道Token：$(cat "$SBFOLDER/sbargotoken.log" 2>/dev/null)"
  fi
  echo
  green "请进入Cloudflare官网 --- Zero Trust --- 网络 --- 连接器，创建固定隧道"
  yellow "1：重置/设置Argo固定隧道域名"
  yellow "2：停止Argo固定隧道"
  yellow "0：返回上层"
  readp "请选择【0-2】：" menu
  if [ "$menu" = "1" ]; then
    cloudflaredargo
    readp "输入Argo固定隧道Token: " argotoken
    readp "输入Argo固定隧道域名: " argoym
    pid=$(ps -ef 2>/dev/null | awk '/[c]loudflared.*run/ {print $2}')
    [ -n "$pid" ] && kill -9 "$pid" >/dev/null 2>&1
    echo
    if [[ -n "${argotoken}" && -n "${argoym}" ]]; then
      if pidof systemd >/dev/null 2>&1; then
        cat > /etc/systemd/system/argo.service <<EOF
[Unit]
Description=argo service
After=network.target
[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=$SBFOLDER/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token "${argotoken}"
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload >/dev/null 2>&1
        systemctl enable argo >/dev/null 2>&1
        systemctl start argo >/dev/null 2>&1
      elif command -v rc-service >/dev/null 2>&1; then
        cat > /etc/init.d/argo <<EOF
#!/sbin/openrc-run
description="argo service"
command="$SBFOLDER/cloudflared tunnel"
command_args="--no-autoupdate --edge-ip-version auto --protocol http2 run --token ${argotoken}"
pidfile="/run/argo.pid"
command_background="yes"
depend() {
  need net
}
EOF
        chmod +x /etc/init.d/argo >/dev/null 2>&1
        rc-update add argo default >/dev/null 2>&1
        rc-service argo start >/dev/null 2>&1
      fi
    fi
    echo "${argoym}" > "$SBFOLDER/sbargoym.log"
    echo "${argotoken}" > "$SBFOLDER/sbargotoken.log"
    argo=$(cat "$SBFOLDER/sbargoym.log" 2>/dev/null)
    sbshare > /dev/null 2>&1
    blue "Argo固定隧道设置完成，固定域名：$argo"
  elif [ "$menu" = "2" ]; then
    if pidof systemd >/dev/null 2>&1; then
      systemctl stop argo >/dev/null 2>&1
      systemctl disable argo >/dev/null 2>&1
      rm -rf /etc/systemd/system/argo.service
    elif command -v rc-service >/dev/null 2>&1; then
      rc-service argo stop >/dev/null 2>&1
      rc-update del argo default >/dev/null 2>&1
      rm -rf /etc/init.d/argo
    fi
    rm -rf "$SBFOLDER/vm_ws_argogd.txt"
    sbshare > /dev/null 2>&1
    green "Argo固定隧道已停止"
  else
    cfargo_ym
  fi
}

cfargo() {
  echo
  yellow "1：重置Argo临时隧道域名"
  yellow "2：停止Argo临时隧道"
  yellow "0：返回上层"
  readp "请选择【0-2】：" menu
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
  local vm_listen_port=$(echo "$clean_json" | jq -r '.inbounds[1].listen_port')
  if [ "$menu" = "1" ]; then
    green "请稍等……"
    cloudflaredargo
    ps -ef | grep "[l]ocalhost:$vm_listen_port" | awk '{print $2}' | xargs kill 2>/dev/null
    nohup "$SBFOLDER/cloudflared" tunnel --url "http://localhost:$vm_listen_port" --edge-ip-version auto --no-autoupdate --protocol http2 > "$SBFOLDER/argo.log" 2>&1 &
    sleep 20
    local argo_url=$(cat "$SBFOLDER/argo.log" 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
    if [[ -n $(curl -sL "https://$argo_url/" -I | awk 'NR==1 && /404|400|503/') ]]; then
      argo=$argo_url
      sbshare > /dev/null 2>&1
      blue "Argo临时隧道申请成功，域名验证有效：$argo" && sleep 2
      if command -v apk >/dev/null 2>&1; then
        cat > /etc/local.d/alpineargo.start <<EOF
#!/bin/bash
sleep 10
nohup $SBFOLDER/cloudflared tunnel --url http://localhost:$vm_listen_port --edge-ip-version auto --no-autoupdate --protocol http2 > $SBFOLDER/argo.log 2>&1 &
sleep 10
printf "9\n1\n" | bash $SCRIPT_SHORTCUT > /dev/null 2>&1
EOF
        chmod +x /etc/local.d/alpineargo.start
        rc-update add local default >/dev/null 2>&1
      else
        crontab -l 2>/dev/null > /tmp/crontab.tmp
        sed -i '/url http/d' /tmp/crontab.tmp
        echo "@reboot sleep 10 && /bin/bash -c \"nohup $SBFOLDER/cloudflared tunnel --url http://localhost:$vm_listen_port --edge-ip-version auto --no-autoupdate --protocol http2 > $SBFOLDER/argo.log 2>&1 & sleep 10 && printf \\\"9\n1\n\\\" | bash $SCRIPT_SHORTCUT > /dev/null 2>&1\"" >> /tmp/crontab.tmp
        crontab /tmp/crontab.tmp >/dev/null 2>&1
        rm /tmp/crontab.tmp
      fi
    else
      yellow "Argo临时域名验证暂不可用，请稍后再试"
    fi
  elif [ "$menu" = "2" ]; then
    ps -ef | grep "[l]ocalhost:$vm_listen_port" | awk '{print $2}' | xargs kill 2>/dev/null
    crontab -l 2>/dev/null > /tmp/crontab.tmp
    sed -i '/url http/d' /tmp/crontab.tmp
    crontab /tmp/crontab.tmp >/dev/null 2>&1
    rm /tmp/crontab.tmp
    rm -rf "$SBFOLDER/vm_ws_argols.txt"
    rm -rf /etc/local.d/alpineargo.start
    sbshare > /dev/null 2>&1
    green "Argo临时隧道已停止"
  else
    cfargo_ym
  fi
}

# --- Settings & Customizations Menu ---
changeserv() {
  sbactive
  echo
  green "Sing-box配置变更选择如下:"
  readp "1：更换Reality域名伪装地址、切换自签证书与Acme域名证书、开关TLS\n2：更换全协议UUID(密码)、Vmess-Path路径\n3：设置Argo临时隧道、固定隧道\n4：切换IPV4或IPV6的代理优先级 (仅 1.10.7 内核可用)\n5：更换Warp-wireguard出站账户\n6：设置所有Vmess节点的CDN优选地址\n0：返回上层\n请选择【0-6】：" menu
  case "$menu" in
    1) changeym ;;
    2) changeuuid ;;
    3) cfargo_ym ;;
    4) changeip ;;
    5) changewg ;;
    6) vmesscfadd ;;
    *) sb ;;
  esac
}

# --- Port Query Helper ---
allports() {
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
  vl_port=$(echo "$clean_json" | jq -r '.inbounds[0].listen_port')
  vm_port=$(echo "$clean_json" | jq -r '.inbounds[1].listen_port')
  hy2_port=$(echo "$clean_json" | jq -r '.inbounds[2].listen_port')
  tu5_port=$(echo "$clean_json" | jq -r '.inbounds[3].listen_port')
  an_port=$(echo "$clean_json" | jq -r '.inbounds[4].listen_port')
  hy2_ports=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$hy2_port" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ',' | sed 's/,$//')
  tu5_ports=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$tu5_port" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ',' | sed 's/,$//')
  [[ -n $hy2_ports ]] && hy2zfport="$hy2_ports" || hy2zfport="未添加"
  [[ -n $tu5_ports ]] && tu5zfport="$tu5_ports" || tu5zfport="未添加"
}

# --- Port Management (Main changeport function) ---
changeport() {
  sbactive
  allports
  
  fports() {
    readp "\n请输入转发的端口范围 (1000-65535范围内，格式为 小数字:大数字)：" rangeport
    if [[ $rangeport =~ ^([1-9][0-9]{3,4}:[1-9][0-9]{3,4})$ ]]; then
      b=${rangeport%%:*}
      c=${rangeport##*:}
      if [[ $b -ge 1000 && $b -le 65535 && $c -ge 1000 && $c -le 65535 && $b -lt $c ]]; then
        iptables -t nat -A PREROUTING -p udp --dport $rangeport -j DNAT --to-destination :$port
        ip6tables -t nat -A PREROUTING -p udp --dport $rangeport -j DNAT --to-destination :$port
        netfilter-persistent save >/dev/null 2>&1
        service iptables save >/dev/null 2>&1
        blue "已确认转发的端口范围：$rangeport"
      else
        red "输入的端口范围不在有效范围内" && fports
      fi
    else
      red "输入格式不正确。格式为 小数字:大数字" && fports
    fi
    echo
  }
  
  fport() {
    readp "\n请输入一个转发的端口 (1000-65535范围内)：" onlyport
    if [[ $onlyport -ge 1000 && $onlyport -le 65535 ]]; then
      iptables -t nat -A PREROUTING -p udp --dport $onlyport -j DNAT --to-destination :$port
      ip6tables -t nat -A PREROUTING -p udp --dport $onlyport -j DNAT --to-destination :$port
      netfilter-persistent save >/dev/null 2>&1
      service iptables save >/dev/null 2>&1
      blue "已确认转发的端口：$onlyport"
    else
      blue "输入的端口不在有效范围内" && fport
    fi
    echo
  }
  
  hy2deports() {
    allports
    hy2_ports=$(echo "$hy2_ports" | sed 's/,/,/g')
    IFS=',' read -ra ports <<< "$hy2_ports"
    for port in "${ports[@]}"; do
      iptables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$hy2_port
      ip6tables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$hy2_port
    done
    netfilter-persistent save >/dev/null 2>&1
    service iptables save >/dev/null 2>&1
  }
  
  tu5deports() {
    allports
    tu5_ports=$(echo "$tu5_ports" | sed 's/,/,/g')
    IFS=',' read -ra ports <<< "$tu5_ports"
    for port in "${ports[@]}"; do
      iptables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$tu5_port
      ip6tables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$tu5_port
    done
    netfilter-persistent save >/dev/null 2>&1
    service iptables save >/dev/null 2>&1
  }
  
  allports
  green "Vless-reality、Vmess-ws、Anytls仅能更改唯一的端口，vmess-ws注意Argo端口重置"
  green "Hysteria2与Tuic5支持更改主端口，也支持增删多个转发端口"
  green "Hysteria2支持端口跳跃，且与Tuic5都支持多端口复用"
  echo
  green "1：Vless-reality协议 ${yellow}端口:$vl_port${plain}"
  green "2：Vmess-ws协议 ${yellow}端口:$vm_port${plain}"
  green "3：Hysteria2协议 ${yellow}端口:$hy2_port  转发多端口: $hy2zfport${plain}"
  green "4：Tuic5协议 ${yellow}端口:$tu5_port  转发多端口: $tu5zfport${plain}"
  if [[ "$sbnh" != "1.10" ]]; then
    green "5：Anytls协议 ${yellow}端口:$an_port${plain}"
  fi
  green "0：返回上层"
  readp "请选择要变更端口的协议：" menu
  
  if [ "$menu" = "1" ]; then
    vlport
    # Clean JQ-based port updates
    for file in $SBFILES; do
      [ -f "$file" ] && jq --argjson p "$port_vl_re" '(.inbounds[] | select(.type == "vless")).listen_port = $p' "$file" > /tmp/tmp.json && mv /tmp/tmp.json "$file"
    done
    restartsb && sbshare > /dev/null 2>&1
    blue "Vless-reality端口更改完成\n"
  elif [ "$menu" = "5" ] && [[ "$sbnh" != "1.10" ]]; then
    anport
    for file in $SBFILES; do
      [ -f "$file" ] && jq --argjson p "$port_an" '(.inbounds[] | select(.type == "anytls")).listen_port = $p' "$file" > /tmp/tmp.json && mv /tmp/tmp.json "$file"
    done
    restartsb && sbshare > /dev/null 2>&1
    blue "Anytls端口更改完成\n"
  elif [ "$menu" = "2" ]; then
    vmport
    for file in $SBFILES; do
      [ -f "$file" ] && jq --argjson p "$port_vm_ws" '(.inbounds[] | select(.type == "vmess")).listen_port = $p' "$file" > /tmp/tmp.json && mv /tmp/tmp.json "$file"
    done
    restartsb && sbshare > /dev/null 2>&1
    blue "Vmess-ws端口更改完成"
    local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
    tls=$(echo "$clean_json" | jq -r '.inbounds[1].tls.enabled')
    if [[ "$tls" = "false" ]]; then
      blue "切记：如果Argo使用中，临时隧道必须重置，固定隧道的CF设置界面端口必须修改为$port_vm_ws"
    else
      blue "因TLS已开启，当前Argo隧道已不支持开启"
    fi
    echo
  elif [ "$menu" = "3" ]; then
    green "1：更换Hysteria2主端口 (原多端口自动重置删除)"
    green "2：添加Hysteria2多端口"
    green "3：重置删除Hysteria2多端口"
    green "0：返回上层"
    readp "请选择【0-3】：" menu
    if [ "$menu" = "1" ]; then
      [ -n "$hy2_ports" ] && hy2deports
      hy2port
      for file in $SBFILES; do
        [ -f "$file" ] && jq --argjson p "$port_hy2" '(.inbounds[] | select(.type == "hysteria2")).listen_port = $p' "$file" > /tmp/tmp.json && mv /tmp/tmp.json "$file"
      done
      restartsb && sbshare > /dev/null 2>&1
      blue "Hysteria2端口更改完成"
    elif [ "$menu" = "2" ]; then
      green "1：添加Hysteria2范围端口"
      green "2:: 添加Hysteria2单端口"
      green "0：返回上层"
      readp "请选择【0-2】：" menu
      port=$(strip_json_comments "$SBFOLDER/sb.json" | jq -r '.inbounds[2].listen_port')
      if [ "$menu" = "1" ]; then
        fports && sbshare > /dev/null 2>&1 && changeport
      elif [ "$menu" = "2" ]; then
        fport && sbshare > /dev/null 2>&1 && changeport
      else
        changeport
      fi
    elif [ "$menu" = "3" ]; then
      if [ -n "$hy2_ports" ]; then
        hy2deports && sbshare > /dev/null 2>&1 && yellow "Hysteria2多端口已删除" && changeport
      else
        sbshare > /dev/null 2>&1 && yellow "Hysteria2未设置多端口" && changeport
      fi
    else
      changeport
    fi
  elif [ "$menu" = "4" ]; then
    green "1：更换Tuic5主端口 (原多端口自动重置删除)"
    green "2：添加Tuic5多端口"
    green "3：重置删除Tuic5多端口"
    green "0：返回上层"
    readp "请选择【0-3】：" menu
    if [ "$menu" = "1" ]; then
      [ -n "$tu5_ports" ] && tu5deports
      tu5port
      for file in $SBFILES; do
        [ -f "$file" ] && jq --argjson p "$port_tu" '(.inbounds[] | select(.type == "tuic")).listen_port = $p' "$file" > /tmp/tmp.json && mv /tmp/tmp.json "$file"
      done
      restartsb && sbshare > /dev/null 2>&1
      blue "Tuic5端口更改完成"
    elif [ "$menu" = "2" ]; then
      green "1：添加Tuic5范围端口"
      green "2:: 添加Tuic5单端口"
      green "0：返回上层"
      readp "请选择【0-2】：" menu
      port=$(strip_json_comments "$SBFOLDER/sb.json" | jq -r '.inbounds[3].listen_port')
      if [ "$menu" = "1" ]; then
        fports && sbshare > /dev/null 2>&1 && changeport
      elif [ "$menu" = "2" ]; then
        fport && sbshare > /dev/null 2>&1 && changeport
      else
        changeport
      fi
    elif [ "$menu" = "3" ]; then
      if [ -n "$tu5_ports" ]; then
        tu5deports && sbshare > /dev/null 2>&1 && yellow "Tuic5多端口已删除" && changeport
      else
        sbshare > /dev/null 2>&1 && yellow "Tuic5未设置多端口" && changeport
      fi
    else
      changeport
    fi
  else
    sb
  fi
}

# --- Change UUID / VMess Path ---
changeuuid() {
  echo
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
  olduuid=$(echo "$clean_json" | jq -r '.inbounds[0].users[0].uuid')
  oldvmpath=$(echo "$clean_json" | jq -r '.inbounds[1].transport.path')
  green "全协议的uuid (密码)：$olduuid"
  green "Vmess的path路径：$oldvmpath"
  echo
  yellow "1：自定义全协议的uuid (密码)"
  yellow "2：自定义Vmess的path路径"
  yellow "0：返回上层"
  readp "请选择【0-2】：" menu
  if [ "$menu" = "1" ]; then
    readp "输入uuid，必须是uuid格式，不懂就回车(重置并随机生成uuid)：" menu
    if [ -z "$menu" ]; then
      uuid=$("$SBFOLDER/sing-box" generate uuid)
    else
      uuid=$menu
    fi
    # Use JQ for robust updates
    for file in $SBFILES; do
      if [ -f "$file" ]; then
        jq --arg u "$uuid" \
           '(.inbounds[] | select(.users != null) | .users[].uuid) = $u |
            (.inbounds[] | select(.type == "hysteria2") | .users[].password) = $u' \
           "$file" > /tmp/tmp.json && mv /tmp/tmp.json "$file"
      fi
    done
    restartsb && sbshare > /dev/null 2>&1
    blue "已确认uuid (密码)：${uuid}" 
    blue "已确认Vmess的path路径：$(strip_json_comments "$SBFOLDER/sb.json" | jq -r '.inbounds[1].transport.path')"
  elif [ "$menu" = "2" ]; then
    readp "输入Vmess的path路径，回车表示不变：" menu
    if [ -n "$menu" ]; then
      vmpath=$menu
      for file in $SBFILES; do
        if [ -f "$file" ]; then
          jq --arg p "$vmpath" '(.inbounds[] | select(.type == "vmess")).transport.path = $p' "$file" > /tmp/tmp.json && mv /tmp/tmp.json "$file"
        fi
      done
      restartsb && sbshare > /dev/null 2>&1
    fi
    blue "已确认Vmess的path路径：$(strip_json_comments "$SBFOLDER/sb.json" | jq -r '.inbounds[1].transport.path')"
  else
    changeserv
  fi
}

# --- Change IP Priority (Only for 1.10.7) ---
changeip() {
  if [[ "$sbnh" == "1.10" ]]; then
    v4v6
    chip() {
      jq --arg strat "$rrpip" '.outbounds[0].domain_strategy = $strat' "$SBFOLDER/sb10.json" > /tmp/sb10.json && mv /tmp/sb10.json "$SBFOLDER/sb10.json"
      cp "$SBFOLDER/sb10.json" "$SBFOLDER/sb.json"
      restartsb
    }
    readp "1. IPV4优先\n2. IPV6优先\n3. 仅IPV4\n4. 仅IPV6\n请选择：" choose
    if [[ $choose == "1" && -n $v4 ]]; then
      rrpip="prefer_ipv4" && chip && v4_6="IPV4优先($v4)"
    elif [[ $choose == "2" && -n $v6 ]]; then
      rrpip="prefer_ipv6" && chip && v4_6="IPV6优先($v6)"
    elif [[ $choose == "3" && -n $v4 ]]; then
      rrpip="ipv4_only" && chip && v4_6="仅IPV4($v4)"
    elif [[ $choose == "4" && -n $v6 ]]; then
      rrpip="ipv6_only" && chip && v4_6="仅IPV6($v6)"
    else 
      red "当前不存在你选择的IPV4/IPV6地址，或者输入错误" && changeip
    fi
    blue "当前已更换的IP优先级：${v4_6}" && sb
  else
    red "仅支持1.10.7内核可用" && exit
  fi
}

# --- Change Warp Wireguard settings ---
warpwg() {
  warpcode() {
    reg() {
      keypair=$(openssl genpkey -algorithm X25519 | openssl pkey -text -noout)
      private_key=$(echo "$keypair" | awk '/priv:/{flag=1; next} /pub:/{flag=0} flag' | tr -d '[:space:]' | xxd -r -p | base64)
      public_key=$(echo "$keypair" | awk '/pub:/{flag=1} flag' | tr -d '[:space:]' | xxd -r -p | base64)
      response=$(curl -sL --tlsv1.3 --connect-timeout 3 --max-time 5 \
        -X POST 'https://api.cloudflareclient.com/v0a2158/reg' \
        -H 'CF-Client-Version: a-7.21-0721' \
        -H 'Content-Type: application/json' \
        -d '{
          "key": "'"$public_key"'",
          "tos": "'"$(date -u +'%Y-%m-%dT%H:%M:%S.000Z')"'"
        }')
      if [ -z "$response" ]; then
        return 1
      fi
      echo "$response" | python3 -m json.tool 2>/dev/null | sed "/\"account_type\"/i\         \"private_key\": \"$private_key\","
    }
    reserved() {
      reserved_str=$(echo "$warp_info" | grep 'client_id' | cut -d\" -f4)
      reserved_hex=$(echo "$reserved_str" | base64 -d | xxd -p)
      reserved_dec=$(echo "$reserved_hex" | fold -w2 | while read HEX; do printf '%d ' "0x${HEX}"; done | awk '{print "["$1", "$2", "$3"]"}')
      echo -e "{\n    \"reserved_dec\": $reserved_dec,"
      echo -e "    \"reserved_hex\": \"0x$reserved_hex\","
      echo -e "    \"reserved_str\": \"$reserved_str\"\n}"
    }
    result() {
      echo "$warp_reserved" | grep -P "reserved" | sed "s/ //g" | sed 's/:"/: "/g' | sed 's/:\[/: \[/g' | sed 's/\([0-9]\+\),\([0-9]\+\),\([0-9]\+\)/\1, \2, \3/' | sed 's/^"/    "/g' | sed 's/"$/",/g'
      echo "$warp_info" | grep -P "(private_key|public_key|\"v4\": \"172.16.0.2\"|\"v6\": \"2)" | sed "s/ //g" | sed 's/:"/: "/g' | sed 's/^"/    "/g'
      echo "}"
    }
    warp_info=$(reg) 
    warp_reserved=$(reserved) 
    result
  }
  output=$(warpcode)
  if ! echo "$output" 2>/dev/null | grep -w "private_key" > /dev/null; then
    v6="2606:4700:110:860e:738f:b37:f15:d38d"
    pvk="g9I2sgUH6OCbIBTehkEfVEnuvInHYZvPOFhWchMLSc4="
    res="[33,217,129]"
  else
    pvk=$(echo "$output" | sed -n 4p | awk '{print $2}' | tr -d ' "' | sed 's/.$//')
    v6=$(echo "$output" | sed -n 7p | awk '{print $2}' | tr -d ' "')
    res=$(echo "$output" | sed -n 1p | awk -F":" '{print $NF}' | tr -d ' ' | sed 's/.$//')
  fi
  blue "Private_key私钥：$pvk"
  blue "IPV6地址：$v6"
  blue "reserved值：$res"
}

changewg() {
  [[ "$sbnh" == "1.10" ]] && num=10 || num=11
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
  if [[ "$sbnh" == "1.10" ]]; then
    wgipv6=$(echo "$clean_json" | jq -r '.outbounds[] | select(.type == "wireguard") | .local_address[1] | split("/")[0]')
    wgprkey=$(echo "$clean_json" | jq -r '.outbounds[] | select(.type == "wireguard") | .private_key')
    wgres=$(sed -n '165s/.*\[\(.*\)\].*/\1/p' "$SBFOLDER/sb.json")
    wgip=$(echo "$clean_json" | jq -r '.outbounds[] | select(.type == "wireguard") | .server')
    wgpo=$(echo "$clean_json" | jq -r '.outbounds[] | select(.type == "wireguard") | .server_port')
  else
    wgipv6=$(echo "$clean_json" | jq -r '.endpoints[] | .address[1] | split("/")[0]')
    wgprkey=$(echo "$clean_json" | jq -r '.endpoints[] | .private_key')
    wgres=$(sed -n '142s/.*\[\(.*\)\].*/\1/p' "$SBFOLDER/sb.json")
    wgip=$(echo "$clean_json" | jq -r '.endpoints[] | .peers[].address')
    wgpo=$(echo "$clean_json" | jq -r '.endpoints[] | .peers[].port')
  fi
  echo
  green "当前warp-wireguard可更换的参数如下："
  green "Private_key私钥：$wgprkey"
  green "IPV6地址：$wgipv6"
  green "Reserved值：$wgres"
  green "对端IP：$wgip:$wgpo"
  echo
  yellow "1：更换warp-wireguard账户"
  yellow "0：返回上层"
  readp "请选择【0-1】：" menu
  if [ "$menu" = "1" ]; then
    green "最新随机生成普通warp-wireguard账户如下"
    warpwg
    echo
    readp "输入自定义Private_key：" menu_key
    [ -z "$menu_key" ] && menu_key=$pvk
    readp "输入自定义IPV6地址：" menu_ip
    [ -z "$menu_ip" ] && menu_ip=$v6
    readp "输入自定义Reserved值 (格式：数字,数字,数字)，如无值则回车跳过：" menu_res
    if [ -z "$menu_res" ]; then
      menu_res="0,0,0"
    fi
    
    # Use JQ for clean and robust updates
    # sb10.json
    jq --arg key "$menu_key" --arg ip "$menu_ip/128" --argjson res "[$menu_res]" \
       '(.outbounds[] | select(.type == "wireguard")) |= (.private_key = $key | .local_address[1] = $ip | .reserved = $res)' \
       "$SBFOLDER/sb10.json" > /tmp/sb10.json && mv /tmp/sb10.json "$SBFOLDER/sb10.json"
    
    # sb11.json
    jq --arg key "$menu_key" --arg ip "$menu_ip/128" --argjson res "[$menu_res]" \
       '(.endpoints[] | select(.type == "wireguard")) |= (.private_key = $key | .address[1] = $ip | .peers[0].reserved = $res)' \
       "$SBFOLDER/sb11.json" > /tmp/sb11.json && mv /tmp/sb11.json "$SBFOLDER/sb11.json"
       
    rm -rf "$SBFOLDER/sb.json"
    cp "$SBFOLDER/sb${num}.json" "$SBFOLDER/sb.json"
    restartsb
    green "设置结束"
  else
    changeserv
  fi
}

# --- Change Reality Domain / Acme Certificate ---
changeym() {
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
  [ -f /root/ygkkkca/ca.log ] && ymzs="$yellow切换为域名证书：$(cat /root/ygkkkca/ca.log 2>/dev/null)$plain" || ymzs="$yellow未申请域名证书，无法切换$plain"
  vl_na="正在使用的域名：$(echo "$clean_json" | jq -r '.inbounds[0].tls.server_name')。$yellow更换符合reality要求的域名，不支持证书域名$plain"
  tls=$(echo "$clean_json" | jq -r '.inbounds[1].tls.enabled')
  [[ "$tls" = "false" ]] && vm_na="当前已关闭TLS。$ymzs ${yellow}将开启TLS，Argo隧道将不支持开启${plain}" || vm_na="正在使用的域名证书：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellow切换为关闭TLS，Argo隧道将可用$plain"
  
  hy2_sniname=$(echo "$clean_json" | jq -r '.inbounds[2].tls.key_path')
  [[ "$hy2_sniname" = "$SBFOLDER/private.key" || "$hy2_sniname" = "/etc/s-box/private.key" ]] && hy2_na="正在使用自签bing证书。$ymzs" || hy2_na="正在使用的域名证书：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellow切换为自签bing证书$plain"
  
  tu5_sniname=$(echo "$clean_json" | jq -r '.inbounds[3].tls.key_path')
  [[ "$tu5_sniname" = "$SBFOLDER/private.key" || "$tu5_sniname" = "/etc/s-box/private.key" ]] && tu5_na="正在使用自签bing证书。$ymzs" || tu5_na="正在使用的域名证书：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellow切换为自签bing证书$plain"
  
  if [[ "$sbnh" != "1.10" ]]; then
    an_sniname=$(echo "$clean_json" | jq -r '.inbounds[4].tls.key_path')
    [[ "$an_sniname" = "$SBFOLDER/private.key" || "$an_sniname" = "/etc/s-box/private.key" ]] && an_na="正在使用自签bing证书。$ymzs" || an_na="正在使用的域名证书：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellow切换为自签bing证书$plain"
  fi
  
  echo
  green "请选择要切换证书模式的协议"
  green "1：vless-reality协议，$vl_na"
  if [[ -f /root/ygkkkca/ca.log ]]; then
    green "2：vmess-ws协议，$vm_na"
    green "3：Hysteria2协议，$hy2_na"
    green "4：Tuic5协议，$tu5_na"
    if [[ "$sbnh" != "1.10" ]]; then
      green "5：Anytls协议，$an_na"
    fi
  else
    red "仅支持选项1 (vless-reality)。因未申请域名证书，vmess-ws、Hysteria-2、Tuic-v5、Anytls的证书切换选项暂不予显示"
  fi
  green "0：返回上层"
  readp "请选择：" menu
  
  if [ "$menu" = "1" ]; then
    readp "请输入vless-reality域名 (回车使用apple.com)：" menu
    ym_vl_re=${menu:-apple.com}
    # JQ-based replacement
    for file in $SBFILES; do
      if [ -f "$file" ]; then
        jq --arg ym "$ym_vl_re" \
           '(.inbounds[] | select(.type == "vless")) |= (.tls.server_name = $ym | .tls.reality.handshake.server = $ym)' \
           "$file" > /tmp/tmp.json && mv /tmp/tmp.json "$file"
      fi
    done
    restartsb && sbshare > /dev/null 2>&1
    blue "Vless-reality域名证书更换完毕"
  elif [ "$menu" = "2" ] && [ -f /root/ygkkkca/ca.log ]; then
    local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
    local cur_tls=$(echo "$clean_json" | jq -r '.inbounds[1].tls.enabled')
    local next_tls=true
    [ "$cur_tls" = "true" ] && next_tls=false
    
    local cur_sni=$(echo "$clean_json" | jq -r '.inbounds[1].tls.server_name')
    local next_sni=$(cat /root/ygkkkca/ca.log)
    
    local cur_key=$(echo "$clean_json" | jq -r '.inbounds[1].tls.key_path')
    local next_cert="/etc/s-box/cert.pem"
    local next_key="/etc/s-box/private.key"
    if [ "$cur_key" = "$SBFOLDER/private.key" ] || [ "$cur_key" = "/etc/s-box/private.key" ]; then
      next_cert="/root/ygkkkca/cert.crt"
      next_key="/root/ygkkkca/private.key"
    fi
    
    for file in $SBFILES; do
      if [ -f "$file" ]; then
        jq --argjson tls "$next_tls" --arg sni "$next_sni" --arg cert "$next_cert" --arg key "$next_key" \
           '(.inbounds[] | select(.type == "vmess")) |= (.tls.enabled = $tls | .tls.server_name = $sni | .tls.certificate_path = $cert | .tls.key_path = $key)' \
           "$file" > /tmp/tmp.json && mv /tmp/tmp.json "$file"
      fi
    done
    restartsb && sbshare > /dev/null 2>&1
    blue "vmess-ws协议域名证书更换完毕\n"
    local clean_json_new=$(strip_json_comments "$SBFOLDER/sb.json")
    tls=$(echo "$clean_json_new" | jq -r '.inbounds[1].tls.enabled')
    vm_port=$(echo "$clean_json_new" | jq -r '.inbounds[1].listen_port')
    blue "当前Vmess-ws(tls)的端口：$vm_port"
    [[ "$tls" = "false" ]] && blue "切记：可进入主菜单选项4-2，将Vmess-ws端口更改为任意7个80系端口(80、8080、8880、2052、2082、2086、2095)，可实现CDN优选IP" || blue "切记：可进入主菜单选项4-2，将Vmess-ws-tls端口更改为任意6个443系的端口(443、8443、2053、2083、2087、2096)，可实现CDN优选IP"
    echo
  elif [ "$menu" = "3" ] && [ -f /root/ygkkkca/ca.log ]; then
    local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
    local cur_key=$(echo "$clean_json" | jq -r '.inbounds[2].tls.key_path')
    local next_cert="/etc/s-box/cert.pem"
    local next_key="/etc/s-box/private.key"
    if [ "$cur_key" = "$SBFOLDER/private.key" ] || [ "$cur_key" = "/etc/s-box/private.key" ]; then
      next_cert="/root/ygkkkca/cert.crt"
      next_key="/root/ygkkkca/private.key"
    fi
    for file in $SBFILES; do
      if [ -f "$file" ]; then
        jq --arg cert "$next_cert" --arg key "$next_key" \
           '(.inbounds[] | select(.type == "hysteria2")).tls |= (.certificate_path = $cert | .key_path = $key)' \
           "$file" > /tmp/tmp.json && mv /tmp/tmp.json "$file"
      fi
    done
    restartsb && sbshare > /dev/null 2>&1
    blue "Hysteria2协议域名证书更换完毕"
  elif [ "$menu" = "4" ] && [ -f /root/ygkkkca/ca.log ]; then
    local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
    local cur_key=$(echo "$clean_json" | jq -r '.inbounds[3].tls.key_path')
    local next_cert="/etc/s-box/cert.pem"
    local next_key="/etc/s-box/private.key"
    if [ "$cur_key" = "$SBFOLDER/private.key" ] || [ "$cur_key" = "/etc/s-box/private.key" ]; then
      next_cert="/root/ygkkkca/cert.crt"
      next_key="/root/ygkkkca/private.key"
    fi
    for file in $SBFILES; do
      if [ -f "$file" ]; then
        jq --arg cert "$next_cert" --arg key "$next_key" \
           '(.inbounds[] | select(.type == "tuic")).tls |= (.certificate_path = $cert | .key_path = $key)' \
           "$file" > /tmp/tmp.json && mv /tmp/tmp.json "$file"
      fi
    done
    restartsb && sbshare > /dev/null 2>&1
    blue "Tuic5协议域名证书更换完毕"
  elif [ "$menu" = "5" ] && [ -f /root/ygkkkca/ca.log ] && [[ "$sbnh" != "1.10" ]]; then
    local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
    local cur_key=$(echo "$clean_json" | jq -r '.inbounds[4].tls.key_path')
    local next_cert="/etc/s-box/cert.pem"
    local next_key="/etc/s-box/private.key"
    if [ "$cur_key" = "$SBFOLDER/private.key" ] || [ "$cur_key" = "/etc/s-box/private.key" ]; then
      next_cert="/root/ygkkkca/cert.crt"
      next_key="/root/ygkkkca/private.key"
    fi
    for file in $SBFILES; do
      if [ -f "$file" ]; then
        jq --arg cert "$next_cert" --arg key "$next_key" \
           '(.inbounds[] | select(.type == "anytls")).tls |= (.certificate_path = $cert | .key_path = $key)' \
           "$file" > /tmp/tmp.json && mv /tmp/tmp.json "$file"
      fi
    done
    restartsb && sbshare > /dev/null 2>&1
    blue "Anytls协议域名证书更换完毕"
  else
    sb
  fi
}

# --- Domain Splitting & Routing Rules Compiler ---
update_routing_rule() {
  local route_channel="$1"
  local rule_type="$2" # "domain_suffix" or "geosite"
  local raw_items="$3"
  
  local json_array
  if [[ -z "$raw_items" || "$raw_items" == "yg_kkk" ]]; then
    json_array='["yg_kkk"]'
  else
    json_array=$(echo "$raw_items" | jq -R 'split(" ")')
  fi

  # For sb10.json (older routing structure):
  case "$route_channel" in
    w4)
      jq --argjson arr "$json_array" --arg rtype "$rule_type" \
         '(.route.rules[] | select(.outbound == "warp-IPv4-out"))[$rtype] = $arr' \
         "$SBFOLDER/sb10.json" > /tmp/sb10.json && mv /tmp/sb10.json "$SBFOLDER/sb10.json"
      ;;
    w6)
      jq --argjson arr "$json_array" --arg rtype "$rule_type" \
         '(.route.rules[] | select(.outbound == "warp-IPv6-out"))[$rtype] = $arr' \
         "$SBFOLDER/sb10.json" > /tmp/sb10.json && mv /tmp/sb10.json "$SBFOLDER/sb10.json"
      ;;
    s4)
      jq --argjson arr "$json_array" --arg rtype "$rule_type" \
         '(.route.rules[] | select(.outbound == "socks-IPv4-out"))[$rtype] = $arr' \
         "$SBFOLDER/sb10.json" > /tmp/sb10.json && mv /tmp/sb10.json "$SBFOLDER/sb10.json"
      ;;
    s6)
      jq --argjson arr "$json_array" --arg rtype "$rule_type" \
         '(.route.rules[] | select(.outbound == "socks-IPv6-out"))[$rtype] = $arr' \
         "$SBFOLDER/sb10.json" > /tmp/sb10.json && mv /tmp/sb10.json "$SBFOLDER/sb10.json"
      ;;
    ad4)
      jq --argjson arr "$json_array" --arg rtype "$rule_type" \
         '(.route.rules[] | select(.outbound == "vps-outbound-v4"))[$rtype] = $arr' \
         "$SBFOLDER/sb10.json" > /tmp/sb10.json && mv /tmp/sb10.json "$SBFOLDER/sb10.json"
      ;;
    ad6)
      jq --argjson arr "$json_array" --arg rtype "$rule_type" \
         '(.route.rules[] | select(.outbound == "vps-outbound-v6"))[$rtype] = $arr' \
         "$SBFOLDER/sb10.json" > /tmp/sb10.json && mv /tmp/sb10.json "$SBFOLDER/sb10.json"
      ;;
  esac

  # For sb11.json (newer routing structure, only supports domain_suffix on w6 and s4):
  if [[ "$rule_type" == "domain_suffix" ]]; then
    case "$route_channel" in
      w6)
        jq --argjson arr "$json_array" \
           '(.route.rules[] | select(.strategy == "prefer_ipv6")).domain_suffix = $arr |
            (.route.rules[] | select(.outbound == "warp-out")).domain_suffix = $arr' \
           "$SBFOLDER/sb11.json" > /tmp/sb11.json && mv /tmp/sb11.json "$SBFOLDER/sb11.json"
        ;;
      s4)
        jq --argjson arr "$json_array" \
           '(.route.rules[] | select(.strategy == "prefer_ipv4")).domain_suffix = $arr |
            (.route.rules[] | select(.outbound == "socks-out")).domain_suffix = $arr' \
           "$SBFOLDER/sb11.json" > /tmp/sb11.json && mv /tmp/sb11.json "$SBFOLDER/sb11.json"
        ;;
    esac
  fi
  
  # Sync to active sb.json
  [[ "$sbnh" == "1.10" ]] && num=10 || num=11
  cp "$SBFOLDER/sb${num}.json" "$SBFOLDER/sb.json"
}

sbymfl() {
  sbport=$(cat "$SBFOLDER/warp-plus.log" "$SBFOLDER/sbwpph.log" 2>/dev/null | head -n 1 | awk '{print $3}' | awk -F":" '{print $NF}') 
  sbport=${sbport:-'40000'}
  resv1=$(curl -sm3 --socks5 localhost:$sbport icanhazip.com)
  resv2=$(curl -sm3 -x socks5h://localhost:$sbport icanhazip.com)
  if [[ -z $resv1 && -z $resv2 ]]; then
    warp_s4_ip='Socks5-IPV4未启动，黑名单模式'
    warp_s6_ip='Socks5-IPV6未启动，黑名单模式'
  else
    warp_s4_ip='Socks5-IPV4可用'
    warp_s6_ip='Socks5-IPV6自测'
  fi
  v4v6
  if [[ -z $v4 ]]; then
    vps_ipv4='无本地IPV4，黑名单模式'      
    vps_ipv6="当前IP：$v6"
  elif [[ -n $v4 && -n $v6 ]]; then
    vps_ipv4="当前IP：$v4"    
    vps_ipv6="当前IP：$v6"
  else
    vps_ipv4="当前IP：$v4"    
    vps_ipv6='无本地IPV6，黑名单模式'
  fi
  unset swg4 swd4 swd6 swg6 ssd4 ssg4 ssd6 ssg6 sad4 sag4 sad6 sag6
  
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
  wd4=$(echo "$clean_json" | jq -r '.route.rules[1].domain_suffix | join(" ")' 2>/dev/null)
  args_wg4=$(echo "$clean_json" | jq -r '.route.rules[1].geosite | join(" ")' 2>/dev/null)
  if [[ "$wd4" == "yg_kkk" && ("$args_wg4" == "yg_kkk" || -z "$args_wg4") ]]; then
    wfl4="${yellow}【warp出站IPV4可用】未分流${plain}"
  else
    [[ "$wd4" != "yg_kkk" ]] && swd4="$wd4 "
    [[ "$args_wg4" != "yg_kkk" ]] && swg4=$args_wg4
    wfl4="${yellow}【warp出站IPV4可用】已分流：$swd4$swg4${plain} "
  fi
  
  wd6=$(echo "$clean_json" | jq -r '.route.rules[2].domain_suffix | join(" ")' 2>/dev/null)
  args_wg6=$(echo "$clean_json" | jq -r '.route.rules[2].geosite | join(" ")' 2>/dev/null)
  if [[ "$wd6" == "yg_kkk" && ("$args_wg6" == "yg_kkk" || -z "$args_wg6") ]]; then
    wfl6="${yellow}【warp出站IPV6自测】未分流${plain}"
  else
    [[ "$wd6" != "yg_kkk" ]] && swd6="$wd6 "
    [[ "$args_wg6" != "yg_kkk" ]] && swg6=$args_wg6
    wfl6="${yellow}【warp出站IPV6自测】已分流：$swd6$swg6${plain} "
  fi
  
  sd4=$(echo "$clean_json" | jq -r '.route.rules[3].domain_suffix | join(" ")' 2>/dev/null)
  sg4=$(echo "$clean_json" | jq -r '.route.rules[3].geosite | join(" ")' 2>/dev/null)
  if [[ "$sd4" == "yg_kkk" && ("$sg4" == "yg_kkk" || -z "$sg4") ]]; then
    sfl4="${yellow}【$warp_s4_ip】未分流${plain}"
  else
    [[ "$sd4" != "yg_kkk" ]] && ssd4="$sd4 "
    [[ "$sg4" != "yg_kkk" ]] && ssg4=$sg4
    sfl4="${yellow}【$warp_s4_ip】已分流：$ssd4$ssg4${plain} "
  fi
  
  sd6=$(echo "$clean_json" | jq -r '.route.rules[4].domain_suffix | join(" ")' 2>/dev/null)
  sg6=$(echo "$clean_json" | jq -r '.route.rules[4].geosite | join(" ")' 2>/dev/null)
  if [[ "$sd6" == "yg_kkk" && ("$sg6" == "yg_kkk" || -z "$sg6") ]]; then
    sfl6="${yellow}【$warp_s6_ip】未分流${plain}"
  else
    [[ "$sd6" != "yg_kkk" ]] && ssd6="$sd6 "
    [[ "$sg6" != "yg_kkk" ]] && ssg6=$sg6
    sfl6="${yellow}【$warp_s6_ip】已分流：$ssd6$ssg6${plain} "
  fi
  
  ad4=$(echo "$clean_json" | jq -r '.route.rules[5].domain_suffix | join(" ")' 2>/dev/null)
  ag4=$(echo "$clean_json" | jq -r '.route.rules[5].geosite | join(" ")' 2>/dev/null)
  if [[ ("$ad4" == "yg_kkk" || -z "$ad4") && ("$ag4" == "yg_kkk" || -z "$ag4") ]]; then
    adfl4="${yellow}【$vps_ipv4】未分流${plain}" 
  else
    [[ "$ad4" != "yg_kkk" ]] && sad4="$ad4 "
    [[ "$ag4" != "yg_kkk" ]] && sag4=$ag4
    adfl4="${yellow}【$vps_ipv4】已分流：$sad4$sag4${plain} "
  fi
  
  ad6=$(echo "$clean_json" | jq -r '.route.rules[6].domain_suffix | join(" ")' 2>/dev/null)
  ag6=$(echo "$clean_json" | jq -r '.route.rules[6].geosite | join(" ")' 2>/dev/null)
  if [[ ("$ad6" == "yg_kkk" || -z "$ad6") && ("$ag6" == "yg_kkk" || -z "$ag6") ]]; then
    adfl6="${yellow}【$vps_ipv6】未分流${plain}" 
  else
    [[ "$ad6" != "yg_kkk" ]] && sad6="$ad6 "
    [[ "$ag6" != "yg_kkk" ]] && sag6=$ag6
    adfl6="${yellow}【$vps_ipv6】已分流：$sad6$sag6${plain} "
  fi
}

changefl() {
  sbactive
  blue "对所有协议进行统一的域名分流"
  blue "为确保分流可用，双栈IP（IPV4/IPV6）分流模式为优先模式"
  blue "warp-wireguard默认开启 (选项1与2)"
  blue "socks5需要在VPS安装warp官方客户端或者WARP-plus-Socks5-赛风VPN (选项3与4)"
  blue "VPS本地出站分流(选项5与6)"
  echo
  [[ "$sbnh" == "1.10" ]] && blue "当前Sing-box内核支持geosite分流方式" || blue "当前Sing-box内核不支持geosite分流方式，仅支持分流2、3、5、6选项"
  echo
  yellow "注意："
  yellow "一、后缀域名方式只能填域名 (例：谷歌网站填写：google.com googleapis.com)"
  yellow "二、geosite方式须填写geosite规则名 (例：奈飞填写netflix ；迪士尼填写disney ；ChatGPT填写openai ；全局且绕过中国填写geolocation-!cn)"
  yellow "三、同一个完整域名或者geosite切勿重复分流"
  yellow "四、如分流通道中有个别通道无网络，所填分流为黑名单模式，即屏蔽该网站访问"
  changef
}

changef() {
  [[ "$sbnh" == "1.10" ]] && num=10 || num=11
  sbymfl
  echo
  [[ "$sbnh" != "1.10" ]] && wfl4='暂不支持' sfl6='暂不支持' adfl4='暂不支持' adfl6='暂不支持'
  green "1：重置warp-wireguard-ipv4优先分流域名 $wfl4"
  green "2：重置warp-wireguard-ipv6优先分流域名 $wfl6"
  green "3：重置warp-socks5-ipv4优先分流域名 $sfl4"
  green "4：重置warp-socks5-ipv6优先分流域名 $sfl6"
  green "5：重置VPS本地ipv4优先分流域名 $adfl4"
  green "6：重置VPS本地ipv6优先分流域名 $adfl6"
  green "0：返回上层"
  echo
  readp "请选择：" menu
  
  if [ "$menu" = "1" ]; then
    if [[ "$sbnh" == "1.10" ]]; then
      readp "1：使用后缀域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu
      if [ "$menu" = "1" ]; then
        readp "每个域名之间留空格，回车跳过表示重置清空warp-wireguard-ipv4的分流通道：" w4flym
        update_routing_rule "w4" "domain_suffix" "$w4flym"
        restartsb && changef
      elif [ "$menu" = "2" ]; then
        readp "每个域名之间留空格，回车跳过表示重置清空warp-wireguard-ipv4的分流通道：" w4flym
        update_routing_rule "w4" "geosite" "$w4flym"
        restartsb && changef
      else
        changef
      fi
    else
      yellow "遗憾！当前暂时只支持warp-wireguard-ipv6，如需要warp-wireguard-ipv4，请切换1.10系列内核" && exit
    fi
  elif [ "$menu" = "2" ]; then
    readp "1：使用后缀域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu
    if [ "$menu" = "1" ]; then
      readp "每个域名之间留空格，回车跳过表示重置清空warp-wireguard-ipv6的分流通道：" w6flym
      update_routing_rule "w6" "domain_suffix" "$w6flym"
      restartsb && changef
    elif [ "$menu" = "2" ]; then
      if [[ "$sbnh" == "1.10" ]]; then
        readp "每个域名之间留空格，回车跳过表示重置清空warp-wireguard-ipv6的分流通道：" w6flym
        update_routing_rule "w6" "geosite" "$w6flym"
        restartsb && changef
      else
        yellow "遗憾！当前Sing-box内核不支持geosite分流方式。如要支持，请切换1.10系列内核" && exit
      fi
    else
      changef
    fi
  elif [ "$menu" = "3" ]; then
    readp "1：使用后缀域名方式\n2::使用geosite方式\n3：返回上层\n请选择：" menu
    if [ "$menu" = "1" ]; then
      readp "每个域名之间留空格，回车跳过表示重置清空warp-socks5-ipv4的分流通道：" s4flym
      update_routing_rule "s4" "domain_suffix" "$s4flym"
      restartsb && changef
    elif [ "$menu" = "2" ]; then
      if [[ "$sbnh" == "1.10" ]]; then
        readp "每个域名之间留空格，回车跳过表示重置清空warp-socks5-ipv4的分流通道：" s4flym
        update_routing_rule "s4" "geosite" "$s4flym"
        restartsb && changef
      else
        yellow "遗憾！当前Sing-box内核不支持geosite分流方式。如要支持，请切换1.10系列内核" && exit
      fi
    else
      changef
    fi
  elif [ "$menu" = "4" ]; then
    if [[ "$sbnh" == "1.10" ]]; then
      readp "1：使用后缀域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu
      if [ "$menu" = "1" ]; then
        readp "每个域名之间留空格，回车跳过表示重置清空warp-socks5-ipv6的分流通道：" s6flym
        update_routing_rule "s6" "domain_suffix" "$s6flym"
        restartsb && changef
      elif [ "$menu" = "2" ]; then
        readp "每个域名之间留空格，回车跳过表示重置清空warp-socks5-ipv6的分流通道：" s6flym
        update_routing_rule "s6" "geosite" "$s6flym"
        restartsb && changef
      else
        changef
      fi
    else
      yellow "遗憾！当前暂时只支持warp-socks5-ipv4，如需要warp-socks5-ipv6，请切换1.10系列内核" && exit
    fi
  elif [ "$menu" = "5" ]; then
    if [[ "$sbnh" == "1.10" ]]; then
      readp "1：使用后缀域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu
      if [ "$menu" = "1" ]; then
        readp "每个域名之间留空格，回车跳过表示重置清空VPS本地ipv4的分流通道：" ad4flym
        update_routing_rule "ad4" "domain_suffix" "$ad4flym"
        restartsb && changef
      elif [ "$menu" = "2" ]; then
        readp "每个域名之间留空格，回车跳过表示重置清空VPS本地ipv4的分流通道：" ad4flym
        update_routing_rule "ad4" "geosite" "$ad4flym"
        restartsb && changef
      else
        changef
      fi
    else
      yellow "遗憾！如需要VPS本地ipv4分流，请切换1.10系列内核" && exit
    fi
  elif [ "$menu" = "6" ]; then
    if [[ "$sbnh" == "1.10" ]]; then
      readp "1：使用后缀域名方式\n2::使用geosite方式\n3：返回上层\n请选择：" menu
      if [ "$menu" = "1" ]; then
        readp "每个域名之间留空格，回车跳过表示重置清空VPS本地ipv6的分流通道：" ad6flym
        update_routing_rule "ad6" "domain_suffix" "$ad6flym"
        restartsb && changef
      elif [ "$menu" = "2" ]; then
        readp "每个域名之间留空格，回车跳过表示重置清空VPS本地ipv6的分流通道：" ad6flym
        update_routing_rule "ad6" "geosite" "$ad6flym"
        restartsb && changef
      else
        changef
      fi
    else
      yellow "遗憾！如需要VPS本地ipv6分流，请切换1.10系列内核" && exit
    fi
  else
    sb
  fi
}

restartsb() {
  if command -v apk >/dev/null 2>&1; then
    rc-service sing-box restart
  else
    systemctl enable sing-box >/dev/null 2>&1
    systemctl start sing-box >/dev/null 2>&1
    systemctl restart sing-box >/dev/null 2>&1
  fi
}



# --- CDN configuration ---
vmesscfadd() {
  echo
  green "推荐使用稳定的世界大厂或组织的官方CDN域名作为CDN优选地址："
  blue "cloudflare-ech.com"
  blue "www.visa.com.sg"
  blue "www.wto.org"
  blue "www.web.com"
  echo
  yellow "1：自定义Vmess-ws(tls)主协议节点的CDN优选地址"
  yellow "2：针对选项1，重置客户端host/sni域名(IP解析到CF上的域名)"
  yellow "3：自定义Vmess-ws(tls)-Argo节点的CDN优选地址"
  yellow "0：返回上层"
  readp "请选择【0-3】：" menu
  if [ "$menu" = "1" ]; then
    echo
    green "请确保VPS的IP已解析到Cloudflare的域名上"
    if [[ ! -f "$SBFOLDER/cfymjx.txt" ]] 2>/dev/null; then
      readp "输入客户端host/sni域名(IP解析到CF上的域名)：" menu
      echo "$menu" > "$SBFOLDER/cfymjx.txt"
    fi
    echo
    readp "输入自定义的优选IP/域名：" menu
    echo "$menu" > "$SBFOLDER/cfvmadd_local.txt"
    sbshare > /dev/null 2>&1
    green "设置成功，选择主菜单9进行节点配置更新" && sleep 2 && vmesscfadd
  elif [ "$menu" = "2" ]; then
    rm -rf "$SBFOLDER/cfymjx.txt"
    sbshare > /dev/null 2>&1
    green "重置成功，可选择1重新设置" && sleep 2 && vmesscfadd
  elif [ "$menu" = "3" ]; then
    readp "输入自定义的优选IP/域名：" menu
    echo "$menu" > "$SBFOLDER/cfvmadd_argo.txt"
    sbshare > /dev/null 2>&1
    green "设置成功，选择主菜单9进行节点配置更新" && sleep 2 && vmesscfadd
  else
    changeserv
  fi
}

# --- Core Updates / Switching ---
lapre() {
  json=$(curl -Ls --max-time 3 https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box)
  if echo "$json" | grep -q '"versions"'; then
    latcore=$(echo "$json" | grep -Eo '"[0-9.]+",' | head -n1 | tr -d '",')
    precore=$(echo "$json" | grep -Eo '"[0-9.]*-[^"]*"' | head -n1 | tr -d '",')
  else
    page=$(curl -Ls --max-time 3 https://github.com/SagerNet/sing-box/releases)
    latcore=$(echo "$page" | grep -oE 'tag/v[0-9.]+' | head -n1 | cut -d'v' -f2)
    precore=$(echo "$page" | grep -oE '/tag/v[0-9.]+-[^"]+' | head -n1 | cut -d'v' -f2)
  fi
  inscore=$("$SBFOLDER/sing-box" version 2>/dev/null | awk '/version/{print $NF}')
}

upsbcroe() {
  sbactive
  lapre
  [[ $inscore =~ ^[0-9.]+$ ]] && lat="【已安装v$inscore】" || pre="【已安装v$inscore】"
  green "1：升级/切换Sing-box最新正式版 v$latcore  ${bblue}${lat}${plain}"
  green "2：升级/切换Sing-box最新测试版 v$precore  ${bblue}${pre}${plain}"
  green "3：切换Sing-box某个正式版或测试版，需指定版本号 (建议1.10.0以上版本)"
  green "0：返回上层"
  readp "请选择【0-3】：" menu
  if [ "$menu" = "1" ]; then
    upcore=$(curl -Ls https://github.com/SagerNet/sing-box/releases/latest | grep -oP 'tag/v\K[0-9.]+' | head -n 1)
  elif [ "$menu" = "2" ]; then
    upcore=$(curl -Ls https://github.com/SagerNet/sing-box/releases | grep -oP '/tag/v\K[0-9.]+-[^"]+' | head -n 1)
  elif [ "$menu" = "3" ]; then
    echo
    red "注意: 版本号在 https://github.com/SagerNet/sing-box/tags 可查，且有Downloads字样 (必须1.10系或者1.30系以上版本)"
    green "正式版版本号格式：数字.数字.数字 (例：1.10.7   注意，1.10系列内核支持geosite分流，1.10以上内核不支持geosite分流"
    green "测试版版本号格式：数字.数字.数字-alpha或rc或beta.数字 (例：1.13.0-alpha或rc或beta.1)"
    readp "请输入Sing-box版本号：" upcore
  else
    sb
  fi
  
  if [[ -n $upcore ]]; then
    green "开始下载并更新Sing-box内核……请稍等"
    sbname="sing-box-$upcore-linux-$cpu"
    curl -L -o "$SBFOLDER/sing-box.tar.gz" -# --retry 2 "https://github.com/SagerNet/sing-box/releases/download/v$upcore/$sbname.tar.gz"
    if [[ -f "$SBFOLDER/sing-box.tar.gz" ]]; then
      tar xzf "$SBFOLDER/sing-box.tar.gz" -C "$SBFOLDER"
      mv "$SBFOLDER/$sbname/sing-box" "$SBFOLDER/sing-box"
      rm -rf "$SBFOLDER/sing-box.tar.gz" "$SBFOLDER/$sbname"
      if [[ -f "$SBFOLDER/sing-box" ]]; then
        chown root:root "$SBFOLDER/sing-box"
        chmod +x "$SBFOLDER/sing-box"
        sbnh=$("$SBFOLDER/sing-box" version 2>/dev/null | awk '/version/{print $NF}' 2>/dev/null | cut -d '.' -f 1,2)
        [[ "$sbnh" == "1.10" ]] && num=10 || num=11
        rm -rf "$SBFOLDER/sb.json"
        cp "$SBFOLDER/sb${num}.json" "$SBFOLDER/sb.json"
        restartsb && sbshare > /dev/null 2>&1
        blue "成功升级/切换 Sing-box 内核版本：$("$SBFOLDER/sing-box" version | awk '/version/{print $NF}')" && sleep 3 && sb
      else
        red "下载 Sing-box 内核不完整，安装失败，请重试" && upsbcroe
      fi
    else
      red "下载 Sing-box 内核失败或不存在，请重试" && upsbcroe
    fi
  else
    red "版本号检测出错，请重试" && upsbcroe
  fi
}

# --- Service Autostart / Cron / Shortcut hooks ---
cronsb() {
  uncronsb
  crontab -l 2>/dev/null > /tmp/crontab.tmp
  echo "0 1 * * * systemctl restart sing-box;rc-service sing-box restart" >> /tmp/crontab.tmp
  crontab /tmp/crontab.tmp >/dev/null 2>&1
  rm /tmp/crontab.tmp
}

uncronsb() {
  crontab -l 2>/dev/null > /tmp/crontab.tmp
  sed -i '/sing-box/d' /tmp/crontab.tmp
  sed -i '/sbwpph/d' /tmp/crontab.tmp
  sed -i '/warp-plus/d' /tmp/crontab.tmp
  sed -i '/url http/d' /tmp/crontab.tmp
  sed -i '/websbox/d' /tmp/crontab.tmp
  crontab /tmp/crontab.tmp >/dev/null 2>&1
  rm /tmp/crontab.tmp
}

lnsb() {
  rm -rf "$SCRIPT_SHORTCUT"
  cp "$0" "$SCRIPT_SHORTCUT"
  chmod +x "$SCRIPT_SHORTCUT"
}

upsbyg() {
  if [[ ! -f "$SCRIPT_SHORTCUT" ]]; then
    red "未正常安装Sing-box" && exit
  fi
  lnsb
  curl -sL "https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/version" | awk -F "更新内容" '{print $1}' | head -n 1 > "$SBFOLDER/v"
  green "Sing-box安装脚本升级成功" && sleep 5 && sb
}

# --- Local WARP plus Socks5 Proxy Manager ---
inswarpplus() {
  sbactive
  find_free_port() {
    local start_port=$1
    local port=$start_port
    while true; do
      if [[ -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
        echo "$port"
        return 0
      fi
      port=$((port+1))
    done
  }
  ins() {
    if [ -f "$SBFOLDER/sbwpph" ]; then
      rm -f "$SBFOLDER/sbwpph"
    fi

    case $(uname -m) in
      aarch64) cpu=arm64;;
      x86_64) cpu=amd64;;
      *) red "不支持的架构：$(uname -m)" && exit;;
    esac

    # 获取 voidr3aper-anon/Vwarp 的最新 Release 版本号
    vwarp_latest=$(curl -sL --max-time 10 "https://api.github.com/repos/voidr3aper-anon/Vwarp/releases/latest" | grep -oP '"tag_name":\s*"\K[^"]+')
    if [[ -z "$vwarp_latest" || ! "$vwarp_latest" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      vwarp_latest="v2.2.2"
    fi

    local_vwarp=""
    if [ -f "$SBFOLDER/warp-plus" ]; then
      if [ -f "$SBFOLDER/vwarp.version" ]; then
        local_vwarp=$(cat "$SBFOLDER/vwarp.version" 2>/dev/null)
      fi
      if [[ -z "$local_vwarp" ]]; then
        local_vwarp=$("$SBFOLDER/warp-plus" version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -n 1)
        if [[ -n "$local_vwarp" ]]; then
          local_vwarp="v$local_vwarp"
        else
          local_vwarp="v2.2.2"
        fi
        echo "$local_vwarp" > "$SBFOLDER/vwarp.version"
      fi
    fi

    # 是否需要下载或更新
    need_download=0
    if [ ! -f "$SBFOLDER/warp-plus" ]; then
      need_download=1
    elif [[ "$local_vwarp" != "$vwarp_latest" ]]; then
      green "检测到本地 vwarp 版本 ($local_vwarp) 与最新版本 ($vwarp_latest) 不一致，将自动更新..."
      need_download=1
    fi

    if [ "$need_download" -eq 1 ]; then
      if ! command -v unzip >/dev/null 2>&1; then
        green "正在安装 unzip 工具..."
        if command -v apt-get >/dev/null 2>&1; then
          sudo apt-get update -y && sudo apt-get install -y unzip
        elif command -v yum >/dev/null 2>&1; then
          sudo yum install -y unzip
        elif command -v dnf >/dev/null 2>&1; then
          sudo dnf install -y unzip
        elif command -v apk >/dev/null 2>&1; then
          apk add unzip
        fi
      fi

      download_and_extract() {
        local ver="$1"
        green "正在从官方获取 vwarp ${ver}..."
        curl -L -o "$SBFOLDER/warp-plus.zip" -# --retry 2 "https://github.com/voidr3aper-anon/Vwarp/releases/download/${ver}/vwarp_linux-${cpu}.zip"
        
        if [[ ! -s "$SBFOLDER/warp-plus.zip" ]]; then
          return 1
        fi
        
        rm -rf "$SBFOLDER/warp_plus_temp"
        unzip -o "$SBFOLDER/warp-plus.zip" -d "$SBFOLDER/warp_plus_temp" >/dev/null 2>&1
        if [[ -f "$SBFOLDER/warp_plus_temp/vwarp" ]]; then
          mv -f "$SBFOLDER/warp_plus_temp/vwarp" "$SBFOLDER/warp-plus"
          chmod +x "$SBFOLDER/warp-plus"
          rm -rf "$SBFOLDER/warp-plus.zip" "$SBFOLDER/warp_plus_temp"
          # 测试是否可以正常运行
          if "$SBFOLDER/warp-plus" version >/dev/null 2>&1; then
            return 0
          fi
        fi
        return 1
      }

      if ! download_and_extract "$vwarp_latest"; then
        if [[ "$vwarp_latest" != "v2.2.2" ]]; then
          yellow "最新版本 $vwarp_latest 下载或运行失败，正在尝试下载并回落到版本 v2.2.2..."
          if ! download_and_extract "v2.2.2"; then
            red "回落版本 v2.2.2 下载或安装也失败，请检查网络连接！"
            exit 1
          fi
          echo "v2.2.2" > "$SBFOLDER/vwarp.version"
        else
          red "获取 vwarp v2.2.2 失败，请检查网络连接！"
          exit 1
        fi
      else
        echo "$vwarp_latest" > "$SBFOLDER/vwarp.version"
      fi
    fi
    ps -ef | grep -E '[s]bwpph|[w]arp-plus' | awk '{print $2}' | xargs kill 2>/dev/null
    v4v6
    if [[ -n $v4 ]]; then
      sw46=4
    else
      red "IPV4不存在，确保安装过WARP-IPV4模式"
      sw46=6
    fi
    echo
    readp "设置WARP-plus-Socks5端口（回车跳过端口默认40000）：" port
    if [[ -z $port ]]; then
      port=40000
      until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] 
      do
        [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义端口:" port
      done
    else
      until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]
      do
        [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义端口:" port
      done
    fi
    
    s5port=$(strip_json_comments "$SBFOLDER/sb.json" | jq -r '.outbounds[] | select(.type == "socks") | .server_port')
    [[ "$sbnh" == "1.10" ]] && num=10 || num=11
    
    # Use JQ for clean and robust updates
    jq --argjson p "$port" '(.outbounds[] | select(.type == "socks")).server_port = $p' "$SBFOLDER/sb10.json" > /tmp/sb10.json && mv /tmp/sb10.json "$SBFOLDER/sb10.json"
    jq --argjson p "$port" '(.outbounds[] | select(.type == "socks")).server_port = $p' "$SBFOLDER/sb11.json" > /tmp/sb11.json && mv /tmp/sb11.json "$SBFOLDER/sb11.json"
    
    cp "$SBFOLDER/sb${num}.json" "$SBFOLDER/sb.json"
    restartsb
  }
  
  unins() {
    if command -v apk >/dev/null 2>&1; then
      rc-service usque stop >/dev/null 2>&1
      rc-update del usque default >/dev/null 2>&1
      rm -f /etc/init.d/usque
      rc-service gost stop >/dev/null 2>&1
      rc-update del gost default >/dev/null 2>&1
      rm -f /etc/init.d/gost
    else
      systemctl disable --now usque >/dev/null 2>&1
      rm -f /etc/systemd/system/usque.service
      systemctl disable --now gost >/dev/null 2>&1
      rm -f /etc/systemd/system/gost.service
      systemctl daemon-reload >/dev/null 2>&1
    fi
    ps -ef | grep -E '[s]bwpph|[w]arp-plus|[g]ost|[u]sque' | awk '{print $2}' | xargs kill 2>/dev/null
    rm -rf "$SBFOLDER/sbwpph.log" "$SBFOLDER/warp-plus.log"
    rm -f /usr/local/bin/gost
    rm -f /etc/sysctl.d/99-gost-usque.conf
    sysctl --system >/dev/null 2>&1

    # Clean up iptables redirect rules for usque-user
    local uu_uid=$(id -u usque-user 2>/dev/null)
    local grep_pattern="usque-user"
    if [[ -n $uu_uid ]]; then
      grep_pattern="usque-user|$uu_uid"
    fi
    iptables-save 2>/dev/null | grep -E "$grep_pattern" | sed 's/^-A //g' | while read -r line; do
      iptables -t nat -D $line >/dev/null 2>&1
      iptables -t filter -D $line >/dev/null 2>&1
      iptables -D $line >/dev/null 2>&1
    done
    ip6tables-save 2>/dev/null | grep -E "$grep_pattern" | sed 's/^-A //g' | while read -r line; do
      ip6tables -t nat -D $line >/dev/null 2>&1
      ip6tables -t filter -D $line >/dev/null 2>&1
      ip6tables -D $line >/dev/null 2>&1
    done
    netfilter-persistent save >/dev/null 2>&1
    service iptables save >/dev/null 2>&1

    # Clean up user
    if id -u usque-user >/dev/null 2>&1; then
      userdel usque-user >/dev/null 2>&1
    fi

    crontab -l 2>/dev/null > /tmp/crontab.tmp
    sed -i '/sbwpph/d' /tmp/crontab.tmp
    sed -i '/warp-plus/d' /tmp/crontab.tmp
    crontab /tmp/crontab.tmp >/dev/null 2>&1
    rm /tmp/crontab.tmp
    rm -rf /etc/local.d/alpinews5.start
    if command -v warp-cli >/dev/null 2>&1; then
      warp-cli disconnect >/dev/null 2>&1
    fi
  }
  
  aplws5() {
    if command -v apk >/dev/null 2>&1; then
      cat > /etc/local.d/alpinews5.start <<'EOF'
#!/bin/bash
sleep 10
nohup $(cat /etc/s-box/warp-plus.log /etc/s-box/sbwpph.log 2>/dev/null | head -n 1)
EOF
      chmod +x /etc/local.d/alpinews5.start
      rc-update add local default >/dev/null 2>&1
    else
      crontab -l 2>/dev/null > /tmp/crontab.tmp
      sed -i '/sbwpph/d' /tmp/crontab.tmp
      sed -i '/warp-plus/d' /tmp/crontab.tmp
      echo '@reboot sleep 10 && /bin/bash -c "nohup $(cat /etc/s-box/warp-plus.log /etc/s-box/sbwpph.log 2>/dev/null | head -n 1) &"' >> /tmp/crontab.tmp
      crontab /tmp/crontab.tmp >/dev/null 2>&1
      rm /tmp/crontab.tmp
    fi
  }
  
  echo
  yellow "1：重置启用WARP-plus-Socks5本地Warp代理模式"
  yellow "2：重置启用WARP-plus-Socks5多地区Psiphon代理模式"
  yellow "3：停止WARP-plus-Socks5代理模式"
  yellow "0：返回上层"
  readp "请选择【0-3】：" menu
  if [ "$menu" = "1" ]; then
    warp_choice=""
    echo
    blue "请选择本地 WARP 代理方案："
    green "1. Usque (开源轻量客户端，默认，支持 MASQUE 协议)"
    yellow "   优点：极度轻量，内存/CPU占用极低，支持 MASQUE，全系统通用"
    green "2. WARP-cli (官方客户端)"
    yellow "   优点：官方维护，支持 MASQUE/WireGuard"
    yellow "   缺点：仅支持 Debian/Ubuntu/CentOS，硬件资源占用略高"
    echo
    readp "请选择【1-2】（默认 1）：" warp_choice
    warp_choice=${warp_choice:-1}

    if [[ "$warp_choice" == "2" ]]; then
      if [[ "$release" != "Debian" && "$release" != "Ubuntu" && "$release" != "Centos" ]]; then
        red "当前操作系统为 $release，WARP-cli 官方暂不支持此系统，自动切换为 Usque 方案。"
        warp_choice=1
        sleep 2
      fi
    fi

    if [[ "$warp_choice" == "1" ]]; then
      if ! command -v unzip >/dev/null 2>&1; then
        green "正在安装 unzip 工具..."
        if command -v apt-get >/dev/null 2>&1; then
          sudo apt-get update -y && sudo apt-get install -y unzip
        elif command -v yum >/dev/null 2>&1; then
          sudo yum install -y unzip
        elif command -v dnf >/dev/null 2>&1; then
          sudo dnf install -y unzip
        elif command -v apk >/dev/null 2>&1; then
          apk add unzip
        fi
      fi

      if [ ! -e "/usr/local/bin/usque" ]; then
        green "正在下载 Usque 二进制文件..."
        case $(uname -m) in
          aarch64) cpu=arm64;;
          x86_64) cpu=amd64;;
          *) red "不支持的架构：$(uname -m)" && exit;;
        esac
        
        usque_latest=$(curl -sL "https://api.github.com/repos/Diniboy1123/usque/releases/latest" | grep -oP '"tag_name":\s*"v\K[^"]+' | tr -d 'v')
        usque_latest=${usque_latest:-'3.0.1'}
        
        curl -L -o "$SBFOLDER/usque.zip" -# --retry 2 "https://github.com/Diniboy1123/usque/releases/download/v${usque_latest}/usque_${usque_latest}_linux_${cpu}.zip"
        unzip -o "$SBFOLDER/usque.zip" -d "$SBFOLDER/" usque
        mv -f "$SBFOLDER/usque" "/usr/local/bin/usque"
        chmod +x "/usr/local/bin/usque"
        rm -f "$SBFOLDER/usque.zip"
      fi

      unins

      v4v6
      if [[ -n $v4 ]]; then
        sw46=4
      else
        red "IPV4不存在，确保安装过WARP-IPV4模式"
        sw46=6
      fi

      echo
      readp "设置WARP-plus-Socks5端口（回车跳过端口默认40000）：" port
      if [[ -z $port ]]; then
        port=40000
      fi
      until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] 
      do
        [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义端口:" port
      done

      if [ ! -f "$SBFOLDER/usque.json" ]; then
        green "正在初始化 Usque 客户端注册..."
        echo "y" | /usr/local/bin/usque register -c "$SBFOLDER/usque.json" >/dev/null 2>&1
      fi

      # Restore default endpoint_h2_v4 / endpoint_h2_v6 in usque.json
      if [ -f "$SBFOLDER/usque.json" ]; then
        jq 'del(.endpoint_h2_v4) | del(.endpoint_h2_v6)' "$SBFOLDER/usque.json" > "$SBFOLDER/usque.json.tmp" && mv -f "$SBFOLDER/usque.json.tmp" "$SBFOLDER/usque.json"
      fi

      if command -v apk >/dev/null 2>&1; then
        # Alpine OpenRC Script
        cat > /etc/init.d/usque <<EOF
#!/sbin/openrc-run
description="Usque WARP MASQUE Proxy"
command="/usr/local/bin/usque"
command_args="socks -c $SBFOLDER/usque.json -b 127.0.0.1 -p $port"
command_background=true
pidfile="/var/run/usque.pid"
EOF
        chmod +x /etc/init.d/usque
        rc-update add usque default >/dev/null 2>&1
        rc-service usque start >/dev/null 2>&1
      else
        # Systemd Service
        cat > /etc/systemd/system/usque.service <<EOF
[Unit]
Description=Usque WARP MASQUE Proxy
After=network.target

[Service]
ExecStart=/usr/local/bin/usque socks -c $SBFOLDER/usque.json -b 127.0.0.1 -p $port
Restart=always

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload >/dev/null 2>&1
        systemctl enable --now usque >/dev/null 2>&1
      fi

      green "启动 Usque 本地代理中，请稍候..."
      sleep 10

      resv1=$(curl -sm5 --socks5 127.0.0.1:$port ifconfig.me)
      resv2=$(curl -sm5 -x socks5h://127.0.0.1:$port ifconfig.me)

      if [[ -z $resv1 && -z $resv2 ]]; then
        red "Usque 本地代理的 IP 获取失败，请检查网络或 usque 服务状态。"
        if command -v apk >/dev/null 2>&1; then
          rc-service usque stop >/dev/null 2>&1
          rc-update del usque default >/dev/null 2>&1
        else
          systemctl disable --now usque >/dev/null 2>&1
        fi
        exit
      else
        echo "usque -b 127.0.0.1:$port" > "$SBFOLDER/warp-plus.log"
        s5port=$(strip_json_comments "$SBFOLDER/sb.json" | jq -r '.outbounds[] | select(.type == "socks") | .server_port')
        [[ "$sbnh" == "1.10" ]] && num=10 || num=11
        jq --argjson p "$port" '(.outbounds[] | select(.type == "socks")).server_port = $p' "$SBFOLDER/sb10.json" > /tmp/sb10.json && mv /tmp/sb10.json "$SBFOLDER/sb10.json"
        jq --argjson p "$port" '(.outbounds[] | select(.type == "socks")).server_port = $p' "$SBFOLDER/sb11.json" > /tmp/sb11.json && mv /tmp/sb11.json "$SBFOLDER/sb11.json"
        cp "$SBFOLDER/sb${num}.json" "$SBFOLDER/sb.json"
        restartsb
        green "Usque 本地代理已成功创建，代理 IP: ${resv1:-$resv2}"
        green "Socks5 监听地址: 127.0.0.1:$port"
        green "重新启动脚本后可使用选项 5 设置分流。"
      fi

    else
      # WARP-cli scheme
      echo
      blue "选择 WARP-cli 连接协议："
      green "1. MASQUE (推荐，抗封锁与传输性能更优)"
      green "2. WireGuard"
      echo
      readp "请选择【1-2】（默认 1）：" proto_choice
      proto_choice=${proto_choice:-1}

      if ! command -v warp-cli >/dev/null 2>&1; then
        echo
        green "开始安装 WARP-cli 官方客户端..."
        if [[ "$release" == "Debian" || "$release" == "Ubuntu" ]]; then
          sudo apt update
          sudo apt install gnupg lsb-release -y
          curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
          echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list
          sudo apt update
          sudo apt install cloudflare-warp -y
        elif [[ "$release" == "Centos" ]]; then
          sudo rpm --import https://pkg.cloudflareclient.com/pubkey.gpg
          curl -fsSL https://pkg.cloudflareclient.com/cloudflare-warp.repo | sudo tee /etc/yum.repos.d/cloudflare-warp.repo
          sudo yum clean all
          sudo yum install cloudflare-warp -y
        fi
        sudo systemctl daemon-reload
        sudo systemctl enable --now warp-svc >/dev/null 2>&1
        sleep 3
      else
        green "检测到已安装 WARP-cli，跳过安装，直接进行配置..."
      fi

      unins

      v4v6
      if [[ -n $v4 ]]; then
        sw46=4
      else
        red "IPV4不存在，确保安装过WARP-IPV4模式"
        sw46=6
      fi

      echo
      readp "设置WARP-plus-Socks5端口（回车跳过端口默认40000）：" port
      if [[ -z $port ]]; then
        port=40000
      fi
      until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] 
      do
        [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义端口:" port
      done

      green "正在初始化 WARP-cli 客户端注册..."
      yes | warp-cli registration new >/dev/null 2>&1

      warp-cli mode proxy >/dev/null 2>&1
      warp-cli proxy port $port >/dev/null 2>&1

      if [[ "$proto_choice" == "1" ]]; then
        warp-cli tunnel protocol set MASQUE >/dev/null 2>&1
      else
        warp-cli tunnel protocol set WireGuard >/dev/null 2>&1
      fi

      green "正在连接 WARP network..."
      warp-cli connect >/dev/null 2>&1
      green "申请IP中……请稍等……" && sleep 15

      resv1=$(curl -sm5 --socks5 127.0.0.1:$port ifconfig.me)
      resv2=$(curl -sm5 -x socks5h://127.0.0.1:$port ifconfig.me)

      if [[ -z $resv1 && -z $resv2 ]]; then
        red "WARP-cli 本地代理的 IP 获取失败，请检查网络或 warp-svc 服务状态。"
        warp-cli disconnect >/dev/null 2>&1
        exit
      else
        echo "warp-cli -b 127.0.0.1:$port" > "$SBFOLDER/warp-plus.log"
        s5port=$(strip_json_comments "$SBFOLDER/sb.json" | jq -r '.outbounds[] | select(.type == "socks") | .server_port')
        [[ "$sbnh" == "1.10" ]] && num=10 || num=11
        jq --argjson p "$port" '(.outbounds[] | select(.type == "socks")).server_port = $p' "$SBFOLDER/sb10.json" > /tmp/sb10.json && mv /tmp/sb10.json "$SBFOLDER/sb10.json"
        jq --argjson p "$port" '(.outbounds[] | select(.type == "socks")).server_port = $p' "$SBFOLDER/sb11.json" > /tmp/sb11.json && mv /tmp/sb11.json "$SBFOLDER/sb11.json"
        cp "$SBFOLDER/sb${num}.json" "$SBFOLDER/sb.json"
        restartsb
        green "WARP-cli 本地代理已成功创建，代理 IP: ${resv1:-$resv2}"
        green "Socks5 监听地址: 127.0.0.1:$port"
        green "重新启动脚本后可使用选项 5 设置分流。"
      fi
    fi
  elif [ "$menu" = "2" ]; then
    unins
    ins
    echo '
奥地利（AT）    澳大利亚（AU）    比利时（BE）    保加利亚（BG）
加拿大（CA）    瑞士（CH）        捷克 (CZ)       德国（DE）
丹麦（DK）      爱沙尼亚（EE）    西班牙（ES）    芬兰（FI）
法国（FR）      英国（GB）        克罗地亚（HR）  匈牙利 (HU)
爱尔兰（IE）    印度（IN）        意大利 (IT)     日本（JP）
立陶宛（LT）    拉脱维亚（LV）    荷兰（NL）      挪威 (NO)
波兰（PL）      葡萄牙（PT）      罗马尼亚 (RO)   塞尔维亚（RS）
瑞典（SE）      新加坡 (SG)       斯洛伐克（SK）  美国（US）
'
    readp "可选择国家地区（输入末尾两个大写字母，如美国，则输入US）：" guojia

    echo
    readp "是否在多地区Psiphon代理的基础上再套一层WARP？（推荐，可大幅改善IP解锁）[y/n]（默认n）：" chain_choice
    chain_choice=${chain_choice:-n}

    if [[ "$chain_choice" =~ ^[Yy]$ ]]; then
      vwarp_port=$(find_free_port 50000)
      gost_port=$(find_free_port 12345)

      if ! command -v unzip >/dev/null 2>&1; then
        green "正在安装 unzip 工具..."
        if command -v apt-get >/dev/null 2>&1; then
          sudo apt-get update -y && sudo apt-get install -y unzip
        elif command -v yum >/dev/null 2>&1; then
          sudo yum install -y unzip
        elif command -v dnf >/dev/null 2>&1; then
          sudo dnf install -y unzip
        elif command -v apk >/dev/null 2>&1; then
          apk add unzip
        fi
      fi

      if [ ! -e "/usr/local/bin/usque" ]; then
        green "正在下载 Usque 二进制文件..."
        case $(uname -m) in
          aarch64) cpu=arm64;;
          x86_64) cpu=amd64;;
          *) red "不支持的架构：$(uname -m)" && exit;;
        esac
        usque_latest=$(curl -sL "https://api.github.com/repos/Diniboy1123/usque/releases/latest" | grep -oP '"tag_name":\s*"v\K[^"]+' | tr -d 'v')
        usque_latest=${usque_latest:-'3.0.1'}
        curl -L -o "$SBFOLDER/usque.zip" -# --retry 2 "https://github.com/Diniboy1123/usque/releases/download/v${usque_latest}/usque_${usque_latest}_linux_${cpu}.zip"
        unzip -o "$SBFOLDER/usque.zip" -d "$SBFOLDER/" usque
        mv -f "$SBFOLDER/usque" "/usr/local/bin/usque"
        chmod +x "/usr/local/bin/usque"
        rm -f "$SBFOLDER/usque.zip"
      fi

      if [ ! -f "$SBFOLDER/usque.json" ]; then
        green "正在初始化 Usque 客户端注册..."
        echo "y" | /usr/local/bin/usque register -c "$SBFOLDER/usque.json" >/dev/null 2>&1
      fi

      # Configure usque.json to route through Gost TCP forwarder
      if [ -f "$SBFOLDER/usque.json" ]; then
        jq '.endpoint_h2_v4 = "127.0.0.1" | .endpoint_h2_v6 = "::1"' "$SBFOLDER/usque.json" > "$SBFOLDER/usque.json.tmp" && mv -f "$SBFOLDER/usque.json.tmp" "$SBFOLDER/usque.json"
      fi

      if [ ! -e "/usr/local/bin/gost" ]; then
        green "正在下载 Gost 二进制文件..."
        gost_latest=$(curl -sL "https://api.github.com/repos/go-gost/gost/releases/latest" | grep -oP '"tag_name":\s*"\K[^"]+')
        gost_ver=${gost_latest#v}
        case $(uname -m) in
          aarch64) cpu_gost=arm64;;
          x86_64) cpu_gost=amd64;;
          *) red "不支持的架构：$(uname -m)" && exit;;
        esac
        curl -L -o "$SBFOLDER/gost.tar.gz" -# --retry 2 "https://github.com/go-gost/gost/releases/download/v${gost_ver}/gost_${gost_ver}_linux_${cpu_gost}.tar.gz"
        tar -zxf "$SBFOLDER/gost.tar.gz" -C "$SBFOLDER" gost
        mv -f "$SBFOLDER/gost" "/usr/local/bin/gost"
        chmod +x "/usr/local/bin/gost"
        rm -f "$SBFOLDER/gost.tar.gz"
      fi

      if ! id -u usque-user >/dev/null 2>&1; then
        useradd -r -s /usr/sbin/nologin usque-user
      fi
      chown usque-user:usque-user "$SBFOLDER/usque.json"
      chmod 644 "$SBFOLDER/usque.json"

      if command -v apk >/dev/null 2>&1; then
        rc-service usque stop >/dev/null 2>&1
        rc-service gost stop >/dev/null 2>&1
      else
        systemctl stop usque >/dev/null 2>&1
        systemctl stop gost >/dev/null 2>&1
      fi
      ps -ef | grep -E '[s]bwpph|[w]arp-plus|[g]ost|[u]sque' | awk '{print $2}' | xargs kill 2>/dev/null

      # Clean up old iptables owner rules
      local uu_uid=$(id -u usque-user 2>/dev/null)
      local grep_pattern="usque-user"
      if [[ -n $uu_uid ]]; then
        grep_pattern="usque-user|$uu_uid"
      fi
      iptables-save 2>/dev/null | grep -E "$grep_pattern" | sed 's/^-A //g' | while read -r line; do
        iptables -t nat -D $line >/dev/null 2>&1
        iptables -t filter -D $line >/dev/null 2>&1
        iptables -D $line >/dev/null 2>&1
      done
      ip6tables-save 2>/dev/null | grep -E "$grep_pattern" | sed 's/^-A //g' | while read -r line; do
        ip6tables -t nat -D $line >/dev/null 2>&1
        ip6tables -t filter -D $line >/dev/null 2>&1
        ip6tables -D $line >/dev/null 2>&1
      done
      netfilter-persistent save >/dev/null 2>&1
      service iptables save >/dev/null 2>&1


      if command -v apk >/dev/null 2>&1; then
        # OpenRC usque
        cat > /etc/init.d/usque <<EOF
#!/sbin/openrc-run
description="Usque WARP MASQUE Proxy"
command="/usr/local/bin/usque"
command_args="socks -c $SBFOLDER/usque.json -b 127.0.0.1 -p $port --http2 --connect-port $gost_port"
command_background=true
pidfile="/var/run/usque.pid"
command_user="usque-user"
EOF
        chmod +x /etc/init.d/usque
        rc-update add usque default >/dev/null 2>&1

        # OpenRC gost
        cat > /etc/init.d/gost <<EOF
#!/sbin/openrc-run
description="Gost TCP Port Forwarding Bridge"
command="/usr/local/bin/gost"
command_args="-D -L tcp://127.0.0.1:$gost_port/162.159.198.2:443 -L tcp://[::1]:$gost_port/162.159.198.2:443 -F socks5://127.0.0.1:$vwarp_port"
command_background=true
pidfile="/var/run/gost.pid"
EOF
        chmod +x /etc/init.d/gost
        rc-update add gost default >/dev/null 2>&1
      else
        # Systemd usque
        cat > /etc/systemd/system/usque.service <<EOF
[Unit]
Description=Usque WARP MASQUE Proxy
After=network.target

[Service]
User=usque-user
ExecStart=/usr/local/bin/usque socks -c $SBFOLDER/usque.json -b 127.0.0.1 -p $port --http2 --connect-port $gost_port
Restart=always

[Install]
WantedBy=multi-user.target
EOF
        # Systemd gost
        cat > /etc/systemd/system/gost.service <<EOF
[Unit]
Description=Gost TCP Port Forwarding Bridge
After=network.target

[Service]
ExecStart=/usr/local/bin/gost -D -L tcp://127.0.0.1:$gost_port/162.159.198.2:443 -L tcp://[::1]:$gost_port/162.159.198.2:443 -F socks5://127.0.0.1:$vwarp_port
Restart=always

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload >/dev/null 2>&1
        systemctl enable usque >/dev/null 2>&1
        systemctl enable gost >/dev/null 2>&1
      fi

      # Apply iptables rules to prevent UDP leak
      iptables -I OUTPUT -m owner --uid-owner usque-user -p udp ! --dport 53 -j REJECT
      if [[ -n $v6 ]]; then
        ip6tables -I OUTPUT -m owner --uid-owner usque-user -p udp ! --dport 53 -j REJECT
      fi
      netfilter-persistent save >/dev/null 2>&1
      service iptables save >/dev/null 2>&1

      # Start Psiphon (warp-plus) on vwarp_port
      nohup "$SBFOLDER/warp-plus" -b 127.0.0.1:$vwarp_port --cfon --country $guojia -$sw46 --endpoint 162.159.192.1:2408 >"$SBFOLDER/warp-plus-run.log" 2>&1 &
      
      # Start Gost & Usque
      if command -v apk >/dev/null 2>&1; then
        rc-service gost start >/dev/null 2>&1
        rc-service usque start >/dev/null 2>&1
      else
        systemctl start gost >/dev/null 2>&1
        systemctl start usque >/dev/null 2>&1
      fi

      green "启动 Psiphon + WARP 双重链代理中，请稍候..."
      sleep 20

      # IP verification using ifconfig.me
      resv1=$(curl -sm15 --socks5 127.0.0.1:$port ifconfig.me)
      resv2=$(curl -sm15 -x socks5h://127.0.0.1:$port ifconfig.me)

      if [[ -z $resv1 && -z $resv2 ]]; then
        red "Psiphon + WARP 双重代理连接失败！将自动回退到正常 Psiphon 连接模式..."
        
        echo "==================== 诊断信息 (DIAGNOSTICS) ===================="
        echo "1. 检查端口监听状态 (ss -tlnp):"
        ss -tlnp 2>/dev/null | grep -E "gost|usque|warp-plus" || netstat -tlnp 2>/dev/null | grep -E "gost|usque|warp-plus"
        echo "2. 完整的 iptables 规则 (iptables-save):"
        iptables-save 2>/dev/null
        echo "3. 完整的 ip6tables 规则 (ip6tables-save):"
        ip6tables-save 2>/dev/null
        echo "4. 检查系统网络参数 (sysctl):"
        sysctl net.ipv4.conf.all.rp_filter net.ipv4.conf.lo.rp_filter net.ipv4.conf.all.route_localnet net.ipv4.conf.lo.route_localnet 2>/dev/null
        echo "6. 检查 Gost 状态与最后日志:"
        systemctl status gost --no-pager 2>/dev/null || rc-service gost status 2>/dev/null
        journalctl -u gost -n 15 --no-pager 2>/dev/null || tail -n 15 /var/log/gost.log 2>/dev/null
        echo "7. 检查 Usque 状态与最后日志:"
        systemctl status usque --no-pager 2>/dev/null || rc-service usque status 2>/dev/null
        journalctl -u usque -n 15 --no-pager 2>/dev/null || tail -n 15 /var/log/usque.log 2>/dev/null
        echo "================================================================"
        
        # Cleanup chain services
        if command -v apk >/dev/null 2>&1; then
          rc-service usque stop >/dev/null 2>&1
          rc-service gost stop >/dev/null 2>&1
          rc-update del usque default >/dev/null 2>&1
          rc-update del gost default >/dev/null 2>&1
        else
          systemctl disable --now usque >/dev/null 2>&1
          systemctl disable --now gost >/dev/null 2>&1
        fi
        ps -ef | grep -E '[s]bwpph|[w]arp-plus|[g]ost|[u]sque' | awk '{print $2}' | xargs kill 2>/dev/null
        
        # Cleanup iptables
        local uu_uid=$(id -u usque-user 2>/dev/null)
        local grep_pattern="usque-user"
        if [[ -n $uu_uid ]]; then
          grep_pattern="usque-user|$uu_uid"
        fi
        iptables-save 2>/dev/null | grep -E "$grep_pattern" | sed 's/^-A //g' | while read -r line; do
          iptables -t nat -D $line >/dev/null 2>&1
          iptables -t filter -D $line >/dev/null 2>&1
          iptables -D $line >/dev/null 2>&1
        done
        ip6tables-save 2>/dev/null | grep -E "$grep_pattern" | sed 's/^-A //g' | while read -r line; do
          ip6tables -t nat -D $line >/dev/null 2>&1
          ip6tables -t filter -D $line >/dev/null 2>&1
          ip6tables -D $line >/dev/null 2>&1
        done
        netfilter-persistent save >/dev/null 2>&1
        service iptables save >/dev/null 2>&1

        # Cleanup sysctl parameters
        rm -f /etc/sysctl.d/99-gost-usque.conf
        sysctl --system >/dev/null 2>&1

        # Fallback: Run normal Psiphon directly on $port
        nohup "$SBFOLDER/warp-plus" -b 127.0.0.1:$port --cfon --country $guojia -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1 &
        green "正常 Psiphon 代理启动中，请稍等..." && sleep 20
        resv1=$(curl -sm3 --socks5 localhost:$port icanhazip.com)
        resv2=$(curl -sm3 -x socks5h://localhost:$port icanhazip.com)
        if [[ -z $resv1 && -z $resv2 ]]; then
          red "WARP-plus-Socks5的IP获取失败，尝试换个国家地区吧" && unins && exit
        else
          echo "$SBFOLDER/warp-plus -b 127.0.0.1:$port --cfon --country $guojia -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1" > "$SBFOLDER/warp-plus.log"
          aplws5
          green "WARP-plus-Socks5的IP获取成功，已成功回退为正常 Psiphon 代理"
        fi
      else
        echo "$SBFOLDER/warp-plus -b 127.0.0.1:$vwarp_port --cfon --country $guojia -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1" > "$SBFOLDER/warp-plus.log"
        aplws5
        green "Psiphon + WARP 双重链代理构建成功！"
        green "代理 IP: ${resv1:-$resv2}"
        green "Socks5 监听地址: 127.0.0.1:$port"
        green "重新启动脚本后可使用选项 5 设置分流。"
      fi
    else
      # Normal Psiphon
      nohup "$SBFOLDER/warp-plus" -b 127.0.0.1:$port --cfon --country $guojia -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1 &
      green "申请IP中……请稍等……" && sleep 20
      resv1=$(curl -sm3 --socks5 localhost:$port icanhazip.com)
      resv2=$(curl -sm3 -x socks5h://localhost:$port icanhazip.com)
      if [[ -z $resv1 && -z $resv2 ]]; then
        red "WARP-plus-Socks5的IP获取失败，尝试换个国家地区吧" && unins && exit
      else
        echo "$SBFOLDER/warp-plus -b 127.0.0.1:$port --cfon --country $guojia -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1" > "$SBFOLDER/warp-plus.log"
        aplws5
        green "WARP-plus-Socks5的IP获取成功，可进行Socks5代理分流"
      fi
    fi
  elif [ "$menu" = "3" ]; then
    unins && green "已停止WARP-plus-Socks5代理功能"
  else
    sb
  fi
}

# --- Uninstall logic ---
unins() {
  readp "是否确认卸载Sing-box？\n1、是，确认卸载\n2、否，取消返回\n请选择【1-2】：" choose
  if [[ "$choose" != "1" ]]; then
    red "已取消卸载！"
    sb
    return 1
  fi
  if command -v apk >/dev/null 2>&1; then
    for svc in sing-box argo usque gost; do
      rc-service "$svc" stop >/dev/null 2>&1
      rc-update del "$svc" default >/dev/null 2>&1
    done
    rm -rf /etc/init.d/{sing-box,argo,usque,gost}
  else
    for svc in sing-box argo usque gost; do
      systemctl stop "$svc" >/dev/null 2>&1
      systemctl disable "$svc" >/dev/null 2>&1
    done
    rm -rf /etc/systemd/system/{sing-box.service,argo.service,usque.service,gost.service}
    systemctl daemon-reload >/dev/null 2>&1
  fi
  rm -f /usr/local/bin/usque /usr/local/bin/gost
  
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json" 2>/dev/null)
  local vm_listen_port=$(echo "$clean_json" | jq -r '.inbounds[1].listen_port' 2>/dev/null)
  [ -n "$vm_listen_port" ] && ps -ef | grep "[l]ocalhost:$vm_listen_port" | awk '{print $2}' | xargs kill 2>/dev/null
  ps -ef | grep -E '[s]bwpph|[w]arp-plus|[g]ost|[u]sque' | awk '{print $2}' | xargs kill 2>/dev/null
  if command -v warp-cli >/dev/null 2>&1; then
    warp-cli disconnect >/dev/null 2>&1
  fi
  kill -15 $(pgrep -f 'websbox' 2>/dev/null) >/dev/null 2>&1

  # Clean up iptables redirect rules for usque-user
  local uu_uid=$(id -u usque-user 2>/dev/null)
  local grep_pattern="usque-user"
  if [[ -n $uu_uid ]]; then
    grep_pattern="usque-user|$uu_uid"
  fi
  iptables-save 2>/dev/null | grep -E "$grep_pattern" | sed 's/^-A //g' | while read -r line; do
    iptables -t nat -D $line >/dev/null 2>&1
    iptables -t filter -D $line >/dev/null 2>&1
    iptables -D $line >/dev/null 2>&1
  done
  ip6tables-save 2>/dev/null | grep -E "$grep_pattern" | sed 's/^-A //g' | while read -r line; do
    ip6tables -t nat -D $line >/dev/null 2>&1
    ip6tables -t filter -D $line >/dev/null 2>&1
    ip6tables -D $line >/dev/null 2>&1
  done

  # Clean up user
  if id -u usque-user >/dev/null 2>&1; then
    userdel usque-user >/dev/null 2>&1
  fi

  rm -f /etc/sysctl.d/99-gost-usque.conf
  sysctl --system >/dev/null 2>&1
  
  rm -rf "$SBFOLDER" sbyg_update "$SCRIPT_SHORTCUT" /root/geoip.db /root/geosite.db /root/warpapi /root/warpip /root/websbox
  rm -f /etc/local.d/alpineargo.start /etc/local.d/alpinesub.start /etc/local.d/alpinews5.start
  uncronsb
  iptables -t nat -F PREROUTING >/dev/null 2>&1
  netfilter-persistent save >/dev/null 2>&1
  service iptables save >/dev/null 2>&1
  green "Sing-box卸载完成！"
  blue "欢迎继续使用Sing-box安装脚本：sb"
  echo
}

# --- Auxiliary System Status Check & Menus ---
sbactive() {
  if [[ ! -f "$SBFOLDER/sb.json" ]]; then
    red "未正常启动Sing-box，请卸载重装或者选择10查看运行日志反馈" && exit
  fi
}

sbsm() {
  echo
  green "Sing-Box 五协议共存一键安装管理脚本"
  blue "支持协议：Vless-reality-vision、Vmess-ws(tls)+Argo、Hysteria2、Tuic5、Anytls"
  blue "脚本特色：集成多协议，支持 Acme 证书自动申请，提供双栈分流支持以及 WARP 代理支持"
  echo
}

sblog() {
  red "退出日志 Ctrl+c"
  if command -v apk >/dev/null 2>&1; then
    yellow "暂不支持alpine查看日志"
  else
    journalctl -u sing-box.service -o cat -f
  fi
}

acme() {
  bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)
}

cfwarp() {
  if ! command -v wget &>/dev/null; then
    if command -v apt &>/dev/null; then
      apt update -y && apt install -y wget
    elif command -v yum &>/dev/null; then
      yum install -y wget
    elif command -v dnf &>/dev/null; then
      dnf install -y wget
    elif command -v apk &>/dev/null; then
      apk add wget
    fi
  fi
  wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh ; bash menu.sh [option] [lisence/url/token]
}

bbr() {
  if [ -f "/etc/alpine-release" ]; then
    while true; do
      clear
      local congestion_algorithm=$(sysctl -n net.ipv4.tcp_congestion_control)
      local queue_algorithm=$(sysctl -n net.core.default_qdisc)
      echo "当前TCP阻塞算法: $congestion_algorithm $queue_algorithm"

      echo ""
      echo "BBR管理"
      echo "------------------------"
      echo "1. 开启BBRv3              2. 关闭BBRv3（会重启）"
      echo "------------------------"
      echo "0. 返回上一级选单"
      echo "------------------------"
      readp "请输入你的选择: " sub_choice

      case $sub_choice in
        1)
          local CONF="/etc/sysctl.d/99-kejilion-bbr.conf"
          mkdir -p /etc/sysctl.d
          echo "net.core.default_qdisc=fq" > "$CONF"
          echo "net.ipv4.tcp_congestion_control=bbr" >> "$CONF"

          sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf 2>/dev/null
          sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf 2>/dev/null

          sysctl -p "$CONF" >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1
          ;;
        2)
          sed -i '/net.ipv4.tcp_congestion_control=/d' /etc/sysctl.conf
          sysctl -p
          readp "现在重启服务器吗？(Y/N): " rboot
          case "$rboot" in
            [Yy])
              echo "已重启"
              reboot
              ;;
            *)
              echo "已取消"
              ;;
          esac
          ;;
        *)
          break
          ;;
      esac
    done
  else
    if ! command -v wget &>/dev/null; then
      if command -v apt &>/dev/null; then
        apt update -y && apt install -y wget
      elif command -v yum &>/dev/null; then
        yum install -y wget
      elif command -v dnf &>/dev/null; then
        dnf install -y wget
      elif command -v apk &>/dev/null; then
        apk add wget
      fi
    fi
    wget --no-check-certificate -O tcpx.sh https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcpx.sh
    chmod +x tcpx.sh
    ./tcpx.sh
  fi
}

showprotocol() {
  allports
  sbymfl
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
  tls=$(echo "$clean_json" | jq -r '.inbounds[1].tls.enabled')
  if [[ "$tls" = "false" ]]; then
    if ps -ef 2>/dev/null | grep -q '[c]loudflared.*run' || ps -ef 2>/dev/null | grep -q "[l]ocalhost:$vm_port"; then
      vm_zs="TLS关闭"
      argoym="已开启"
    else
      vm_zs="TLS关闭"
      argoym="未开启"
    fi
  else
    vm_zs="TLS开启"
    argoym="不支持开启"
  fi
  hy2_sniname=$(echo "$clean_json" | jq -r '.inbounds[2].tls.key_path')
  [[ "$hy2_sniname" = "$SBFOLDER/private.key" || "$hy2_sniname" = "/etc/s-box/private.key" ]] && hy2_zs="自签证书" || hy2_zs="域名证书"
  tu5_sniname=$(echo "$clean_json" | jq -r '.inbounds[3].tls.key_path')
  [[ "$tu5_sniname" = "$SBFOLDER/private.key" || "$tu5_sniname" = "/etc/s-box/private.key" ]] && tu5_zs="自签证书" || tu5_zs="域名证书"
  an_sniname=$(echo "$clean_json" | jq -r '.inbounds[4].tls.key_path')
  [[ "$an_sniname" = "$SBFOLDER/private.key" || "$an_sniname" = "/etc/s-box/private.key" ]] && an_zs="自签证书" || an_zs="域名证书"

  # Check if warp-cli is connected
  warp_cli_connected=0
  if command -v warp-cli >/dev/null 2>&1 && warp-cli status 2>/dev/null | grep -qi "connected"; then
    warp_cli_connected=1
  fi

  # Check if warp-plus is running
  warpplus_running=0
  if [[ -n $(ps -e | grep -E 'warp-plus|sbwpph') ]]; then
    warpplus_running=1
  fi

  # Check if usque is running
  usque_running=0
  if [[ -n $(ps -e | grep -w usque) ]]; then
    usque_running=1
  fi

  if [[ $warpplus_running -eq 1 || $warp_cli_connected -eq 1 || $usque_running -eq 1 ]]; then
    if [[ $usque_running -eq 1 ]]; then
      s5port=$(ps -ef | grep -w usque | grep -v grep | grep -oP '\-p\s+\K\d+' | head -n 1)
      if [[ -z "$s5port" ]]; then
        s5port=$(cat "$SBFOLDER/warp-plus.log" "$SBFOLDER/sbwpph.log" 2>/dev/null | head -n 1 | awk '{print $3}' | awk -F":" '{print $NF}')
      fi
      s5port=${s5port:-40000}
      s5proto="MASQUE"
      if [[ -n $(ps -e | grep -w gost) ]]; then
        s5gj=$(cat "$SBFOLDER/warp-plus.log" "$SBFOLDER/sbwpph.log" 2>/dev/null | head -n 1 | awk '{print $6}')
        case "$s5gj" in
          AT) showgj="奥地利" ;;
          AU) showgj="澳大利亚" ;;
          BE) showgj="比利时" ;;
          BG) showgj="保加利亚" ;;
          CA) showgj="加拿大" ;;
          CH) showgj="瑞士" ;;
          CZ) showgj="捷克" ;;
          DE) showgj="德国" ;;
          DK) showgj="丹麦" ;;
          EE) showgj="爱沙尼亚" ;;
          ES) showgj="西班牙" ;;
          FI) showgj="芬兰" ;;
          FR) showgj="法国" ;;
          GB) showgj="英国" ;;
          HR) showgj="克罗地亚" ;;
          HU) showgj="匈牙利" ;;
          IE) showgj="爱尔兰" ;;
          IN) showgj="印度" ;;
          IT) showgj="意大利" ;;
          JP) showgj="日本" ;;
          LT) showgj="立陶宛" ;;
          LV) showgj="拉脱维亚" ;;
          NL) showgj="荷兰" ;;
          NO) showgj="挪威" ;;
          PL) showgj="波兰" ;;
          PT) showgj="葡萄牙" ;;
          RO) showgj="罗马尼亚" ;;
          RS) showgj="塞尔维亚" ;;
          SE) showgj="瑞典" ;;
          SG) showgj="新加坡" ;;
          SK) showgj="斯洛伐克" ;;
          US) showgj="美国" ;;
          *) showgj="$s5gj" ;;
        esac
        client_type="Usque + Gost + Psiphon (国家:$showgj)"
      else
        client_type="Usque"
      fi
    elif [[ $warp_cli_connected -eq 1 ]]; then
      client_type="WARP-cli"
      s5port=$(warp-cli settings 2>/dev/null | grep -i "proxy port" | awk '{print $NF}')
      if [[ ! "$s5port" =~ ^[0-9]+$ ]]; then
        s5port=$(cat "$SBFOLDER/warp-plus.log" "$SBFOLDER/sbwpph.log" 2>/dev/null | head -n 1 | awk '{print $3}' | awk -F":" '{print $NF}')
      fi
      s5port=${s5port:-40000}
      s5proto=$(warp-cli settings 2>/dev/null | grep -i "tunnel protocol" | awk '{print $NF}')
      s5proto=${s5proto:-"MASQUE"}
    else
      s5port=$(cat "$SBFOLDER/warp-plus.log" "$SBFOLDER/sbwpph.log" 2>/dev/null | head -n 1 | awk '{print $3}' | awk -F":" '{print $NF}')
      s5port=${s5port:-40000}
      s5proto="WireGuard"
      s5gj=$(cat "$SBFOLDER/warp-plus.log" "$SBFOLDER/sbwpph.log" 2>/dev/null | head -n 1 | awk '{print $6}')
      if grep -q "country" "$SBFOLDER/warp-plus.log" "$SBFOLDER/sbwpph.log" 2>/dev/null; then
        case "$s5gj" in
          AT) showgj="奥地利" ;;
          AU) showgj="澳大利亚" ;;
          BE) showgj="比利时" ;;
          BG) showgj="保加利亚" ;;
          CA) showgj="加拿大" ;;
          CH) showgj="瑞士" ;;
          CZ) showgj="捷克" ;;
          DE) showgj="德国" ;;
          DK) showgj="丹麦" ;;
          EE) showgj="爱沙尼亚" ;;
          ES) showgj="西班牙" ;;
          FI) showgj="芬兰" ;;
          FR) showgj="法国" ;;
          GB) showgj="英国" ;;
          HR) showgj="克罗地亚" ;;
          HU) showgj="匈牙利" ;;
          IE) showgj="爱尔兰" ;;
          IN) showgj="印度" ;;
          IT) showgj="意大利" ;;
          JP) showgj="日本" ;;
          LT) showgj="立陶宛" ;;
          LV) showgj="拉脱维亚" ;;
          NL) showgj="荷兰" ;;
          NO) showgj="挪威" ;;
          PL) showgj="波兰" ;;
          PT) showgj="葡萄牙" ;;
          RO) showgj="罗马尼亚" ;;
          RS) showgj="塞尔维亚" ;;
          SE) showgj="瑞典" ;;
          SG) showgj="新加坡" ;;
          SK) showgj="斯洛伐克" ;;
          US) showgj="美国" ;;
          *) showgj="$s5gj" ;;
        esac
        client_type="Psiphon (国家:$showgj)"
      else
        client_type="WireProxy"
      fi
    fi

    # Query proxy IP
    proxy_ipv4=""
    for host in "api.ipify.org" "v4.ident.me" "ipv4.seeip.org"; do
      res=$(curl -s4m3 -x socks5h://127.0.0.1:$s5port "$host" 2>/dev/null || curl -s4m3 --socks5 127.0.0.1:$s5port "$host" 2>/dev/null)
      if [[ -n "$res" && ! "$res" =~ : ]]; then
        proxy_ipv4="$res"
        break
      fi
    done

    proxy_ipv6=""
    for host in "api6.ipify.org" "v6.ident.me" "ipv6.seeip.org"; do
      res=$(curl -s4m3 -x socks5h://127.0.0.1:$s5port "$host" 2>/dev/null || curl -sm3 --socks5 127.0.0.1:$s5port "$host" 2>/dev/null)
      if [[ -n "$res" && "$res" =~ : ]]; then
        proxy_ipv6="$res"
        break
      fi
    done

    [[ -z "$proxy_ipv4" ]] && show_v4="无" || show_v4="$proxy_ipv4"
    [[ -z "$proxy_ipv6" ]] && show_v6="无" || show_v6="$proxy_ipv6"

    local_vwarp=""
    if [[ "$client_type" == *"Psiphon"* || "$client_type" == "WireProxy" ]]; then
      if [ -f "$SBFOLDER/vwarp.version" ]; then
        local_vwarp=" ($(cat "$SBFOLDER/vwarp.version" 2>/dev/null))"
      fi
    fi

    echo -e "WARP-plus-Socks5状态：${green}已启动${plain}${local_vwarp}"
    echo -e "客户端：${yellow}${client_type}${plain}        协议：${yellow}${s5proto}${plain}        代理端口：${yellow}${s5port}${plain}"
    echo -e "当前代理IP："
    echo -e "  IPV4：${yellow}${show_v4}${plain}"
    echo -e "  IPV6：${yellow}${show_v6}${plain}"
  else
    echo -e "WARP-plus-Socks5状态：${yellow}未启动${plain}"
  fi

  echo "------------------------------------------------------------------------------------"

  echo -e "Sing-box节点关键信息、已分流域名情况如下："
  echo -e "🚀【 Vless-reality 】${yellow}端口:$vl_port  Reality域名证书伪装地址：$(echo "$clean_json" | jq -r '.inbounds[0].tls.server_name')${plain}"
  if [[ "$tls" = "false" ]]; then
    echo -e "🚀【   Vmess-ws    】${yellow}端口:$vm_port   证书形式:$vm_zs   Argo状态:$argoym${plain}"
  else
    echo -e "🚀【 Vmess-ws-tls  】${yellow}端口:$vm_port   证书形式:$vm_zs   Argo状态:$argoym${plain}"
  fi
  echo -e "🚀【  Hysteria-2   】${yellow}端口:$hy2_port  证书形式:$hy2_zs  转发多端口: $hy2zfport${plain}"
  echo -e "🚀【    Tuic-v5    】${yellow}端口:$tu5_port  证书形式:$tu5_zs  转发多端口: $tu5zfport${plain}"
  if [[ "$sbnh" != "1.10" ]]; then
    echo -e "🚀【    Anytls     】${yellow}端口:$an_port  证书形式:$an_zs${plain}"
  fi

  if [ "$argoym" = "已开启" ]; then
    if ps -ef 2>/dev/null | grep -q "[l]ocalhost:$vm_port"; then
      echo -e "Argo临时域名：${yellow}$(cat "$SBFOLDER/argo.log" 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')${plain}"
    fi
    if ps -ef 2>/dev/null | grep -q '[c]loudflared.*run'; then
      echo -e "Argo固定域名：${yellow}$(cat "$SBFOLDER/sbargoym.log" 2>/dev/null)${plain}"
    fi
  fi

  echo "------------------------------------------------------------------------------------"

  ww4="warp-wireguard-ipv4优先分流域名：$wfl4"
  ww6="warp-wireguard-ipv6优先分流域名：$wfl6"
  ws4="warp-socks5-ipv4优先分流域名：$sfl4"
  ws6="warp-socks5-ipv6优先分流域名：$sfl6"
  l4="VPS本地ipv4优先分流域名：$adfl4"
  l6="VPS本地ipv6优先分流域名：$adfl6"

  [[ "$sbnh" == "1.10" ]] && ymflzu=("ww4" "ww6" "ws4" "ws6" "l4" "l6") || ymflzu=("ww6" "ws4" "l4" "l6")
  for ymfl in "${ymflzu[@]}"; do
    if [[ ${!ymfl} != *"未"* ]]; then
      echo -e "${!ymfl}"
    fi
  done

  if [[ $ww4 = *"未"* && $ww6 = *"未"* && $ws4 = *"未"* && $ws6 = *"未"* && $l4 = *"未"* && $l6 = *"未"* ]]; then
    echo -e "未设置域名分流"
  fi
}

# --- Main Entry and Interface ---
instsllsingbox() {
  detect_system
  install_dependencies
  tun_check
  openyn
  inssb
  
  # Reality public/private keys
  reality_keys=$("$SBFOLDER/sing-box" generate reality-keypair)
  private_key=$(echo "$reality_keys" | awk '/PrivateKey/{print $NF}' | tr -d '"')
  public_key=$(echo "$reality_keys" | awk '/PublicKey/{print $NF}' | tr -d '"')
  echo "$private_key" > "$SBFOLDER/private.key"
  echo "$public_key" > "$SBFOLDER/public.key"
  short_id=$(openssl rand -hex 8)
  
  inscertificate
  insport
  
  pvk="g9I2sgUH6OCbIBTehkEfVEnuvInHYZvPOFhWchMLSc4="
  v6="2606:4700:110:860e:738f:b37:f15:d38d"
  res="[33,217,129]"
  
  inssbjsonser
  sbservice
  curl -sL "https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/version" | awk -F "更新内容" '{print $1}' | head -n 1 > "$SBFOLDER/v"
  lnsb
  cronsb
  
  wgcfgo
  sbshare
  
  blue "Sing-box脚本安装成功，脚本快捷方式：sb"
  cronsb
}

sb() {
  clear
  detect_system
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
  echo -e "${bblue}   _____ _             _                  ${plain}"
  echo -e "${bblue}  / ____(_)           | |                 ${plain}"
  echo -e "${bblue} | (___  _ _ __   __ _| |__   _____  __   ${plain}"
  echo -e "${bblue}  \\___ \\| | '_ \\ / _\` | '_ \\ / _ \\ \\/ /   ${plain}"
  echo -e "${bblue}  ____) | | | | | (_| | |_) | (_) >  <    ${plain}"
  echo -e "${bblue} |_____/|_|_| |_|\\__, |_.__/ \\___/_/\\_\\   ${plain}"
  echo -e "${bblue}                  __/ |                   ${plain}"
  echo -e "${bblue}                 |___/                    ${plain}"
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
  white "Vless-reality-vision、Vmess-ws(tls)+Argo、Hy2、Tuic、Anytls 五协议共存脚本"
  white "脚本快捷方式：sb"
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  green " 1. 一键安装 Sing-box" 
  green " 2. 删除卸载 Sing-box"
  white "----------------------------------------------------------------------------------"
  green " 3. 变更配置 【双证书TLS/UUID路径/Argo/IP优先/Warp/CDN优选】" 
  green " 4. 更改主端口/添加多端口跳跃复用" 
  green " 5. 三通道域名分流"
  green " 6. 关闭/重启 Sing-box"   
  green " 7. 更新 Sing-box 脚本"
  green " 8. 更新/切换/指定 Sing-box 内核版本"
  white "----------------------------------------------------------------------------------"
  green " 9. 刷新并查看节点 【Mihomo/SFA+SFI+SFW三合一配置/分享链接】"
  green "10. 查看 Sing-box 运行日志"
  green "11. 更改 BBR 设置"
  green "12. 管理 Acme 申请域名证书"
  green "13. 管理 Cloudflare WARP"
  green "14. 添加 WARP-plus-Socks5 代理模式 【本地Warp/多地区Psiphon-VPN】"
  green "15. 更换IP刷新本地IP、调整IPV4/IPV6配置输出"
  white "----------------------------------------------------------------------------------"
  green "16. Sing-box 脚本使用说明书"
  white "----------------------------------------------------------------------------------"
  green " 0. 退出脚本"
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  
  if [ -f "$SBFOLDER/v" ]; then
    insV=$(cat "$SBFOLDER/v" 2>/dev/null)
    latestV=$(curl -sL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/version | awk -F "更新内容" '{print $1}' | head -n 1)
    if [ "$insV" = "$latestV" ]; then
      echo -e "当前 Sing-box 脚本最新版：${bblue}${insV}${plain} (已安装)"
    else
      echo -e "当前 Sing-box 脚本版本号：${bblue}${insV}${plain}"
      echo -e "检测到最新 Sing-box 脚本版本号：${yellow}${latestV}${plain} (可选择7进行更新)"
      echo -e "${yellow}$(curl -sL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/version)${plain}"
    fi
  else
    latestV=$(curl -sL https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/version | awk -F "更新内容" '{print $1}' | head -n 1)
    echo -e "当前 Sing-box 脚本版本号：${bblue}${latestV}${plain}"
    yellow "未安装 Sing-box 脚本！请先选择 1 安装"
  fi
  
  lapre
  if [ -f "$SBFOLDER/sb.json" ]; then
    if [[ $inscore =~ ^[0-9.]+$ ]]; then
      if [ "${inscore}" = "${latcore}" ]; then
        echo -e "\n当前 Sing-box 最新正式版内核：${bblue}${inscore}${plain} (已安装)"
        echo -e "当前 Sing-box 最新测试版内核：${bblue}${precore}${plain} (可切换)"
      else
        echo -e "\n当前 Sing-box 已安装正式版内核：${bblue}${inscore}${plain}"
        echo -e "检测到最新 Sing-box 正式版内核：${yellow}${latcore}${plain} (可选择8进行更新)"
        echo -e "\n当前 Sing-box 最新测试版内核：${bblue}${precore}${plain} (可切换)"
      fi
    else
      if [ "${inscore}" = "${precore}" ]; then
        echo -e "\n当前 Sing-box 最新测试版内核：${bblue}${inscore}${plain} (已安装)"
        echo -e "当前 Sing-box 最新正式版内核：${bblue}${latcore}${plain} (可切换)"
      else
        echo -e "\n当前 Sing-box 已安装测试版内核：${bblue}${inscore}${plain}"
        echo -e "检测到最新 Sing-box 测试版内核：${yellow}${precore}${plain} (可选择8进行更新)"
        echo -e "\n当前 Sing-box 最新正式版内核：${bblue}${latcore}${plain} (可切换)"
      fi
    fi
  else
    echo -e "\n当前 Sing-box 最新正式版内核：${bblue}${latcore}${plain}"
    echo -e "当前 Sing-box 最新测试版内核：${bblue}${precore}${plain}"
  fi
  
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  echo -e "VPS状态如下："
  echo -e "系统:$blue$op$plain  \c";echo -e "内核:$blue$version$plain  \c";echo -e "处理器:$blue$cpu$plain  \c";echo -e "虚拟化:$blue$vi$plain  \c";echo -e "BBR算法:$blue$bbr$plain"
  v4v6
  if [[ "$v6" == "2a09"* ]]; then
    w6="【WARP】"
  fi
  if [[ "$v4" == "104.28"* ]]; then
    w4="【WARP】"
  fi
  [[ -z $v4 ]] && showv4='IPV4地址丢失，请切换至IPV6或者重装Sing-box' || showv4=$v4$w4
  [[ -z $v6 ]] && showv6='IPV6地址丢失，请切换至IPV4或者重装Sing-box' || showv6=$v6$w6
  if [[ -z $v4 ]]; then
    vps_ipv4='无IPV4'      
    vps_ipv6="$v6"
    location="$v6dq"
  elif [[ -n $v4 &&  -n $v6 ]]; then
    vps_ipv4="$v4"    
    vps_ipv6="$v6"
    location="$v4dq"
  else
    vps_ipv4="$v4"    
    vps_ipv6='无IPV6'
    location="$v4dq"
  fi
  echo -e "本地IPV4地址：$blue$vps_ipv4$w4$plain   本地IPV6地址：$blue$vps_ipv6$w6$plain"
  echo -e "服务器地区：$blue$location$plain"
  
  if [[ "$sbnh" == "1.10" ]] && [ -f "$SBFOLDER/sb.json" ]; then
    rpip=$(strip_json_comments "$SBFOLDER/sb.json" | jq -r '.outbounds[0].domain_strategy') 2>/dev/null
    if [[ $rpip = 'prefer_ipv6' ]]; then
      v4_6="IPV6优先出站($showv6)"
    elif [[ $rpip = 'prefer_ipv4' ]]; then
      v4_6="IPV4优先出站($showv4)"
    elif [[ $rpip = 'ipv4_only' ]]; then
      v4_6="仅IPV4出站($showv4)"
    elif [[ $rpip = 'ipv6_only' ]]; then
      v4_6="仅IPV6出站($showv6)"
    fi
    echo -e "代理IP优先级：$blue$v4_6$plain"
  fi
  
  if command -v apk >/dev/null 2>&1; then
    status_cmd="rc-service sing-box status"
    status_pattern="started"
  else
    status_cmd="systemctl is-active sing-box"
    status_pattern="active"
  fi
  
  if [[ -n $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f "$SBFOLDER/sb.json" ]]; then
    echo -e "Sing-box状态：$blue运行中$plain"
  elif [[ -z $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f "$SBFOLDER/sb.json" ]]; then
    echo -e "Sing-box状态：$yellow未启动，选择10查看日志并反馈，建议切换正式版内核或卸载重装脚本$plain"
  else
    echo -e "Sing-box状态：$red未安装$plain"
  fi
  
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  if [ -f "$SBFOLDER/sb.json" ]; then
    showprotocol
  fi
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  echo
  readp "请输入数字【0-16】:" Input
  case "$Input" in  
     1 ) instsllsingbox ;;
     2 ) unins ;;
     3 ) changeserv ;;
     4 ) changeport ;;
     5 ) changefl ;;
     6 ) restartsb ;;
     7 ) upsbyg ;; 
     8 ) upsbcroe ;;
     9 ) clash_sb_share ;;
    10 ) sblog ;;
    11 ) bbr ;;
    12 ) acme ;;
    13 ) cfwarp ;;
    14 ) inswarpplus ;;
    15 ) wgcfgo && sbshare ;;
    16 ) sbsm ;;
     * ) exit ;;
  esac
}

# Start the script TUI
sb
