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
SBFOLDER="/var/Sing-Box-DuolaD"
SBFILES="$SBFOLDER/sb.json"
SCRIPT_URL="https://raw.githubusercontent.com/DuolaD/Sing-Box-DuolaD/main/sb.sh"
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
  v4=$(curl -s4m2 icanhazip.com -k)
  v4dq=$(curl -s4m2 -k https://myip.ipip.net | awk -F'来自于：' '{print $2}' 2>/dev/null)
  v6=""
  v6dq=""
  if ip addr show 2>/dev/null | grep -q "inet6 [23]"; then
    v6=$(curl -s6m2 icanhazip.com -k)
    v6dq=$(curl -s6m2 -k https://ip.fm | sed -n 's/.*Location: //p' 2>/dev/null)
  fi
}

warpcheck() {
  wgcfv6=$(curl -s6m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
  wgcfv4=$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
}

detect_network_settings() {
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
    endip="engage.cloudflareclient.com"
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
  green "自动下载并安装最新正式版 Sing-box 内核..."
  sbcore=$(curl -Ls https://github.com/SagerNet/sing-box/releases/latest | grep -oP 'tag/v\K[0-9.]+' | head -n 1)
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
get_self_domain() {
  cat /var/Sing-Box-DuolaD/self_domain.log 2>/dev/null || echo "dl.delivery.mp.microsoft.com"
}

generate_self_signed_cert() {
  local target_key="$1"
  local target_cert="$2"
  local domain="$3"
  if [[ -z "$domain" ]]; then
    domain=$(get_self_domain)
  fi
  mkdir -p /var/Sing-Box-DuolaD
  echo "$domain" > /var/Sing-Box-DuolaD/self_domain.log
  
  if ! command -v openssl &>/dev/null; then
    if command -v apt &>/dev/null; then
      apt update -y && apt install -y openssl
    elif command -v yum &>/dev/null; then
      yum install -y openssl
    fi
  fi
  
  cat > /tmp/openssl_ca.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
CN = $domain

[v3_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
extendedKeyUsage = serverAuth
subjectAltName = DNS:$domain
EOF

  openssl ecparam -genkey -name prime256v1 -out "$target_key" >/dev/null 2>&1
  openssl req -new -x509 -days 36500 -key "$target_key" -out "$target_cert" -config /tmp/openssl_ca.cnf >/dev/null 2>&1
  rm -f /tmp/openssl_ca.cnf
}

inscertificate() {
  local cur_self_dom=$(get_self_domain)
  echo
  green "请选择 SSL 证书类型："
  yellow "1：自签证书 ($cur_self_dom) (回车默认)"
  yellow "2：纯 IP 证书 (由 Let's Encrypt 签发，需确保 VPS 80 端口开放且未被防火墙阻断)"
  yellow "3：域名证书 (自动 ACME 申请，自备已解析的域名)"
  readp "请选择【1-3】：" cert_menu
  case "$cert_menu" in
    2)
      cert_type="ip"
      select_ip_cert_mode
      ;;
    3)
      cert_type="domain"
      while true; do
        readp "请输入解析至当前 VPS 的域名：" ym_domain
        if [[ -z "$ym_domain" ]]; then
          red "域名不能为空，请重新输入！"
        else
          local resolved_ip=$(dig +short "$ym_domain" 2>/dev/null || nslookup "$ym_domain" 2>/dev/null | awk '/Address:/ {print $2}' | tail -n 1)
          if [[ -z "$resolved_ip" ]]; then
            resolved_ip=$(ping -c 1 -W 2 "$ym_domain" 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
          fi
          local server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null || curl -s4 ip.sb)
          if [[ -z "$resolved_ip" || "$resolved_ip" != "$server_ip" ]]; then
            red "检测到域名 $ym_domain 未解析到当前 VPS 外部 IP $server_ip (解析到的 IP 是: ${resolved_ip:-无})。"
            yellow "请先确保域名解析生效，或者输入 y 忽略并强制继续："
            readp "忽略并继续？[y/N]：" force_dns
            if [[ "$force_dns" =~ ^[Yy]$ ]]; then
              break
            fi
          else
            blue "域名解析检测通过！"
            break
          fi
        fi
      done
      mkdir -p /var/Sing-Box-DuolaD
      echo "$ym_domain" > /var/Sing-Box-DuolaD/domain.log
      ;;
    *)
      cert_type="self"
      readp "请输入自签证书伪装域名 (回车默认使用 $cur_self_dom)：" custom_self_dom
      local self_dom=${custom_self_dom:-$cur_self_dom}
      mkdir -p /var/Sing-Box-DuolaD
      echo "$self_dom" > /var/Sing-Box-DuolaD/self_domain.log
      ;;
  esac

  setup_caddy_cert
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

get_random_free_port() {
  local free_port
  while true; do
    free_port=$(shuf -i 10000-65535 -n 1)
    if [[ -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$free_port") ]] && \
       [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$free_port") ]]; then
      echo "$free_port"
      break
    fi
  done
}

insport() {
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  green "三、设置各协议端口"
  yellow "1：自动生成选定协议的随机端口 (10000-65535范围内)，回车默认。请确保VPS后台已开放所有端口"
  yellow "2：自定义选定协议端口。请确保VPS后台已开放指定的端口"
  readp "请输入【1-2】：" port_choice
  
  local allocated_ports=()

  is_port_in_use() {
    local p="$1"
    if [[ -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$p") ]] || \
       [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$p") ]]; then
      return 0
    fi
    local check
    for check in "${allocated_ports[@]}"; do
      if [[ "$check" == "$p" ]]; then
        return 0
      fi
    done
    return 1
  }

  get_random_free_port() {
    local free_port
    while true; do
      free_port=$(shuf -i 10000-65535 -n 1)
      if ! is_port_in_use "$free_port"; then
        allocated_ports+=("$free_port")
        echo "$free_port"
        break
      fi
    done
  }
  
  get_cdn_port() {
    local is_tls="$1"
    local ports
    if [[ "$is_tls" == "true" ]]; then
      ports=("2053" "2083" "2087" "2096" "8443")
    else
      ports=("8080" "8880" "2052" "2082" "2086" "2095")
    fi
    local p
    local shuffled_ports=($(shuf -e "${ports[@]}"))
    for p in "${shuffled_ports[@]}"; do
      if ! is_port_in_use "$p"; then
        allocated_ports+=("$p")
        echo "$p"
        return 0
      fi
    done
    get_random_free_port
  }

  custom_port_prompt() {
    local name="$1"
    local var_name="$2"
    while true; do
      readp "\n设置 ${name} 端口 (回车跳过为10000-65535之间的随机端口)：" port
      if [[ -z "$port" ]]; then
        port=$(get_random_free_port)
        break
      else
        chooseport
        local dup=false
        for check in "${allocated_ports[@]}"; do
          if [[ "$check" == "$port" ]]; then
            dup=true
            break
          fi
        done
        if $dup; then
          red "该端口已分配给本次安装的其他协议，请重新输入！"
        else
          allocated_ports+=("$port")
          break
        fi
      fi
    done
    eval "${var_name}=\$port"
  }

  if [ -z "$port_choice" ] || [ "$port_choice" = "1" ] ; then
    [[ "$use_vl_re" = "true" ]] && port_vl_re=$(get_random_free_port)
    [[ "$use_vl_ws_tls" = "true" ]] && port_vl_ws_tls=$(get_random_free_port)
    [[ "$use_vl_hu_tls" = "true" ]] && port_vl_hu_tls=$(get_random_free_port)
    [[ "$use_vm_ws" = "true" ]] && port_vm_ws=$(get_cdn_port "false")
    [[ "$use_vm_ws_tls" = "true" ]] && port_vm_ws_tls=$(get_cdn_port "true")
    [[ "$use_vm_hu_tls" = "true" ]] && port_vm_hu_tls=$(get_random_free_port)
    [[ "$use_tr_tls" = "true" ]] && port_tr_tls=$(get_random_free_port)
    [[ "$use_tr_ws_tls" = "true" ]] && port_tr_ws_tls=$(get_random_free_port)
    [[ "$use_tr_hu_tls" = "true" ]] && port_tr_hu_tls=$(get_random_free_port)
    [[ "$use_ss" = "true" ]] && port_ss=$(get_random_free_port)
    [[ "$use_hy2" = "true" ]] && port_hy2=$(get_random_free_port)
    [[ "$use_tu" = "true" ]] && port_tu=$(get_random_free_port)
    [[ "$use_an" = "true" ]] && port_an=$(get_random_free_port)
    [[ "$use_vm_tcp" = "true" ]] && port_vm_tcp=$(get_random_free_port)
    [[ "$use_vm_http" = "true" ]] && port_vm_http=$(get_random_free_port)
    [[ "$use_vm_quic" = "true" ]] && port_vm_quic=$(get_random_free_port)
    [[ "$use_vm_h2_tls" = "true" ]] && port_vm_h2_tls=$(get_random_free_port)
    [[ "$use_vl_h2_tls" = "true" ]] && port_vl_h2_tls=$(get_random_free_port)
    [[ "$use_tr_h2_tls" = "true" ]] && port_tr_h2_tls=$(get_random_free_port)
    [[ "$use_vl_h2_re" = "true" ]] && port_vl_h2_re=$(get_random_free_port)
    [[ "$use_socks" = "true" ]] && port_socks=$(get_random_free_port)
  else
    [[ "$use_vl_re" = "true" ]] && custom_port_prompt "VLESS-Reality" "port_vl_re"
    [[ "$use_vl_ws_tls" = "true" ]] && custom_port_prompt "VLESS-WS-TLS" "port_vl_ws_tls"
    [[ "$use_vl_hu_tls" = "true" ]] && custom_port_prompt "VLESS-HTTPUpgrade-TLS" "port_vl_hu_tls"
    [[ "$use_vm_ws" = "true" ]] && custom_port_prompt "VMess-WS" "port_vm_ws"
    [[ "$use_vm_ws_tls" = "true" ]] && custom_port_prompt "VMess-WS-TLS" "port_vm_ws_tls"
    [[ "$use_vm_hu_tls" = "true" ]] && custom_port_prompt "VMess-HTTPUpgrade-TLS" "port_vm_hu_tls"
    [[ "$use_tr_tls" = "true" ]] && custom_port_prompt "Trojan-TLS" "port_tr_tls"
    [[ "$use_tr_ws_tls" = "true" ]] && custom_port_prompt "Trojan-WS-TLS" "port_tr_ws_tls"
    [[ "$use_tr_hu_tls" = "true" ]] && custom_port_prompt "Trojan-HTTPUpgrade-TLS" "port_tr_hu_tls"
    [[ "$use_ss" = "true" ]] && custom_port_prompt "Shadowsocks" "port_ss"
    [[ "$use_hy2" = "true" ]] && custom_port_prompt "Hysteria 2" "port_hy2"
    [[ "$use_tu" = "true" ]] && custom_port_prompt "Tuic-v5" "port_tu"
    [[ "$use_an" = "true" ]] && custom_port_prompt "AnyTLS" "port_an"
    [[ "$use_vm_tcp" = "true" ]] && custom_port_prompt "VMess-TCP" "port_vm_tcp"
    [[ "$use_vm_http" = "true" ]] && custom_port_prompt "VMess-HTTP" "port_vm_http"
    [[ "$use_vm_quic" = "true" ]] && custom_port_prompt "VMess-QUIC" "port_vm_quic"
    [[ "$use_vm_h2_tls" = "true" ]] && custom_port_prompt "VMess-H2-TLS" "port_vm_h2_tls"
    [[ "$use_vl_h2_tls" = "true" ]] && custom_port_prompt "VLESS-H2-TLS" "port_vl_h2_tls"
    [[ "$use_tr_h2_tls" = "true" ]] && custom_port_prompt "Trojan-H2-TLS" "port_tr_h2_tls"
    [[ "$use_vl_h2_re" = "true" ]] && custom_port_prompt "VLESS-HTTP2-REALITY" "port_vl_h2_re"
    [[ "$use_socks" = "true" ]] && custom_port_prompt "Socks" "port_socks"
  fi
  
  echo
  blue "各协议端口确认如下"
  [[ "$use_vl_re" = "true" ]] && blue "Vless-Reality端口：$port_vl_re"
  [[ "$use_vl_ws_tls" = "true" ]] && blue "Vless-WS-TLS端口：$port_vl_ws_tls"
  [[ "$use_vl_hu_tls" = "true" ]] && blue "Vless-HTTPUpgrade-TLS端口：$port_vl_hu_tls"
  [[ "$use_vm_ws" = "true" ]] && blue "VMess-WS端口：$port_vm_ws"
  [[ "$use_vm_ws_tls" = "true" ]] && blue "VMess-WS-TLS端口：$port_vm_ws_tls"
  [[ "$use_vm_hu_tls" = "true" ]] && blue "VMess-HTTPUpgrade-TLS端口：$port_vm_hu_tls"
  [[ "$use_tr_tls" = "true" ]] && blue "Trojan-TLS端口：$port_tr_tls"
  [[ "$use_tr_ws_tls" = "true" ]] && blue "Trojan-WS-TLS端口：$port_tr_ws_tls"
  [[ "$use_tr_hu_tls" = "true" ]] && blue "Trojan-HTTPUpgrade-TLS端口：$port_tr_hu_tls"
  [[ "$use_ss" = "true" ]] && blue "Shadowsocks端口：$port_ss"
  [[ "$use_hy2" = "true" ]] && blue "Hysteria-2端口：$port_hy2"
  [[ "$use_tu" = "true" ]] && blue "Tuic-v5端口：$port_tu"
  [[ "$use_an" = "true" ]] && blue "Anytls端口：$port_an"
  [[ "$use_vm_tcp" = "true" ]] && blue "VMess-TCP端口：$port_vm_tcp"
  [[ "$use_vm_http" = "true" ]] && blue "VMess-HTTP端口：$port_vm_http"
  [[ "$use_vm_quic" = "true" ]] && blue "VMess-QUIC端口：$port_vm_quic"
  [[ "$use_vm_h2_tls" = "true" ]] && blue "VMess-H2-TLS端口：$port_vm_h2_tls"
  [[ "$use_vl_h2_tls" = "true" ]] && blue "VLESS-H2-TLS端口：$port_vl_h2_tls"
  [[ "$use_tr_h2_tls" = "true" ]] && blue "Trojan-H2-TLS端口：$port_tr_h2_tls"
  [[ "$use_vl_h2_re" = "true" ]] && blue "VLESS-HTTP2-REALITY端口：$port_vl_h2_re"
  [[ "$use_socks" = "true" ]] && blue "Socks端口：$port_socks"
  
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  green "四、自动生成各个协议独立的uuid (密码)"
  uuid_vl_re=$("$SBFOLDER/sing-box" generate uuid)
  uuid_vl_ws=$("$SBFOLDER/sing-box" generate uuid)
  uuid_vl_hu=$("$SBFOLDER/sing-box" generate uuid)
  uuid_vm_ws=$("$SBFOLDER/sing-box" generate uuid)
  uuid_vm_ws_tls=$("$SBFOLDER/sing-box" generate uuid)
  uuid_vm_hu_tls=$("$SBFOLDER/sing-box" generate uuid)
  uuid_tr_tls=$("$SBFOLDER/sing-box" generate uuid)
  uuid_tr_ws_tls=$("$SBFOLDER/sing-box" generate uuid)
  uuid_tr_hu_tls=$("$SBFOLDER/sing-box" generate uuid)
  uuid_hy2=$("$SBFOLDER/sing-box" generate uuid)
  uuid_tu=$("$SBFOLDER/sing-box" generate uuid)
  uuid_an=$("$SBFOLDER/sing-box" generate uuid)
  uuid_vm_tcp=$("$SBFOLDER/sing-box" generate uuid)
  uuid_vm_http=$("$SBFOLDER/sing-box" generate uuid)
  uuid_vm_quic=$("$SBFOLDER/sing-box" generate uuid)
  uuid_vm_h2_tls=$("$SBFOLDER/sing-box" generate uuid)
  uuid_vl_h2=$("$SBFOLDER/sing-box" generate uuid)
  uuid_tr_h2_tls=$("$SBFOLDER/sing-box" generate uuid)
  uuid_vl_h2_re=$("$SBFOLDER/sing-box" generate uuid)
  socks_username=$("$SBFOLDER/sing-box" generate uuid)
  socks_password=$("$SBFOLDER/sing-box" generate uuid)
  blue "已确认各个协议独立的uuid (密码)已自动生成"
  
  if [[ "$use_ss" = "true" ]]; then
    blue "已确认Shadowsocks加密方式：${ss_method}"
    blue "已确认Shadowsocks密码/密钥：${ss_password}"
  fi
}

# --- JSON Config Generator (Server Side) ---
inssbjsonser() {
  local use_caddy_active=false
  if [[ "$use_caddy" == "true" ]]; then
    use_caddy_active=true
  elif systemctl is-active --quiet caddy 2>/dev/null || rc-service caddy status 2>/dev/null | grep -q "started"; then
    use_caddy_active=true
  fi

  local sb_tls_enabled="true"
  if $use_caddy_active; then
    sb_tls_enabled="false"
  fi

  # Attempt to read existing WireGuard values from sb.json
  if [[ -f "$SBFOLDER/sb.json" ]]; then
    local clean_js=$(strip_json_comments "$SBFOLDER/sb.json")
    local cur_pvk=$(echo "$clean_js" | jq -r ' ((.outbounds[] | select(.type == "wireguard") | .private_key) // (.endpoints[] | select(.type == "wireguard") | .private_key) // empty)' 2>/dev/null | head -n 1)
    [[ -n "$cur_pvk" ]] && pvk="$cur_pvk"
    local cur_v6=$(echo "$clean_js" | jq -r ' ((.outbounds[] | select(.type == "wireguard") | .local_address[1]) // (.endpoints[] | select(.type == "wireguard") | .address[1]) // empty)' 2>/dev/null | cut -d/ -f1 | head -n 1)
    [[ -n "$cur_v6" ]] && v6="$cur_v6"
    local cur_res=$(echo "$clean_js" | jq -c ' ((.outbounds[] | select(.type == "wireguard") | .reserved) // (.endpoints[] | select(.type == "wireguard") | .peers[0].reserved) // empty)' 2>/dev/null | head -n 1)
    [[ -n "$cur_res" ]] && res="$cur_res"
    local cur_endip=$(echo "$clean_js" | jq -r ' ((.outbounds[] | select(.type == "wireguard") | .server) // (.endpoints[] | select(.type == "wireguard") | .peers[0].address) // empty)' 2>/dev/null | head -n 1)
    [[ -n "$cur_endip" ]] && endip="$cur_endip"
  fi
  : ${pvk:="g9I2sgUH6OCbIBTehkEfVEnuvInHYZvPOFhWchMLSc4="}
  : ${v6:="2606:4700:110:860e:738f:b37:f15:d38d"}
  : ${res:="[33,217,129]"}
  : ${endip:="engage.cloudflareclient.com"}
  : ${ipv:="prefer_ipv4"}

  # Attempt to load existing TLS certificate paths and Reality keys
  if [[ -f "$SBFOLDER/sb.json" ]]; then
    local clean_js=$(strip_json_comments "$SBFOLDER/sb.json")
    local cur_cert=$(echo "$clean_js" | jq -r ' (.inbounds[] | select(.tls.certificate_path != null) | .tls.certificate_path) // empty' 2>/dev/null | head -n 1)
    [[ -n "$cur_cert" ]] && certificatec="$cur_cert"
    local cur_key=$(echo "$clean_js" | jq -r ' (.inbounds[] | select(.tls.key_path != null) | .tls.key_path) // empty' 2>/dev/null | head -n 1)
    [[ -n "$cur_key" ]] && certificatep="$cur_key"
    local cur_ym=$(echo "$clean_js" | jq -r ' (.inbounds[] | select(.tls.server_name != null and .tls.reality == null) | .tls.server_name) // empty' 2>/dev/null | head -n 1)
    [[ -n "$cur_ym" ]] && ym_domain="$cur_ym"
    local cur_vl_ym=$(echo "$clean_js" | jq -r ' (.inbounds[] | select(.tls.reality != null) | .tls.server_name) // empty' 2>/dev/null | head -n 1)
    [[ -n "$cur_vl_ym" ]] && ym_vl_re="$cur_vl_ym"
    
    local cur_priv=$(echo "$clean_js" | jq -r ' (.inbounds[] | select(.tls.reality != null) | .tls.reality.private_key) // empty' 2>/dev/null | head -n 1)
    [[ -n "$cur_priv" ]] && private_key="$cur_priv"
    local cur_pub=$(cat "$SBFOLDER/public.key" 2>/dev/null)
    [[ -n "$cur_pub" ]] && public_key="$cur_pub"
    local cur_sid=$(echo "$clean_js" | jq -r ' (.inbounds[] | select(.tls.reality != null) | .tls.reality.short_id[0]) // empty' 2>/dev/null | head -n 1)
    [[ -n "$cur_sid" ]] && short_id="$cur_sid"
  fi

  # Reality key fallbacks if empty
  if [[ -z "$private_key" && -f "$SBFOLDER/private.key" ]]; then
    private_key=$(cat "$SBFOLDER/private.key" 2>/dev/null)
  fi
  if [[ -z "$public_key" && -f "$SBFOLDER/public.key" ]]; then
    public_key=$(cat "$SBFOLDER/public.key" 2>/dev/null)
  fi

  # TLS certificate fallbacks if empty
  if [[ -z "$certificatec" ]]; then
    local cert_type=$(cat /var/Sing-Box-DuolaD/cert_type.log 2>/dev/null)
    if [[ "$cert_type" == "ip" && -f "/var/Sing-Box-DuolaD/ip_cert.pem" ]]; then
      certificatec="/var/Sing-Box-DuolaD/ip_cert.pem"
      certificatep="/var/Sing-Box-DuolaD/ip_private.key"
      ym_domain=""
    elif [[ -f "/var/Sing-Box-DuolaD/domain.log" && -f "/var/Sing-Box-DuolaD/domain_cert.pem" ]]; then
      certificatec="/var/Sing-Box-DuolaD/domain_cert.pem"
      certificatep="/var/Sing-Box-DuolaD/domain_private.key"
      ym_domain=$(cat /var/Sing-Box-DuolaD/domain.log 2>/dev/null)
    elif [[ -f "$SBFOLDER/cert.pem" ]]; then
      certificatec="$SBFOLDER/cert.pem"
      certificatep="$SBFOLDER/private.key"
      ym_domain=$(get_self_domain)
    else
      certificatec="/var/Sing-Box-DuolaD/cert.pem"
      certificatep="/var/Sing-Box-DuolaD/private.key"
      ym_domain=$(get_self_domain)
    fi
  fi

  : ${ym_domain:=$(get_self_domain)}
  : ${ym_vl_re:="apple.com"}
  : ${certificatec:="/var/Sing-Box-DuolaD/cert.pem"}
  : ${certificatep:="/var/Sing-Box-DuolaD/private.key"}

  # VLESS-Reality
  local vl_re_inb='{
    "type": "vless",
    "tag": "vless-reality-sb",
    "listen": "::",
    "listen_port": '"${port_vl_re:-443}"',
    "users": [
      {
        "uuid": "'"${uuid_vl_re}"'",
        "flow": "xtls-rprx-vision"
      }
    ],
    "tls": {
      "enabled": true,
      "server_name": "'"${ym_vl_re:-apple.com}"'",
      "reality": {
        "enabled": true,
        "handshake": {
          "server": "'"${ym_vl_re:-apple.com}"'",
          "server_port": 443
        },
        "private_key": "'"${private_key}"'",
        "short_id": ["'"${short_id}"'"]
      }
    }
  }'

  # VLESS-WS-TLS
  local vl_ws_tls_inb='{
    "type": "vless",
    "tag": "vless-ws-tls-sb",
    "listen": "::",
    "listen_port": '"${port_vl_ws_tls:-443}"',
    "users": [
      {
        "uuid": "'"${uuid_vl_ws}"'"
      }
    ],
    "transport": {
      "type": "ws",
      "path": "/'"${uuid_vl_ws}"'",
      "max_early_data": 2048,
      "early_data_header_name": "Sec-WebSocket-Protocol"
    },
    "tls": {
      "enabled": '"$sb_tls_enabled"',
      "server_name": "'"${ym_domain}"'",
      "certificate_path": "'"${certificatec}"'",
      "key_path": "'"${certificatep}"'"
    }
  }'

  # VLESS-HTTPUpgrade-TLS
  local vl_hu_tls_inb='{
    "type": "vless",
    "tag": "vless-hu-tls-sb",
    "listen": "::",
    "listen_port": '"${port_vl_hu_tls:-443}"',
    "users": [
      {
        "uuid": "'"${uuid_vl_hu}"'"
      }
    ],
    "transport": {
      "type": "httpupgrade",
      "path": "/'"${uuid_vl_hu}"'"
    },
    "tls": {
      "enabled": '"$sb_tls_enabled"',
      "server_name": "'"${ym_domain}"'",
      "certificate_path": "'"${certificatec}"'",
      "key_path": "'"${certificatep}"'"
    }
  }'

  # VMess-WS
  local vm_ws_inb='{
    "type": "vmess",
    "tag": "vmess-ws-sb",
    "listen": "::",
    "listen_port": '"${port_vm_ws:-80}"',
    "users": [
      {
        "uuid": "'"${uuid_vm_ws}"'",
        "alterId": 0
      }
    ],
    "transport": {
      "type": "ws",
      "path": "/'"${uuid_vm_ws}"'",
      "max_early_data": 2048,
      "early_data_header_name": "Sec-WebSocket-Protocol"
    },
    "tls": {
      "enabled": false
    }
  }'

  # VMess-WS-TLS
  local vm_ws_tls_inb='{
    "type": "vmess",
    "tag": "vmess-ws-tls-sb",
    "listen": "::",
    "listen_port": '"${port_vm_ws_tls:-443}"',
    "users": [
      {
        "uuid": "'"${uuid_vm_ws_tls}"'",
        "alterId": 0
      }
    ],
    "transport": {
      "type": "ws",
      "path": "/'"${uuid_vm_ws_tls}"'",
      "max_early_data": 2048,
      "early_data_header_name": "Sec-WebSocket-Protocol"
    },
    "tls": {
      "enabled": '"$sb_tls_enabled"',
      "server_name": "'"${ym_domain}"'",
      "certificate_path": "'"${certificatec}"'",
      "key_path": "'"${certificatep}"'"
    }
  }'

  # VMess-HTTPUpgrade-TLS
  local vm_hu_tls_inb='{
    "type": "vmess",
    "tag": "vmess-hu-tls-sb",
    "listen": "::",
    "listen_port": '"${port_vm_hu_tls:-443}"',
    "users": [
      {
        "uuid": "'"${uuid_vm_hu_tls}"'",
        "alterId": 0
      }
    ],
    "transport": {
      "type": "httpupgrade",
      "path": "/'"${uuid_vm_hu_tls}"'"
    },
    "tls": {
      "enabled": '"$sb_tls_enabled"',
      "server_name": "'"${ym_domain}"'",
      "certificate_path": "'"${certificatec}"'",
      "key_path": "'"${certificatep}"'"
    }
  }'

  # Trojan-TLS
  local tr_tls_inb='{
    "type": "trojan",
    "tag": "trojan-tls-sb",
    "listen": "::",
    "listen_port": '"${port_tr_tls:-443}"',
    "users": [
      {
        "password": "'"${uuid_tr_tls}"'"
      }
    ],
    "tls": {
      "enabled": true,
      "server_name": "'"${ym_domain}"'",
      "certificate_path": "'"${certificatec}"'",
      "key_path": "'"${certificatep}"'"
    }
  }'

  # Trojan-WS-TLS
  local tr_ws_tls_inb='{
    "type": "trojan",
    "tag": "trojan-ws-tls-sb",
    "listen": "::",
    "listen_port": '"${port_tr_ws_tls:-443}"',
    "users": [
      {
        "password": "'"${uuid_tr_ws_tls}"'"
      }
    ],
    "transport": {
      "type": "ws",
      "path": "/'"${uuid_tr_ws_tls}"'",
      "max_early_data": 2048,
      "early_data_header_name": "Sec-WebSocket-Protocol"
    },
    "tls": {
      "enabled": '"$sb_tls_enabled"',
      "server_name": "'"${ym_domain}"'",
      "certificate_path": "'"${certificatec}"'",
      "key_path": "'"${certificatep}"'"
    }
  }'

  # Trojan-HTTPUpgrade-TLS
  local tr_hu_tls_inb='{
    "type": "trojan",
    "tag": "trojan-hu-tls-sb",
    "listen": "::",
    "listen_port": '"${port_tr_hu_tls:-443}"',
    "users": [
      {
        "password": "'"${uuid_tr_hu_tls}"'"
      }
    ],
    "transport": {
      "type": "httpupgrade",
      "path": "/'"${uuid_tr_hu_tls}"'"
    },
    "tls": {
      "enabled": '"$sb_tls_enabled"',
      "server_name": "'"${ym_domain}"'",
      "certificate_path": "'"${certificatec}"'",
      "key_path": "'"${certificatep}"'"
    }
  }'

  # Shadowsocks
  local ss_inb='{
    "type": "shadowsocks",
    "tag": "shadowsocks-sb",
    "listen": "::",
    "listen_port": '"${port_ss:-8388}"',
    "method": "'"${ss_method:-2022-blake3-aes-128-gcm}"'",
    "password": "'"${ss_password}"'"
  }'

  # Hysteria 2
  local hy2_inb='{
    "type": "hysteria2",
    "tag": "hy2-sb",
    "listen": "::",
    "listen_port": '"${port_hy2:-443}"',
    "users": [
      {
        "password": "'"${uuid_hy2}"'"
      }
    ],
    "ignore_client_bandwidth": false,
    "tls": {
      "enabled": true,
      "alpn": ["h3"],
      "certificate_path": "'"${certificatec}"'",
      "key_path": "'"${certificatep}"'"
    }
  }'

  # Tuic-v5
  local tu_inb='{
    "type": "tuic",
    "tag": "tuic5-sb",
    "listen": "::",
    "listen_port": '"${port_tu:-443}"',
    "users": [
      {
        "uuid": "'"${uuid_tu}"'",
        "password": "'"${uuid_tu}"'"
      }
    ],
    "congestion_control": "bbr",
    "tls": {
      "enabled": true,
      "alpn": ["h3"],
      "certificate_path": "'"${certificatec}"'",
      "key_path": "'"${certificatep}"'"
    }
  }'

  # AnyTLS
  local an_inb='{
    "type": "anytls",
    "tag": "anytls-sb",
    "listen": "::",
    "listen_port": '"${port_an:-443}"',
    "users": [
      {
        "password": "'"${uuid_an}"'"
      }
    ],
    "padding_scheme": [],
    "tls": {
      "enabled": true,
      "certificate_path": "'"${certificatec}"'",
      "key_path": "'"${certificatep}"'"
    }
  }'

  # VMess-TCP
  local vm_tcp_inb='{
    "type": "vmess",
    "tag": "vmess-tcp-sb",
    "listen": "::",
    "listen_port": '"${port_vm_tcp:-8080}"',
    "users": [
      {
        "uuid": "'"${uuid_vm_tcp}"'",
        "alterId": 0
      }
    ],
    "tls": {
      "enabled": false
    }
  }'

  # VMess-HTTP
  local vm_http_inb='{
    "type": "vmess",
    "tag": "vmess-http-sb",
    "listen": "::",
    "listen_port": '"${port_vm_http:-8081}"',
    "users": [
      {
        "uuid": "'"${uuid_vm_http}"'",
        "alterId": 0
      }
    ],
    "transport": {
      "type": "http"
    },
    "tls": {
      "enabled": false
    }
  }'

  # VMess-QUIC
  local vm_quic_inb='{
    "type": "vmess",
    "tag": "vmess-quic-sb",
    "listen": "::",
    "listen_port": '"${port_vm_quic:-443}"',
    "users": [
      {
        "uuid": "'"${uuid_vm_quic}"'",
        "alterId": 0
      }
    ],
    "transport": {
      "type": "quic"
    },
    "tls": {
      "enabled": true,
      "alpn": ["h3"],
      "certificate_path": "'"${certificatec}"'",
      "key_path": "'"${certificatep}"'"
    }
  }'

  # VMess-H2-TLS
  local vm_h2_tls_inb='{
    "type": "vmess",
    "tag": "vmess-h2-tls-sb",
    "listen": "::",
    "listen_port": '"${port_vm_h2_tls:-443}"',
    "users": [
      {
        "uuid": "'"${uuid_vm_h2_tls}"'",
        "alterId": 0
      }
    ],
    "transport": {
      "type": "http",
      "host": ["'"${ym_domain}"'"],
      "path": "/'"${uuid_vm_h2_tls}"'"
    },
    "tls": {
      "enabled": true,
      "server_name": "'"${ym_domain}"'",
      "certificate_path": "'"${certificatec}"'",
      "key_path": "'"${certificatep}"'"
    }
  }'

  # VLESS-H2-TLS
  local vl_h2_tls_inb='{
    "type": "vless",
    "tag": "vless-h2-tls-sb",
    "listen": "::",
    "listen_port": '"${port_vl_h2_tls:-443}"',
    "users": [
      {
        "uuid": "'"${uuid_vl_h2}"'"
      }
    ],
    "transport": {
      "type": "http",
      "host": ["'"${ym_domain}"'"],
      "path": "/'"${uuid_vl_h2}"'"
    },
    "tls": {
      "enabled": true,
      "server_name": "'"${ym_domain}"'",
      "certificate_path": "'"${certificatec}"'",
      "key_path": "'"${certificatep}"'"
    }
  }'

  # Trojan-H2-TLS
  local tr_h2_tls_inb='{
    "type": "trojan",
    "tag": "trojan-h2-tls-sb",
    "listen": "::",
    "listen_port": '"${port_tr_h2_tls:-443}"',
    "users": [
      {
        "password": "'"${uuid_tr_h2_tls}"'"
      }
    ],
    "transport": {
      "type": "http",
      "host": ["'"${ym_domain}"'"],
      "path": "/'"${uuid_tr_h2_tls}"'"
    },
    "tls": {
      "enabled": true,
      "server_name": "'"${ym_domain}"'",
      "certificate_path": "'"${certificatec}"'",
      "key_path": "'"${certificatep}"'"
    }
  }'

  # VLESS-HTTP2-REALITY
  local vl_h2_re_inb='{
    "type": "vless",
    "tag": "vless-h2-reality-sb",
    "listen": "::",
    "listen_port": '"${port_vl_h2_re:-443}"',
    "users": [
      {
        "uuid": "'"${uuid_vl_h2_re}"'"
      }
    ],
    "transport": {
      "type": "http",
      "host": ["'"${ym_vl_re:-apple.com}"'"],
      "path": "/'"${uuid_vl_h2_re}"'"
    },
    "tls": {
      "enabled": true,
      "server_name": "'"${ym_vl_re:-apple.com}"'",
      "reality": {
        "enabled": true,
        "handshake": {
          "server": "'"${ym_vl_re:-apple.com}"'",
          "server_port": 443
        },
        "private_key": "'"${private_key}"'",
        "short_id": ["'"${short_id}"'"]
      }
    }
  }'

  # Socks
  local socks_inb='{
    "type": "socks",
    "tag": "socks-sb",
    "listen": "::",
    "listen_port": '"${port_socks:-1080}"',
    "users": [
      {
        "username": "'"${socks_username}"'",
        "password": "'"${socks_password}"'"
      }
    ]
  }'

  # Base 1.11+ json
  local config_json='{
    "log": {
      "disabled": false,
      "level": "info",
      "timestamp": true
    },
    "inbounds": [],
    "endpoints": [
      {
        "type": "wireguard",
        "tag": "warp-out",
        "address": [
          "172.16.0.2/32",
          "'"${v6}/128"'"
        ],
        "private_key": "'"${pvk}"'",
        "peers": [
          {
            "address": "'"${endip}"'",
            "port": 2408,
            "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
            "allowed_ips": [
              "0.0.0.0/0",
              "::/0"
            ],
            "reserved": '"${res}"'
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
          "strategy": "'"${ipv}"'"
        },
        {
          "domain_suffix": ["DuolaD"],
          "outbound": "socks-out"
        },
        {
          "domain_suffix": ["DuolaD"],
          "outbound": "warp-out"
        },
        {
          "outbound": "direct",
          "network": "udp,tcp"
        }
      ]
    }
  }'

  # Default initializations if not set
  : ${use_vl_re:=true}
  : ${use_vl_ws_tls:=false}
  : ${use_vl_hu_tls:=false}
  : ${use_vm_ws:=false}
  : ${use_vm_ws_tls:=false}
  : ${use_vm_hu_tls:=false}
  : ${use_tr_tls:=false}
  : ${use_tr_ws_tls:=false}
  : ${use_tr_hu_tls:=false}
  : ${use_ss:=false}
  : ${use_hy2:=false}
  : ${use_tu:=false}
  : ${use_an:=false}
  : ${use_vm_tcp:=false}
  : ${use_vm_http:=false}
  : ${use_vm_quic:=false}
  : ${use_vm_h2_tls:=false}
  : ${use_vl_h2_tls:=false}
  : ${use_tr_h2_tls:=false}
  : ${use_vl_h2_re:=false}
  : ${use_socks:=false}

  # Dynamically add selected inbounds
  if [[ "$use_vl_re" == "true" ]]; then
    config_json=$(echo "$config_json" | jq --argjson inb "$vl_re_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_vl_ws_tls" == "true" ]]; then
    config_json=$(echo "$config_json" | jq --argjson inb "$vl_ws_tls_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_vl_hu_tls" == "true" ]]; then
    config_json=$(echo "$config_json" | jq --argjson inb "$vl_hu_tls_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_vm_ws" == "true" ]]; then
    config_json=$(echo "$config_json" | jq --argjson inb "$vm_ws_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_vm_ws_tls" == "true" ]]; then
    config_json=$(echo "$config_json" | jq --argjson inb "$vm_ws_tls_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_vm_hu_tls" == "true" ]]; then
    config_json=$(echo "$config_json" | jq --argjson inb "$vm_hu_tls_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_tr_tls" == "true" ]]; then
    config_json=$(echo "$config_json" | jq --argjson inb "$tr_tls_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_tr_ws_tls" == "true" ]]; then
    config_json=$(echo "$config_json" | jq --argjson inb "$tr_ws_tls_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_tr_hu_tls" == "true" ]]; then
    config_json=$(echo "$config_json" | jq --argjson inb "$tr_hu_tls_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_ss" == "true" ]]; then
    config_json=$(echo "$config_json" | jq --argjson inb "$ss_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_hy2" == "true" ]]; then
    config_json=$(echo "$config_json" | jq --argjson inb "$hy2_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_tu" == "true" ]]; then
    config_json=$(echo "$config_json" | jq --argjson inb "$tu_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_an" == "true" ]]; then
    config_json=$(echo "$config_json" | jq --argjson inb "$an_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_vm_tcp" == "true" ]]; then
    config_json=$(echo "$config_json" | jq --argjson inb "$vm_tcp_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_vm_http" == "true" ]]; then
    config_json=$(echo "$config_json" | jq --argjson inb "$vm_http_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_vm_quic" == "true" ]]; then
    config_json=$(echo "$config_json" | jq --argjson inb "$vm_quic_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_vm_h2_tls" == "true" ]]; then
    config_json=$(echo "$config_json" | jq --argjson inb "$vm_h2_tls_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_vl_h2_tls" == "true" ]]; then
    config_json=$(echo "$config_json" | jq --argjson inb "$vl_h2_tls_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_tr_h2_tls" == "true" ]]; then
    config_json=$(echo "$config_json" | jq --argjson inb "$tr_h2_tls_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_vl_h2_re" == "true" ]]; then
    config_json=$(echo "$config_json" | jq --argjson inb "$vl_h2_re_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_socks" == "true" ]]; then
    config_json=$(echo "$config_json" | jq --argjson inb "$socks_inb" '.inbounds += [$inb]')
  fi

  # Post-process config_json to preserve custom certificate paths
  local local_proto_tags=("vless-reality-sb" "vless-ws-tls-sb" "vless-hu-tls-sb" "vless-h2-tls-sb" "vless-h2-reality-sb" "vmess-ws-sb" "vmess-ws-tls-sb" "vmess-hu-tls-sb" "vmess-tcp-sb" "vmess-http-sb" "vmess-quic-sb" "vmess-h2-tls-sb" "trojan-tls-sb" "trojan-ws-tls-sb" "trojan-hu-tls-sb" "trojan-h2-tls-sb" "shadowsocks-sb" "hy2-sb" "tuic5-sb" "anytls-sb" "socks-sb")
  local tag
  for tag in "${local_proto_tags[@]}"; do
    local f_conf="$SBFOLDER/conf/${tag}.json"
    if [[ -f "$f_conf" ]]; then
      local cpath=$(jq -r '.inbounds[0].tls.certificate_path // empty' "$f_conf")
      local kpath=$(jq -r '.inbounds[0].tls.key_path // empty' "$f_conf")
      if [[ -n "$cpath" && "$cpath" != "null" ]]; then
        local jq_filter='(.inbounds[] | select(.tag == $tag) | .tls) |= (.certificate_path = $cert | .key_path = $key)'
        config_json=$(echo "$config_json" | jq --arg tag "$tag" --arg cert "$cpath" --arg key "$kpath" "$jq_filter")
      fi
    fi
  done

  echo "$config_json" > "$SBFOLDER/sb.json"
  sync_configs_from_sb_json
}

get_free_acme_port() {
  local port=9999
  if [[ -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] || \
     [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
    while true; do
      port=$(shuf -i 10000-65535 -n 1)
      if [[ -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && \
         [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
        break
      fi
    done
  fi
  echo "$port"
}

# --- Caddy Helper Functions ---
write_caddyfile() {
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
  
  local server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null || curl -s4 ip.sb)
  local ym_domain=$(cat /var/Sing-Box-DuolaD/domain.log 2>/dev/null)
  local acme_port=$(cat /var/Sing-Box-DuolaD/acme_port.log 2>/dev/null || echo "9999")
  local global_cert_type=$(cat /var/Sing-Box-DuolaD/cert_type.log 2>/dev/null || echo "self")

  # Define Caddy-proxied protocol tags, ports, and paths
  local caddy_tags=("vless-ws-tls-sb" "vless-hu-tls-sb" "vless-h2-tls-sb" "vmess-ws-tls-sb" "vmess-hu-tls-sb" "vmess-h2-tls-sb" "trojan-ws-tls-sb" "trojan-hu-tls-sb" "trojan-h2-tls-sb")
  
  # Group lists
  local group_self_proxies=""
  local group_ip_proxies=""
  local group_domain_proxies=""

  local tag
  for tag in "${caddy_tags[@]}"; do
    local port=$(echo "$clean_json" | jq -r ".inbounds[] | select(.tag == \"$tag\") | .listen_port // empty" 2>/dev/null | head -n 1)
    local path=""
    if [[ "$tag" =~ "trojan" ]]; then
      path=$(echo "$clean_json" | jq -r ".inbounds[] | select(.tag == \"$tag\") | .users[0].password // empty" 2>/dev/null | head -n 1)
    else
      path=$(echo "$clean_json" | jq -r ".inbounds[] | select(.tag == \"$tag\") | .users[0].uuid // empty" 2>/dev/null | head -n 1)
    fi

    if [[ -n "$port" && -n "$path" ]]; then
      # Get certificate type for this protocol
      local p_cert=$(grep -w "^${tag}:" /var/Sing-Box-DuolaD/proto_certs.log 2>/dev/null | cut -d: -f2)
      [[ -z "$p_cert" ]] && p_cert="$global_cert_type"

      local proxy_directive=""
      if [[ "$tag" =~ "-h2-tls" ]]; then
        proxy_directive="  reverse_proxy /$path https://127.0.0.1:$port {
    transport http {
      tls_insecure_skip_verify
    }
  }"
      else
        proxy_directive="  reverse_proxy /$path 127.0.0.1:$port"
      fi

      if [[ "$p_cert" == "self" ]]; then
        group_self_proxies="${group_self_proxies}${proxy_directive}
"
      elif [[ "$p_cert" == "ip" ]]; then
        group_ip_proxies="${group_ip_proxies}${proxy_directive}
"
      elif [[ "$p_cert" == "domain" ]]; then
        group_domain_proxies="${group_domain_proxies}${proxy_directive}
"
      fi
    fi
  done

  # Now write the Caddyfile!
  mkdir -p /etc/caddy
  cat > /etc/caddy/Caddyfile <<EOF
{
  admin off
}
EOF

  # 1. Self-signed block
  if [[ -n "$group_self_proxies" ]]; then
    cat >> /etc/caddy/Caddyfile <<EOF

:443 {
  tls /var/Sing-Box-DuolaD/self_cert.pem /var/Sing-Box-DuolaD/self_private.key
  reverse_proxy /.well-known/acme-challenge/* 127.0.0.1:$acme_port
$group_self_proxies}
EOF
  fi

  # 2. IP block
  if [[ -n "$group_ip_proxies" && -n "$server_ip" ]]; then
    cat >> /etc/caddy/Caddyfile <<EOF

:443 {
  tls /var/Sing-Box-DuolaD/ip_cert.pem /var/Sing-Box-DuolaD/ip_private.key
  reverse_proxy /.well-known/acme-challenge/* 127.0.0.1:$acme_port
$group_ip_proxies}
EOF
  fi

  # 3. Domain block
  if [[ -n "$group_domain_proxies" && -n "$ym_domain" ]]; then
    local caddy_domain_listen="$ym_domain:443"
    if [[ "$ym_domain" == \*.* ]]; then
      caddy_domain_listen="${ym_domain#*.}:443, $ym_domain:443"
    fi

    cat >> /etc/caddy/Caddyfile <<EOF

$caddy_domain_listen {
  tls /var/Sing-Box-DuolaD/domain_cert.pem /var/Sing-Box-DuolaD/domain_private.key
  reverse_proxy /.well-known/acme-challenge/* 127.0.0.1:$acme_port
$group_domain_proxies}
EOF
  fi
}

select_ip_cert_mode() {
  local server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null || echo "")
  local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
  local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)

  if [[ -z "$v4_addr" ]]; then
    v4_addr=$(curl -s4 --max-time 3 ip.sb 2>/dev/null || curl -s4 --max-time 3 4.ipw.cn 2>/dev/null)
  fi
  if [[ -z "$v6_addr" ]]; then
    v6_addr=$(curl -s6 --max-time 3 ip.sb 2>/dev/null || curl -s6 --max-time 3 6.ipw.cn 2>/dev/null)
  fi

  local mode="v4"
  if [[ "$server_ip" == "dual" || (-n "$v4_addr" && -n "$v6_addr") ]]; then
    echo
    green "检测到当前服务器为 IPv4 + IPv6 双栈网络，请选择纯 IP 证书申请类型："
    yellow "1: 为双栈 IP (IPv4 + IPv6) 共同申请证书 (回车默认)"
    yellow "2: 仅为 IPv4 地址 (${v4_addr:-IPv4}) 申请证书"
    yellow "3: 仅为 IPv6 地址 (${v6_addr:-IPv6}) 申请证书"
    readp "请选择【1-3】(默认 1)：" ip_choice
    case "$ip_choice" in
      2) mode="v4" ;;
      3) mode="v6" ;;
      *) mode="dual" ;;
    esac
  elif [[ -n "$v6_addr" && -z "$v4_addr" ]]; then
    mode="v6"
  else
    mode="v4"
  fi

  mkdir -p /var/Sing-Box-DuolaD
  echo "$mode" > /var/Sing-Box-DuolaD/ip_cert_mode.log
}

setup_caddy_cert() {
  echo "$cert_type" > /var/Sing-Box-DuolaD/cert_type.log
  mkdir -p /var/Sing-Box-DuolaD
  
  if [[ "$cert_type" == "self" ]]; then
    local self_dom=$(get_self_domain)
    blue "正在生成自签证书 (伪装域名: $self_dom)..."
    generate_self_signed_cert /var/Sing-Box-DuolaD/private.key /var/Sing-Box-DuolaD/cert.pem "$self_dom"
    cp -f /var/Sing-Box-DuolaD/private.key "$SBFOLDER/private.key" 2>/dev/null
    cp -f /var/Sing-Box-DuolaD/cert.pem "$SBFOLDER/cert.pem" 2>/dev/null
    cp -f /var/Sing-Box-DuolaD/ca.pem "$SBFOLDER/ca.pem" 2>/dev/null
    is_self_signed=true
    tls_sni="$self_dom"
    ym_domain="$self_dom"
    certificatec="/var/Sing-Box-DuolaD/cert.pem"
    certificatep="/var/Sing-Box-DuolaD/private.key"
  elif [[ "$cert_type" == "ip" ]]; then
    if [[ ! -f /var/Sing-Box-DuolaD/ip_cert_mode.log ]]; then
      select_ip_cert_mode
    fi
    local ip_mode=$(cat /var/Sing-Box-DuolaD/ip_cert_mode.log 2>/dev/null || echo "v4")
    local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
    local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
    
    if [[ -z "$v4_addr" && "$ip_mode" != "v6" ]]; then
      v4_addr=$(curl -s4 --max-time 3 ip.sb 2>/dev/null || curl -s4 --max-time 3 4.ipw.cn 2>/dev/null)
    fi
    if [[ -z "$v6_addr" && "$ip_mode" != "v4" ]]; then
      v6_addr=$(curl -s6 --max-time 3 ip.sb 2>/dev/null || curl -s6 --max-time 3 6.ipw.cn 2>/dev/null)
    fi
    local acme_ip_args=""
    local main_ip=""

    if [[ "$ip_mode" == "dual" && -n "$v4_addr" && -n "$v6_addr" ]]; then
      acme_ip_args="-d $v4_addr -d $v6_addr"
      main_ip="$v4_addr"
      blue "正在使用 acme.sh 申请双栈 IP 证书 ($v4_addr 和 $v6_addr)..."
    elif [[ "$ip_mode" == "v6" && -n "$v6_addr" ]]; then
      acme_ip_args="-d $v6_addr"
      main_ip="$v6_addr"
      blue "正在使用 acme.sh 申请 IPv6 证书 ($v6_addr)..."
    else
      local target_v4="${v4_addr:-$(cat "$SBFOLDER/server_ip.log" 2>/dev/null || curl -s4 ip.sb)}"
      acme_ip_args="-d $target_v4"
      main_ip="$target_v4"
      blue "正在使用 acme.sh 申请 IPv4 证书 ($target_v4)..."
    fi
    
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
      blue "正在安装 acme.sh..."
      curl -s https://get.acme.sh | sh >/dev/null 2>&1
    fi
    
    local acme_port=$(get_free_acme_port)
    echo "$acme_port" > /var/Sing-Box-DuolaD/acme_port.log
    
    local acme_port_arg=""
    local listen_v6_arg=""
    if [[ "$ip_mode" == "dual" || "$ip_mode" == "v6" ]]; then
      listen_v6_arg="--listen-v6"
    fi
    if ss -tunlp | grep -q -E ":80\b"; then
      yellow "检测到 80 端口已被占用，将使用 Caddy 反代进行校验转发 (转发端口: $acme_port)..."
      acme_port_arg="--httpport $acme_port"
    fi
    
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force > /dev/null 2>&1
    ~/.acme.sh/acme.sh --register-account -m "caddy_singbox@gmail.com" > /dev/null 2>&1
    
    ~/.acme.sh/acme.sh --issue \
        $acme_ip_args \
        --standalone \
        --server letsencrypt \
        --certificate-profile shortlived \
        --days 6 \
        $acme_port_arg \
        $listen_v6_arg \
        --force
        
    if [[ $? -eq 0 ]]; then
      local ip_reload_cmd="cp -f /var/Sing-Box-DuolaD/ip_cert.pem /var/Sing-Box-DuolaD/cert.pem 2>/dev/null; cp -f /var/Sing-Box-DuolaD/ip_private.key /var/Sing-Box-DuolaD/private.key 2>/dev/null; cp -f /var/Sing-Box-DuolaD/ip_cert.pem \"$SBFOLDER/cert.pem\" 2>/dev/null; cp -f /var/Sing-Box-DuolaD/ip_private.key \"$SBFOLDER/private.key\" 2>/dev/null; { systemctl is-active --quiet caddy 2>/dev/null && systemctl reload caddy 2>/dev/null; } || { rc-service caddy status 2>/dev/null | grep -q started && rc-service caddy reload 2>/dev/null; } || true; { systemctl is-active --quiet sing-box 2>/dev/null && systemctl restart sing-box 2>/dev/null; } || { rc-service sing-box status 2>/dev/null | grep -q started && rc-service sing-box restart 2>/dev/null; } || true"
      
      ~/.acme.sh/acme.sh --installcert --force -d "$main_ip" \
          --key-file "/var/Sing-Box-DuolaD/ip_private.key" \
          --fullchain-file "/var/Sing-Box-DuolaD/ip_cert.pem" \
          --reloadcmd "$ip_reload_cmd"
      chmod 600 /var/Sing-Box-DuolaD/ip_private.key
      chmod 644 /var/Sing-Box-DuolaD/ip_cert.pem
      cp -f /var/Sing-Box-DuolaD/ip_private.key /var/Sing-Box-DuolaD/private.key 2>/dev/null
      cp -f /var/Sing-Box-DuolaD/ip_cert.pem /var/Sing-Box-DuolaD/cert.pem 2>/dev/null
      cp -f /var/Sing-Box-DuolaD/private.key "$SBFOLDER/private.key" 2>/dev/null
      cp -f /var/Sing-Box-DuolaD/cert.pem "$SBFOLDER/cert.pem" 2>/dev/null
      blue "IP 证书申请并安装成功！"
      is_self_signed=false
      tls_sni="$server_ip"
      ym_domain="$server_ip"
      certificatec="/var/Sing-Box-DuolaD/cert.pem"
      certificatep="/var/Sing-Box-DuolaD/private.key"
    else
      red "IP 证书申请失败！回退使用自签证书。"
      cert_type="self"
      setup_caddy_cert
    fi
  elif [[ "$cert_type" == "domain" ]]; then
    blue "正在使用 acme.sh 申请域名证书 ($ym_domain)..."
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
      blue "正在安装 acme.sh..."
      curl -s https://get.acme.sh | sh >/dev/null 2>&1
    fi
    
    local dns_prov=$(cat /var/Sing-Box-DuolaD/acme_provider.log 2>/dev/null)
    local issue_status=1
    local install_domain="$ym_domain"
    
    if [[ -n "$dns_prov" && -f /var/Sing-Box-DuolaD/dns_api.log ]]; then
      local api_info=$(cat /var/Sing-Box-DuolaD/dns_api.log 2>/dev/null)
      if [[ "$dns_prov" == "dns_cf" ]]; then
        local mode=$(echo "$api_info" | cut -d'|' -f2)
        if [[ "$mode" == "token" ]]; then
          export CF_Account_ID=$(echo "$api_info" | cut -d'|' -f3)
          export CF_Token=$(echo "$api_info" | cut -d'|' -f4)
        else
          export CF_Email=$(echo "$api_info" | cut -d'|' -f3)
          export CF_Key=$(echo "$api_info" | cut -d'|' -f4)
        fi
      elif [[ "$dns_prov" == "dns_dp" ]]; then
        export DP_Id=$(echo "$api_info" | cut -d'|' -f2)
        export DP_Key=$(echo "$api_info" | cut -d'|' -f3)
      elif [[ "$dns_prov" == "dns_ali" ]]; then
        export Ali_Key=$(echo "$api_info" | cut -d'|' -f2)
        export Ali_Secret=$(echo "$api_info" | cut -d'|' -f3)
      fi
      
      local issue_args=""
      if [[ "$ym_domain" == \*.* ]]; then
        local main_dom="${ym_domain#*.}"
        issue_args="-d $main_dom -d $ym_domain"
        install_domain="$main_dom"
      else
        issue_args="-d $ym_domain"
      fi
      
      blue "正在使用 acme.sh (DNS API 模式: $dns_prov) 申请域名证书 ($ym_domain)..."
      ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force > /dev/null 2>&1
      ~/.acme.sh/acme.sh --register-account -m "caddy_singbox@gmail.com" > /dev/null 2>&1
      ~/.acme.sh/acme.sh --issue $issue_args --dns $dns_prov -k ec-256 --server letsencrypt --force
      issue_status=$?
    else
      local acme_port=$(get_free_acme_port)
      echo "$acme_port" > /var/Sing-Box-DuolaD/acme_port.log
      
      local acme_port_arg=""
      if ss -tunlp | grep -q -E ":80\b"; then
        yellow "检测到 80 端口已被占用，将使用 Caddy 反代进行校验转发 (转发端口: $acme_port)..."
        acme_port_arg="--httpport $acme_port"
      fi
      
      blue "正在使用 acme.sh (HTTP 独立/反代模式) 申请域名证书 ($ym_domain)..."
      ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force > /dev/null 2>&1
      ~/.acme.sh/acme.sh --register-account -m "caddy_singbox@gmail.com" > /dev/null 2>&1
      ~/.acme.sh/acme.sh --issue -d "$ym_domain" --standalone --server letsencrypt $acme_port_arg --force
      issue_status=$?
    fi

    if [[ $issue_status -eq 0 ]]; then
      local domain_reload_cmd="cp -f /var/Sing-Box-DuolaD/domain_cert.pem /var/Sing-Box-DuolaD/cert.pem 2>/dev/null; cp -f /var/Sing-Box-DuolaD/domain_private.key /var/Sing-Box-DuolaD/private.key 2>/dev/null; cp -f /var/Sing-Box-DuolaD/domain_cert.pem \"$SBFOLDER/cert.pem\" 2>/dev/null; cp -f /var/Sing-Box-DuolaD/domain_private.key \"$SBFOLDER/private.key\" 2>/dev/null; { systemctl is-active --quiet caddy 2>/dev/null && systemctl reload caddy 2>/dev/null; } || { rc-service caddy status 2>/dev/null | grep -q started && rc-service caddy reload 2>/dev/null; } || true; { systemctl is-active --quiet sing-box 2>/dev/null && systemctl restart sing-box 2>/dev/null; } || { rc-service sing-box status 2>/dev/null | grep -q started && rc-service sing-box restart 2>/dev/null; } || true"
      
      ~/.acme.sh/acme.sh --installcert --force -d "$install_domain" \
          --key-file "/var/Sing-Box-DuolaD/domain_private.key" \
          --fullchain-file "/var/Sing-Box-DuolaD/domain_cert.pem" \
          --reloadcmd "$domain_reload_cmd"
      chmod 600 /var/Sing-Box-DuolaD/domain_private.key
      chmod 644 /var/Sing-Box-DuolaD/domain_cert.pem
      cp -f /var/Sing-Box-DuolaD/domain_private.key /var/Sing-Box-DuolaD/private.key 2>/dev/null
      cp -f /var/Sing-Box-DuolaD/domain_cert.pem /var/Sing-Box-DuolaD/cert.pem 2>/dev/null
      cp -f /var/Sing-Box-DuolaD/private.key "$SBFOLDER/private.key" 2>/dev/null
      cp -f /var/Sing-Box-DuolaD/cert.pem "$SBFOLDER/cert.pem" 2>/dev/null
      blue "域名证书申请并安装成功！"
      is_self_signed=false
      tls_sni="$ym_domain"
      [[ "$ym_domain" == \*.* ]] && tls_sni="node.${ym_domain#*.}"
      certificatec="/var/Sing-Box-DuolaD/cert.pem"
      certificatep="/var/Sing-Box-DuolaD/private.key"
    else
      red "域名证书申请失败！回退使用自签证书。"
      cert_type="self"
      setup_caddy_cert
    fi
  fi
}

caddyservice() {
  [[ "$use_caddy" != "true" ]] && return 0
  
  if [[ ! -f /usr/local/bin/caddy ]]; then
    echo
    blue "正在下载并安装 Caddy..."
    local cver="2.8.4"
    local arch_name="amd64"
    case "$cpu" in
      arm64) arch_name="arm64" ;;
      armv7) arch_name="armv6" ;;
      amd64) arch_name="amd64" ;;
    esac
    local caddy_url="https://github.com/caddyserver/caddy/releases/download/v${cver}/caddy_${cver}_linux_${arch_name}.tar.gz"
    mkdir -p /tmp/caddy
    if curl -sL "$caddy_url" -o /tmp/caddy/caddy.tar.gz; then
      tar -zxf /tmp/caddy/caddy.tar.gz -C /tmp/caddy
      mv -f /tmp/caddy/caddy /usr/local/bin/caddy
      chmod +x /usr/local/bin/caddy
      rm -rf /tmp/caddy
      blue "Caddy 安装成功"
    else
      red "Caddy 下载失败！"
      exit 1
    fi
  fi

  write_caddyfile

  if command -v apk >/dev/null 2>&1; then
    cat > /etc/init.d/caddy <<EOF
#!/sbin/openrc-run
name="Caddy"
description="Caddy web server"
command="/usr/local/bin/caddy"
command_args="run --environ --config /etc/caddy/Caddyfile --adapter caddyfile"
command_background=true
pidfile="/var/run/caddy.pid"

supervisor=supervise-daemon

depend() {
    need net
    after firewall
}
EOF
    chmod +x /etc/init.d/caddy
    rc-update add caddy default
    rc-service caddy restart
  else
    cat > /etc/systemd/system/caddy.service <<EOF
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=exec
User=root
Group=root
ExecStart=/usr/local/bin/caddy run --environ --config /etc/caddy/Caddyfile --adapter caddyfile
ExecReload=/usr/local/bin/caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
TimeoutStopSec=5s
LimitNPROC=10000
LimitNOFILE=1048576
PrivateTmp=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable caddy
    systemctl restart caddy
  fi
  
  blue "Caddy 服务已启动/重启！"
}

# --- Service Management (Systemd & OpenRC) ---
sbservice() {
  if command -v apk >/dev/null 2>&1; then
    echo '#!/sbin/openrc-run
description="sing-box service"
command="/var/Sing-Box-DuolaD/sing-box"
command_args="run -c /var/Sing-Box-DuolaD/config.json -C /var/Sing-Box-DuolaD/conf/"
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
ExecStart=/var/Sing-Box-DuolaD/sing-box run -c /var/Sing-Box-DuolaD/config.json -C /var/Sing-Box-DuolaD/conf/
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
      echo "$v4" > "$SBFOLDER/v4.log"
      echo "$v6" > "$SBFOLDER/v6.log"
      green "调整IPv4/IPV6配置输出"
      yellow "1：刷新本地IP，使用IPV4配置输出 (回车默认) "
      yellow "2：刷新本地IP，使用IPV6配置输出"
      yellow "3：刷新本地IP，使用双栈配置输出"
      readp "请选择【1-3】：" menu
      if [ -z "$menu" ] || [ "$menu" = "1" ]; then
        server_ip="$v4"
        server_ipcl="$v4"
      elif [ "$menu" = "2" ]; then
        server_ip="[$v6]"
        server_ipcl="$v6"
      else
        server_ip="dual"
        server_ipcl="dual"
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
  local file="$1"
  if [[ "$file" == *"/sb.json" ]]; then
    if [ -f "$SBFOLDER/config.json" ]; then
      local combined_json=$(cat "$SBFOLDER/config.json" | sed 's|^\s*//.*||g; s|[ \t]\+//.*||g')
      if [ -d "$SBFOLDER/conf" ]; then
        for f in "$SBFOLDER/conf"/*.json; do
          if [ -f "$f" ]; then
            local f_json=$(cat "$f" | sed 's|^\s*//.*||g; s|[ \t]\+//.*||g')
            combined_json=$(jq --argjson f_json "$f_json" '.inbounds += ($f_json.inbounds // [])' <<< "$combined_json" 2>/dev/null || echo "$combined_json")
          fi
        done
      fi
      echo "$combined_json" > "$SBFOLDER/sb.json"
      echo "$combined_json"
      return
    fi
  fi
  if [ -f "$file" ]; then
    sed 's|^\s*//.*||g; s|[ \t]\+//.*||g' "$file"
  else
    echo "{}"
  fi
}

sync_configs_from_sb_json() {
  if [ -f "$SBFOLDER/sb.json" ]; then
    local clean_json=$(sed 's|^\s*//.*||g; s|[ \t]\+//.*||g' "$SBFOLDER/sb.json")
    if [[ -n "$clean_json" ]]; then
      mkdir -p "$SBFOLDER/conf"
      rm -f "$SBFOLDER/conf"/*.json
      
      local num_inbounds=$(echo "$clean_json" | jq '.inbounds | length' 2>/dev/null)
      if [[ -n "$num_inbounds" && "$num_inbounds" -gt 0 ]]; then
        for ((i=0; i<num_inbounds; i++)); do
          local inb=$(echo "$clean_json" | jq ".inbounds[$i]" 2>/dev/null)
          local tag=$(echo "$inb" | jq -r '.tag // empty' 2>/dev/null)
          if [[ -n "$tag" ]]; then
            echo "{\"inbounds\": [$inb]}" > "$SBFOLDER/conf/${tag}.json"
          fi
        done
      fi
      
      local base_config=$(echo "$clean_json" | jq '.inbounds = []' 2>/dev/null)
      if [[ -n "$base_config" ]]; then
        echo "$base_config" > "$SBFOLDER/config.json"
        echo "$base_config" > "$SBFOLDER/config10.json"
        echo "$base_config" > "$SBFOLDER/config11.json"
      fi
    fi
  fi
}

result_vl_vm_hy_tu() {
  if [[ -f /var/Sing-Box-DuolaD/domain_cert.pem && -f /var/Sing-Box-DuolaD/domain_private.key ]]; then
    ym=$(bash ~/.acme.sh/acme.sh --list 2>/dev/null | tail -1 | awk '{print $1}')
    [ -n "$ym" ] && echo "$ym" > /var/Sing-Box-DuolaD/domain.log
  fi
  rm -rf "$SBFOLDER"/{vm_ws_argo.txt,vm_ws.txt,vm_ws_tls.txt}
  
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
  server_ipcl=$(cat "$SBFOLDER/server_ipcl.log" 2>/dev/null)

  if [[ -f "$SBFOLDER/cfvmadd_local.txt" ]]; then
    vmadd_local=$(cat "$SBFOLDER/cfvmadd_local.txt" 2>/dev/null)
  else
    vmadd_local="$server_ipcl"
  fi

  if [[ -f "$SBFOLDER/cfvmadd_argo.txt" ]]; then
    vmadd_argo=$(cat "$SBFOLDER/cfvmadd_argo.txt" 2>/dev/null)
  else
    vmadd_argo="cloudflare-ech.com"
  fi
  
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
  
  query_inbound_port() {
    local tag="$1"
    echo "$clean_json" | jq -r ".inbounds[] | select(.tag == \"$tag\") | .listen_port // empty" 2>/dev/null | head -n 1
  }

  uuid_vl_re=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vless-reality-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_vl_ws=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vless-ws-tls-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_vl_hu=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vless-hu-tls-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_vm_ws=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vmess-ws-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_vm_ws_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vmess-ws-tls-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_vm_hu_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vmess-hu-tls-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_tr_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "trojan-tls-sb") | .users[0].password // empty' 2>/dev/null | head -n 1)
  uuid_tr_ws_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "trojan-ws-tls-sb") | .users[0].password // empty' 2>/dev/null | head -n 1)
  uuid_tr_hu_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "trojan-hu-tls-sb") | .users[0].password // empty' 2>/dev/null | head -n 1)
  uuid_hy2=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "hy2-sb") | .users[0].password // empty' 2>/dev/null | head -n 1)
  uuid_tu=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "tuic5-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_an=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "anytls-sb") | .users[0].password // empty' 2>/dev/null | head -n 1)
  uuid_vm_tcp=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vmess-tcp-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_vm_http=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vmess-http-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_vm_quic=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vmess-quic-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_vm_h2_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vmess-h2-tls-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_vl_h2=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vless-h2-tls-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_tr_h2_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "trojan-h2-tls-sb") | .users[0].password // empty' 2>/dev/null | head -n 1)
  uuid_vl_h2_re=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vless-h2-reality-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  socks_username=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "socks-sb") | .users[0].username // empty' 2>/dev/null | head -n 1)
  socks_password=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "socks-sb") | .users[0].password // empty' 2>/dev/null | head -n 1)
  
  port_vl_re=$(query_inbound_port "vless-reality-sb")
  port_vl_ws_tls=$(query_inbound_port "vless-ws-tls-sb")
  port_vl_hu_tls=$(query_inbound_port "vless-hu-tls-sb")
  port_vm_ws=$(query_inbound_port "vmess-ws-sb")
  port_vm_ws_tls=$(query_inbound_port "vmess-ws-tls-sb")
  port_vm_hu_tls=$(query_inbound_port "vmess-hu-tls-sb")
  port_tr_tls=$(query_inbound_port "trojan-tls-sb")
  port_tr_ws_tls=$(query_inbound_port "trojan-ws-tls-sb")
  port_tr_hu_tls=$(query_inbound_port "trojan-hu-tls-sb")
  port_ss=$(query_inbound_port "shadowsocks-sb")
  port_hy2=$(query_inbound_port "hy2-sb")
  port_tu=$(query_inbound_port "tuic5-sb")
  port_an=$(query_inbound_port "anytls-sb")
  port_vm_tcp=$(query_inbound_port "vmess-tcp-sb")
  port_vm_http=$(query_inbound_port "vmess-http-sb")
  port_vm_quic=$(query_inbound_port "vmess-quic-sb")
  port_vm_h2_tls=$(query_inbound_port "vmess-h2-tls-sb")
  port_vl_h2_tls=$(query_inbound_port "vless-h2-tls-sb")
  port_tr_h2_tls=$(query_inbound_port "trojan-h2-tls-sb")
  port_vl_h2_re=$(query_inbound_port "vless-h2-reality-sb")
  port_socks=$(query_inbound_port "socks-sb")

  # Reality keys
  vl_name=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vless-reality-sb" or .tag == "vless-h2-reality-sb") | .tls.server_name // empty' 2>/dev/null | head -n 1)
  public_key=$(cat "$SBFOLDER/public.key" 2>/dev/null)
  short_id=$(echo "$clean_json" | jq -r ' (.inbounds[] | select(.tag == "vless-reality-sb" or .tag == "vless-h2-reality-sb") | .tls.reality.short_id[0]) // empty' 2>/dev/null | head -n 1)
  
  # Shadowsocks credentials
  ss_password=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "shadowsocks-sb") | .password // empty' 2>/dev/null | head -n 1)
  ss_method=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "shadowsocks-sb") | .method // empty' 2>/dev/null | head -n 1)

  # Check certificate mode
  ym=$(cat /var/Sing-Box-DuolaD/domain.log 2>/dev/null)
  local cur_cert_type=$(cat /var/Sing-Box-DuolaD/cert_type.log 2>/dev/null)
  if [[ "$cur_cert_type" == "ip" ]]; then
    is_self_signed=false
    local server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null || curl -s4 ip.sb)
    tls_sni="$server_ip"
  elif [[ "$cur_cert_type" == "domain" ]]; then
    is_self_signed=false
    tls_sni="${ym:-$(get_self_domain)}"
  elif [[ "$cur_cert_type" == "self" ]]; then
    is_self_signed=true
    tls_sni=$(get_self_domain)
  else
    if [[ -f /var/Sing-Box-DuolaD/domain_cert.pem ]]; then
      is_self_signed=false
      tls_sni="${ym:-$(get_self_domain)}"
    elif [[ -f /var/Sing-Box-DuolaD/ip_cert.pem ]]; then
      is_self_signed=false
      local server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null || curl -s4 ip.sb)
      tls_sni="$server_ip"
    else
      is_self_signed=true
      tls_sni=$(get_self_domain)
    fi
  fi

  # Hysteria 2 parameters
  hy2_ports=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$port_hy2" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ',' | sed 's/,$//')
  if [[ -n $hy2_ports ]]; then
    cmhy2pt=$(echo $hy2_ports | tr ':' '-')
    hyps="&mport=$cmhy2pt"
    sbhy2pt=$(echo "$hy2_ports" | grep -o '[0-9]\+:[0-9]\+' | sed 's/.*/"&"/' | paste -sd,)
  else
    hyps=""
    sbhy2pt=""
  fi
  
  if [[ -f "$SBFOLDER/cert.pem" ]]; then
    SHA256=$(openssl x509 -in "$SBFOLDER/cert.pem" -outform DER | sha256sum | awk '{print $1}')
    echo "$SHA256" > "$SBFOLDER/SHA256.txt"
  fi
  
  # TUIC and AnyTLS ports are mapped already.
  # Let's map variables for sharing client helpers
  if [[ "$is_self_signed" = "true" ]]; then
    SHA256=$(cat "$SBFOLDER/SHA256.txt" 2>/dev/null)
    local s_dom=$(get_self_domain)
    hy2_name="$s_dom"
    sb_hy2_ip=$server_ip
    cl_hy2_ip=$server_ipcl
    ins_hy2=1
    hy2_ins=false
    
    tu5_name="$s_dom"
    sb_tu5_ip=$server_ip
    cl_tu5_ip=$server_ipcl
    ins=1
    tu5_ins=true

    an_name="$s_dom"
    sb_an_ip=$server_ip
    cl_an_ip=$server_ipcl
    ins_an=1
    an_ins=true
  else
    local cur_cert_type=$(cat /var/Sing-Box-DuolaD/cert_type.log 2>/dev/null)
    local target_sni="$ym"
    local target_ip="$ym"
    local target_ipcl="$ym"
    if [[ "$cur_cert_type" == "ip" || -z "$ym" ]]; then
      local server_ip_val=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null || curl -s4 ip.sb)
      [[ "$server_ip_val" == "dual" ]] && server_ip_val=$(cat "$SBFOLDER/v4.log" 2>/dev/null || curl -s4 ip.sb)
      local server_ipcl_val=$(cat "$SBFOLDER/server_ipcl.log" 2>/dev/null || echo "$server_ip_val")
      [[ "$server_ipcl_val" == "dual" ]] && server_ipcl_val=$(cat "$SBFOLDER/v4.log" 2>/dev/null || echo "$server_ip_val")
      target_sni="$server_ip_val"
      target_ip="$server_ip_val"
      target_ipcl="$server_ipcl_val"
    fi

    hy2_name="$target_sni"
    sb_hy2_ip="$target_ip"
    cl_hy2_ip="$target_ipcl"
    ins_hy2=0
    hy2_ins=false
    
    tu5_name="$target_sni"
    sb_tu5_ip="$target_ip"
    cl_tu5_ip="$target_ipcl"
    ins=0
    tu5_ins=false

    an_name="$target_sni"
    sb_an_ip="$target_ip"
    cl_an_ip="$target_ipcl"
    ins_an=0
    an_ins=false
  fi
}

resvless() {
  [[ -z "$port_vl_re" && -z "$port_vl_ws_tls" && -z "$port_vl_hu_tls" ]] && return 0
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
  local vl_tls_params="insecure=0&allowInsecure=0"
  if [[ "$is_self_signed" = "true" ]]; then
    vl_tls_params+="&pinnedPeerCertSha256=$SHA256"
  fi
  
  local caddy_active=false
  if systemctl is-active --quiet caddy 2>/dev/null || rc-service caddy status 2>/dev/null | grep -q "started"; then
    caddy_active=true
  fi

  local p_vl_ws="$port_vl_ws_tls"
  local p_vl_hu="$port_vl_hu_tls"
  local s_ip_ws="$server_ip"
  local s_ip_hu="$server_ip"
  
  if $caddy_active; then
    p_vl_ws="443"
    p_vl_hu="443"
    local cert_type=$(cat /var/Sing-Box-DuolaD/cert_type.log 2>/dev/null || echo "self")
    if [[ "$cert_type" == "domain" && -n "$tls_sni" ]]; then
      s_ip_ws="$tls_sni"
      s_ip_hu="$tls_sni"
    fi
  fi

  local ip_tag="IPV4"
  if [[ "$server_ip" =~ : ]]; then ip_tag="IPV6"; fi

  if [[ -n "$port_vl_re" ]]; then
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    if [[ "$server_ip" = "dual" ]]; then
      local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
      local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
      vl_link_v4="vless://$uuid_vl_re@$v4_addr:$port_vl_re?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$vl_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#vl-reality-$hostname-IPV4"
      vl_link_v6="vless://$uuid_vl_re@[$v6_addr]:$port_vl_re?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$vl_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#vl-reality-$hostname-IPV6"
      echo -e "$vl_link_v4\n$vl_link_v6" > "$SBFOLDER/vl_reality.txt"
      red "🚀【 vless-reality-vision-IPV4 】节点信息如下：" && sleep 1
      echo -e "${yellow}$vl_link_v4${plain}\n"
      print_qr "$vl_link_v4"
      red "🚀【 vless-reality-vision-IPV6 】节点信息如下：" && sleep 1
      echo -e "${yellow}$vl_link_v6${plain}\n"
      print_qr "$vl_link_v6"
    else
      vl_link="vless://$uuid_vl_re@$server_ip:$port_vl_re?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$vl_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#vl-reality-$hostname-$ip_tag"
      echo "$vl_link" > "$SBFOLDER/vl_reality.txt"
      red "🚀【 vless-reality-vision-$ip_tag 】节点信息如下：" && sleep 2
      echo -e "${yellow}$vl_link${plain}\n"
      print_qr "$vl_link"
    fi
  fi

  if [[ -n "$port_vl_ws_tls" ]]; then
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    if [[ "$server_ip" = "dual" ]]; then
      local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
      local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
      local vl_ws_link_v4="vless://$uuid_vl_ws@$v4_addr:$p_vl_ws?encryption=none&security=tls&sni=$tls_sni&type=ws&path=%2F${uuid_vl_ws}&${vl_tls_params}#vl-ws-tls-$hostname-IPV4"
      local vl_ws_link_v6="vless://$uuid_vl_ws@[$v6_addr]:$p_vl_ws?encryption=none&security=tls&sni=$tls_sni&type=ws&path=%2F${uuid_vl_ws}&${vl_tls_params}#vl-ws-tls-$hostname-IPV6"
      echo -e "$vl_ws_link_v4\n$vl_ws_link_v6" > "$SBFOLDER/vl_ws_tls.txt"
      red "🚀【 vless-ws-tls-IPV4 】节点信息如下：" && sleep 1
      echo -e "${yellow}$vl_ws_link_v4${plain}\n"
      print_qr "$vl_ws_link_v4"
      red "🚀【 vless-ws-tls-IPV6 】节点信息如下：" && sleep 1
      echo -e "${yellow}$vl_ws_link_v6${plain}\n"
      print_qr "$vl_ws_link_v6"
    else
      local vl_ws_link="vless://$uuid_vl_ws@$s_ip_ws:$p_vl_ws?encryption=none&security=tls&sni=$tls_sni&type=ws&path=%2F${uuid_vl_ws}&${vl_tls_params}#vl-ws-tls-$hostname-$ip_tag"
      echo "$vl_ws_link" > "$SBFOLDER/vl_ws_tls.txt"
      red "🚀【 vless-ws-tls-$ip_tag 】节点信息如下：" && sleep 2
      echo -e "${yellow}$vl_ws_link${plain}\n"
      print_qr "$vl_ws_link"
    fi
  fi

  if [[ -n "$port_vl_hu_tls" ]]; then
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    if [[ "$server_ip" = "dual" ]]; then
      local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
      local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
      local vl_hu_link_v4="vless://$uuid_vl_hu@$v4_addr:$p_vl_hu?encryption=none&security=tls&sni=$tls_sni&type=httpupgrade&path=%2F${uuid_vl_hu}&${vl_tls_params}#vl-hu-tls-$hostname-IPV4"
      local vl_hu_link_v6="vless://$uuid_vl_hu@[$v6_addr]:$p_vl_hu?encryption=none&security=tls&sni=$tls_sni&type=httpupgrade&path=%2F${uuid_vl_hu}&${vl_tls_params}#vl-hu-tls-$hostname-IPV6"
      echo -e "$vl_hu_link_v4\n$vl_hu_link_v6" > "$SBFOLDER/vl_hu_tls.txt"
      red "🚀【 vless-hu-tls-IPV4 】节点信息如下：" && sleep 1
      echo -e "${yellow}$vl_hu_link_v4${plain}\n"
      print_qr "$vl_hu_link_v4"
      red "🚀【 vless-hu-tls-IPV6 】节点信息如下：" && sleep 1
      echo -e "${yellow}$vl_hu_link_v6${plain}\n"
      print_qr "$vl_hu_link_v6"
    else
      local vl_hu_link="vless://$uuid_vl_hu@$s_ip_hu:$p_vl_hu?encryption=none&security=tls&sni=$tls_sni&type=httpupgrade&path=%2F${uuid_vl_hu}&${vl_tls_params}#vl-hu-tls-$hostname-$ip_tag"
      echo "$vl_hu_link" > "$SBFOLDER/vl_hu_tls.txt"
      red "🚀【 vless-hu-tls-$ip_tag 】节点信息如下：" && sleep 2
      echo -e "${yellow}$vl_hu_link${plain}\n"
      print_qr "$vl_hu_link"
    fi
  fi
}

resvmess() {
  [[ -z "$port_vm_ws" && -z "$port_vm_ws_tls" && -z "$port_vm_hu_tls" ]] && return 0
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
  
  local caddy_active=false
  if systemctl is-active --quiet caddy 2>/dev/null || rc-service caddy status 2>/dev/null | grep -q "started"; then
    caddy_active=true
  fi

  local p_vm_ws_tls="$port_vm_ws_tls"
  local p_vm_hu_tls="$port_vm_hu_tls"
  local s_ipcl_ws="$server_ipcl"
  local s_ipcl_hu="$server_ipcl"
  
  if $caddy_active; then
    p_vm_ws_tls="443"
    p_vm_hu_tls="443"
    local cert_type=$(cat /var/Sing-Box-DuolaD/cert_type.log 2>/dev/null || echo "self")
    if [[ "$cert_type" == "domain" && -n "$tls_sni" ]]; then
      s_ipcl_ws="$tls_sni"
      s_ipcl_hu="$tls_sni"
    fi
  fi

  local ip_tag="IPV4"
  if [[ "$server_ip" =~ : ]]; then ip_tag="IPV6"; fi

  if [[ -n "$port_vm_ws" ]]; then
    local port_active=false
    if [[ -f "$SBFOLDER/argo.log" && -s "$SBFOLDER/argo.log" ]] && \
       ps -ef | grep -v grep | grep -q "cloudflared.*localhost:$port_vm_ws"; then
      port_active=true
    fi
    
    if $port_active; then
      echo
      white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
      red "🚀【 vmess-ws(tls)+Argo-$ip_tag 】临时节点信息如下 (可选择3-8-3，自定义CDN优选地址)：" && sleep 2
      echo
      echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
      local argo_domain=$(grep -a -o -E '[a-zA-Z0-9.-]+\.trycloudflare\.com' "$SBFOLDER/argo.log" 2>/dev/null | head -n 1)
      local vm_argo_temp_link="vmess://$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argo_domain'","id":"'$uuid_vm_ws'","net":"ws","path":"'$uuid_vm_ws'","port":"443","ps":"'vm-argo-$hostname-$ip_tag'","tls":"tls","sni":"'$argo_domain'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)"
      echo -e "${yellow}$vm_argo_temp_link${plain}"
      echo
      echo "$vm_argo_temp_link" > "$SBFOLDER/vm_ws_argols.txt"
      print_qr "$vm_argo_temp_link"
    fi
    
    local fixed_argo_active=false
    if [[ -f "$SBFOLDER/sbargoym.log" && -s "$SBFOLDER/sbargoym.log" ]] && \
       { systemctl is-active --quiet argo 2>/dev/null || rc-service argo status 2>/dev/null | grep -q "started"; }; then
      fixed_argo_active=true
    fi
    
    if $fixed_argo_active; then
      local argogd=$(cat "$SBFOLDER/sbargoym.log" 2>/dev/null)
      echo
      white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
      red "🚀【 vmess-ws(tls)+Argo-$ip_tag 】固定节点信息如下 (可选择3-8-3，自定义CDN优选地址)：" && sleep 2
      echo
      echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
      local vm_argo_fixed_link="vmess://$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argogd'","id":"'$uuid_vm_ws'","net":"ws","path":"'$uuid_vm_ws'","port":"443","ps":"'vm-argo-$hostname-$ip_tag'","tls":"tls","sni":"'$argogd'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)"
      echo -e "${yellow}$vm_argo_fixed_link${plain}"
      echo
      echo "$vm_argo_fixed_link" > "$SBFOLDER/vm_ws_argogd.txt"
      print_qr "$vm_argo_fixed_link"
    fi
    
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    if [[ -f "$SBFOLDER/cfvmadd_local.txt" ]]; then
      local vm_ws_link="vmess://$(echo '{"add":"'$vmadd_local'","aid":"0","host":"'$tls_sni'","id":"'$uuid_vm_ws'","net":"ws","path":"'$uuid_vm_ws'","port":"'$port_vm_ws'","ps":"'vm-ws-$hostname-$ip_tag'","tls":"","type":"none","v":"2"}' | base64 -w 0)"
      echo "$vm_ws_link" > "$SBFOLDER/vm_ws.txt"
      red "🚀【 vmess-ws-$ip_tag 】节点信息如下 (已启用自定义优选地址)：" && sleep 2
      echo -e "${yellow}$vm_ws_link${plain}\n"
      print_qr "$vm_ws_link"
    elif [[ "$server_ip" = "dual" ]]; then
      local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
      local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
      local vm_ws_link_v4="vmess://$(echo '{"add":"'$v4_addr'","aid":"0","host":"'$tls_sni'","id":"'$uuid_vm_ws'","net":"ws","path":"'$uuid_vm_ws'","port":"'$port_vm_ws'","ps":"'vm-ws-$hostname-IPV4'","tls":"","type":"none","v":"2"}' | base64 -w 0)"
      local vm_ws_link_v6="vmess://$(echo '{"add":"['$v6_addr']","aid":"0","host":"'$tls_sni'","id":"'$uuid_vm_ws'","net":"ws","path":"'$uuid_vm_ws'","port":"'$port_vm_ws'","ps":"'vm-ws-$hostname-IPV6'","tls":"","type":"none","v":"2"}' | base64 -w 0)"
      echo -e "$vm_ws_link_v4\n$vm_ws_link_v6" > "$SBFOLDER/vm_ws.txt"
      red "🚀【 vmess-ws-IPV4 】节点信息如下 (建议选择3-8-1，设置为CDN优选节点)：" && sleep 1
      echo -e "${yellow}$vm_ws_link_v4${plain}\n"
      print_qr "$vm_ws_link_v4"
      red "🚀【 vmess-ws-IPV6 】节点信息如下 (建议选择3-8-1，设置为CDN优选节点)：" && sleep 1
      echo -e "${yellow}$vm_ws_link_v6${plain}\n"
      print_qr "$vm_ws_link_v6"
    else
      local vm_ws_link="vmess://$(echo '{"add":"'$server_ipcl'","aid":"0","host":"'$tls_sni'","id":"'$uuid_vm_ws'","net":"ws","path":"'$uuid_vm_ws'","port":"'$port_vm_ws'","ps":"'vm-ws-$hostname-$ip_tag'","tls":"","type":"none","v":"2"}' | base64 -w 0)"
      echo "$vm_ws_link" > "$SBFOLDER/vm_ws.txt"
      red "🚀【 vmess-ws-$ip_tag 】节点信息如下 (建议选择3-8-1，设置为CDN优选节点)：" && sleep 2
      echo -e "${yellow}$vm_ws_link${plain}\n"
      print_qr "$vm_ws_link"
    fi
  fi

  if [[ -n "$port_vm_ws_tls" ]]; then
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    if [[ -f "$SBFOLDER/cfvmadd_local.txt" ]]; then
      red "🚀【 vmess-ws-tls-$ip_tag 】节点信息如下 (已启用自定义优选地址)：" && sleep 2
      local vm_ws_tls_link="vmess://$(echo '{"add":"'$vmadd_local'","aid":"0","host":"'$tls_sni'","id":"'$uuid_vm_ws_tls'","net":"ws","path":"'$uuid_vm_ws_tls'","port":"'$p_vm_ws_tls'","ps":"'vm-ws-tls-$hostname-$ip_tag'","tls":"tls","sni":"'$tls_sni'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)"
      echo -e "${yellow}$vm_ws_tls_link${plain}"
      print_qr "$vm_ws_tls_link"
      echo "$vm_ws_tls_link" > "$SBFOLDER/vm_ws_tls.txt"
    elif [[ "$server_ip" = "dual" ]]; then
      local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
      local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
      local vm_ws_tls_link_v4="vmess://$(echo '{"add":"'$v4_addr'","aid":"0","host":"'$tls_sni'","id":"'$uuid_vm_ws_tls'","net":"ws","path":"'$uuid_vm_ws_tls'","port":"'$p_vm_ws_tls'","ps":"'vm-ws-tls-$hostname-IPV4'","tls":"tls","sni":"'$tls_sni'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)"
      local vm_ws_tls_link_v6="vmess://$(echo '{"add":"['$v6_addr']","aid":"0","host":"'$tls_sni'","id":"'$uuid_vm_ws_tls'","net":"ws","path":"'$uuid_vm_ws_tls'","port":"'$p_vm_ws_tls'","ps":"'vm-ws-tls-$hostname-IPV6'","tls":"tls","sni":"'$tls_sni'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)"
      echo -e "$vm_ws_tls_link_v4\n$vm_ws_tls_link_v6" > "$SBFOLDER/vm_ws_tls.txt"
      red "🚀【 vmess-ws-tls-IPV4 】节点信息如下 (建议选择3-8-1，设置为CDN优选节点)：" && sleep 1
      echo -e "${yellow}$vm_ws_tls_link_v4${plain}\n"
      print_qr "$vm_ws_tls_link_v4"
      red "🚀【 vmess-ws-tls-IPV6 】节点信息如下 (建议选择3-8-1，设置为CDN优选节点)：" && sleep 1
      echo -e "${yellow}$vm_ws_tls_link_v6${plain}\n"
      print_qr "$vm_ws_tls_link_v6"
    else
      red "🚀【 vmess-ws-tls-$ip_tag 】节点信息如下 (建议选择3-8-1，设置为CDN优选节点)：" && sleep 2
      local vm_ws_tls_link="vmess://$(echo '{"add":"'$s_ipcl_ws'","aid":"0","host":"'$tls_sni'","id":"'$uuid_vm_ws_tls'","net":"ws","path":"'$uuid_vm_ws_tls'","port":"'$p_vm_ws_tls'","ps":"'vm-ws-tls-$hostname-$ip_tag'","tls":"tls","sni":"'$tls_sni'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)"
      echo -e "${yellow}$vm_ws_tls_link${plain}"
      print_qr "$vm_ws_tls_link"
      echo "$vm_ws_tls_link" > "$SBFOLDER/vm_ws_tls.txt"
    fi
  fi

  if [[ -n "$port_vm_hu_tls" ]]; then
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    if [[ "$server_ip" = "dual" ]]; then
      local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
      local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
      local vm_hu_tls_link_v4="vmess://$(echo '{"add":"'$v4_addr'","aid":"0","host":"'$tls_sni'","id":"'$uuid_vm_hu_tls'","net":"httpupgrade","path":"'$uuid_vm_hu_tls'","port":"'$p_vm_hu_tls'","ps":"'vm-hu-tls-$hostname-IPV4'","tls":"tls","sni":"'$tls_sni'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)"
      local vm_hu_tls_link_v6="vmess://$(echo '{"add":"['$v6_addr']","aid":"0","host":"'$tls_sni'","id":"'$uuid_vm_hu_tls'","net":"httpupgrade","path":"'$uuid_vm_hu_tls'","port":"'$p_vm_hu_tls'","ps":"'vm-hu-tls-$hostname-IPV6'","tls":"tls","sni":"'$tls_sni'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)"
      echo -e "$vm_hu_tls_link_v4\n$vm_hu_tls_link_v6" > "$SBFOLDER/vm_hu_tls.txt"
      red "🚀【 vmess-hu-tls-IPV4 】节点信息如下 (建议选择3-8-1，设置为CDN优选节点)：" && sleep 1
      echo -e "${yellow}$vm_hu_tls_link_v4${plain}\n"
      print_qr "$vm_hu_tls_link_v4"
      red "🚀【 vmess-hu-tls-IPV6 】节点信息如下 (建议选择3-8-1，设置为CDN优选节点)：" && sleep 1
      echo -e "${yellow}$vm_hu_tls_link_v6${plain}\n"
      print_qr "$vm_hu_tls_link_v6"
    else
      local vm_hu_tls_link="vmess://$(echo '{"add":"'$s_ipcl_hu'","aid":"0","host":"'$tls_sni'","id":"'$uuid_vm_hu_tls'","net":"httpupgrade","path":"'$uuid_vm_hu_tls'","port":"'$p_vm_hu_tls'","ps":"'vm-hu-tls-$hostname-$ip_tag'","tls":"tls","sni":"'$tls_sni'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)"
      echo "$vm_hu_tls_link" > "$SBFOLDER/vm_hu_tls.txt"
      red "🚀【 vmess-hu-tls-$ip_tag 】节点信息如下 (建议选择3-8-1，设置为CDN优选节点)：" && sleep 2
      echo -e "${yellow}$vm_hu_tls_link${plain}\n"
      print_qr "$vm_hu_tls_link"
    fi
  fi
}

reshy2() {
  [[ -z "$port_hy2" ]] && return 0
  echo
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  local hy2_params="insecure=0&alpn=h3"
  if [[ "$is_self_signed" = "true" ]]; then
    hy2_params="insecure=0&sni=$(get_self_domain)&pinnedPeerCertSha256=$SHA256&alpn=h3"
  else
    hy2_params="sni=$hy2_name&insecure=0&alpn=h3"
  fi
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
  local ip_tag="IPV4"
  if [[ "$server_ip" =~ : ]]; then ip_tag="IPV6"; fi

  if [[ "$server_ip" = "dual" ]]; then
    local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
    local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
    hy2_link_v4="hysteria2://$uuid_hy2@$v4_addr:$port_hy2?$hy2_params$hyps#hy2-$hostname-IPV4"
    hy2_link_v6="hysteria2://$uuid_hy2@[$v6_addr]:$port_hy2?$hy2_params$hyps#hy2-$hostname-IPV6"
    echo -e "$hy2_link_v4\n$hy2_link_v6" > "$SBFOLDER/hy2.txt"
    red "🚀【 Hysteria-2-IPV4 】节点信息如下：" && sleep 1
    echo -e "${yellow}$hy2_link_v4${plain}\n"
    print_qr "$hy2_link_v4"
    red "🚀【 Hysteria-2-IPV6 】节点信息如下：" && sleep 1
    echo -e "${yellow}$hy2_link_v6${plain}\n"
    print_qr "$hy2_link_v6"
  else
    hy2_link="hysteria2://$uuid_hy2@$sb_hy2_ip:$port_hy2?$hy2_params$hyps#hy2-$hostname-$ip_tag"
    echo "$hy2_link" > "$SBFOLDER/hy2.txt"
    red "🚀【 Hysteria-2-$ip_tag 】节点信息如下：" && sleep 2
    echo -e "${yellow}$hy2_link${plain}\n"
    print_qr "$hy2_link"
  fi
}

restu5() {
  [[ -z "$port_tu" ]] && return 0
  echo
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  local tu5_params="insecure=0&allowInsecure=0&allow_insecure=0&alpn=h3"
  if [[ "$is_self_signed" = "true" ]]; then
    tu5_params="sni=$(get_self_domain)&insecure=0&allowInsecure=0&allow_insecure=0&pinnedPeerCertSha256=$SHA256&alpn=h3"
  else
    tu5_params="sni=$tu5_name&insecure=0&allowInsecure=0&allow_insecure=0&alpn=h3"
  fi
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
  local ip_tag="IPV4"
  if [[ "$server_ip" =~ : ]]; then ip_tag="IPV6"; fi

  if [[ "$server_ip" = "dual" ]]; then
    local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
    local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
    tu_link_v4="tuic://$uuid_tu:$uuid_tu@$v4_addr:$port_tu?$tu5_params#tuic5-$hostname-IPV4"
    tu_link_v6="tuic://$uuid_tu:$uuid_tu@[$v6_addr]:$port_tu?$tu5_params#tuic5-$hostname-IPV6"
    echo -e "$tu_link_v4\n$tu_link_v6" > "$SBFOLDER/tuic5.txt"
    red "🚀【 Tuic-v5-IPV4 】节点信息如下：" && sleep 1
    echo -e "${yellow}$tu_link_v4${plain}\n"
    print_qr "$tu_link_v4"
    red "🚀【 Tuic-v5-IPV6 】节点信息如下：" && sleep 1
    echo -e "${yellow}$tu_link_v6${plain}\n"
    print_qr "$tu_link_v6"
  else
    tu_link="tuic://$uuid_tu:$uuid_tu@$sb_tu5_ip:$port_tu?$tu5_params#tuic5-$hostname-$ip_tag"
    echo "$tu_link" > "$SBFOLDER/tuic5.txt"
    red "🚀【 Tuic-v5-$ip_tag 】节点信息如下：" && sleep 2
    echo -e "${yellow}$tu_link${plain}\n"
    print_qr "$tu_link"
  fi
}

resan() {
  [[ -z "$port_an" ]] && return 0
  echo
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  local an_params="sni=$an_name&allowInsecure=0&insecure=0"
  if [[ "$is_self_signed" = "true" ]]; then
    an_params="sni=$(get_self_domain)&allowInsecure=0&insecure=0&pinnedPeerCertSha256=$SHA256"
  fi
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
  local ip_tag="IPV4"
  if [[ "$server_ip" =~ : ]]; then ip_tag="IPV6"; fi

  if [[ "$server_ip" = "dual" ]]; then
    local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
    local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
    an_link_v4="anytls://$uuid_an@$v4_addr:$port_an?$an_params#anytls-$hostname-IPV4"
    an_link_v6="anytls://$uuid_an@[${v6_addr}]:$port_an?$an_params#anytls-$hostname-IPV6"
    echo -e "$an_link_v4\n$an_link_v6" > "$SBFOLDER/an.txt"
    red "🚀【 Anytls-IPV4 】节点信息如下：" && sleep 1
    echo -e "${yellow}$an_link_v4${plain}\n"
    print_qr "$an_link_v4"
    red "🚀【 Anytls-IPV6 】节点信息如下：" && sleep 1
    echo -e "${yellow}$an_link_v6${plain}\n"
    print_qr "$an_link_v6"
  else
    an_link="anytls://$uuid_an@$sb_an_ip:$port_an?$an_params#anytls-$hostname-$ip_tag"
    echo "$an_link" > "$SBFOLDER/an.txt"
    red "🚀【 Anytls-$ip_tag 】节点信息如下：" && sleep 2
    echo -e "${yellow}$an_link${plain}\n"
    print_qr "$an_link"
  fi
}

restrojan() {
  [[ -z "$port_tr_tls" && -z "$port_tr_ws_tls" && -z "$port_tr_hu_tls" ]] && return 0
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
  local tr_tls_params="insecure=0&allowInsecure=0"
  if [[ "$is_self_signed" = "true" ]]; then
    tr_tls_params+="&pinnedPeerCertSha256=$SHA256"
  fi
  
  local caddy_active=false
  if systemctl is-active --quiet caddy 2>/dev/null || rc-service caddy status 2>/dev/null | grep -q "started"; then
    caddy_active=true
  fi

  local p_tr_ws_tls="$port_tr_ws_tls"
  local p_tr_hu_tls="$port_tr_hu_tls"
  local s_ip_ws="$server_ip"
  local s_ip_hu="$server_ip"
  
  if $caddy_active; then
    p_tr_ws_tls="443"
    p_tr_hu_tls="443"
    local cert_type=$(cat /var/Sing-Box-DuolaD/cert_type.log 2>/dev/null || echo "self")
    if [[ "$cert_type" == "domain" && -n "$tls_sni" ]]; then
      s_ip_ws="$tls_sni"
      s_ip_hu="$tls_sni"
    fi
  fi

  local ip_tag="IPV4"
  if [[ "$server_ip" =~ : ]]; then ip_tag="IPV6"; fi

  if [[ -n "$port_tr_tls" ]]; then
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    if [[ "$server_ip" = "dual" ]]; then
      local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
      local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
      local tr_link_v4="trojan://$uuid_tr_tls@$v4_addr:$port_tr_tls?security=tls&sni=$tls_sni&${tr_tls_params}#tr-tls-$hostname-IPV4"
      local tr_link_v6="trojan://$uuid_tr_tls@[$v6_addr]:$port_tr_tls?security=tls&sni=$tls_sni&${tr_tls_params}#tr-tls-$hostname-IPV6"
      echo -e "$tr_link_v4\n$tr_link_v6" > "$SBFOLDER/tr_tls.txt"
      red "🚀【 Trojan-TLS-IPV4 】节点信息如下：" && sleep 1
      echo -e "${yellow}$tr_link_v4${plain}\n"
      print_qr "$tr_link_v4"
      red "🚀【 Trojan-TLS-IPV6 】节点信息如下：" && sleep 1
      echo -e "${yellow}$tr_link_v6${plain}\n"
      print_qr "$tr_link_v6"
    else
      local tr_link="trojan://$uuid_tr_tls@$server_ip:$port_tr_tls?security=tls&sni=$tls_sni&${tr_tls_params}#tr-tls-$hostname-$ip_tag"
      echo "$tr_link" > "$SBFOLDER/tr_tls.txt"
      red "🚀【 Trojan-TLS-$ip_tag 】节点信息如下：" && sleep 2
      echo -e "${yellow}$tr_link${plain}\n"
      print_qr "$tr_link"
    fi
  fi

  if [[ -n "$port_tr_ws_tls" ]]; then
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    if [[ "$server_ip" = "dual" ]]; then
      local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
      local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
      local tr_ws_link_v4="trojan://$uuid_tr_ws_tls@$v4_addr:$p_tr_ws_tls?security=tls&sni=$tls_sni&type=ws&path=%2F${uuid_tr_ws_tls}&${tr_tls_params}#tr-ws-tls-$hostname-IPV4"
      local tr_ws_link_v6="trojan://$uuid_tr_ws_tls@[$v6_addr]:$p_tr_ws_tls?security=tls&sni=$tls_sni&type=ws&path=%2F${uuid_tr_ws_tls}&${tr_tls_params}#tr-ws-tls-$hostname-IPV6"
      echo -e "$tr_ws_link_v4\n$tr_ws_link_v6" > "$SBFOLDER/tr_ws_tls.txt"
      red "🚀【 Trojan-WS-TLS-IPV4 】节点信息如下：" && sleep 1
      echo -e "${yellow}$tr_ws_link_v4${plain}\n"
      print_qr "$tr_ws_link_v4"
      red "🚀【 Trojan-WS-TLS-IPV6 】节点信息如下：" && sleep 1
      echo -e "${yellow}$tr_ws_link_v6${plain}\n"
      print_qr "$tr_ws_link_v6"
    else
      local tr_ws_link="trojan://$uuid_tr_ws_tls@$s_ip_ws:$p_tr_ws_tls?security=tls&sni=$tls_sni&type=ws&path=%2F${uuid_tr_ws_tls}&${tr_tls_params}#tr-ws-tls-$hostname-$ip_tag"
      echo "$tr_ws_link" > "$SBFOLDER/tr_ws_tls.txt"
      red "🚀【 Trojan-WS-TLS-$ip_tag 】节点信息如下：" && sleep 2
      echo -e "${yellow}$tr_ws_link${plain}\n"
      print_qr "$tr_ws_link"
    fi
  fi

  if [[ -n "$port_tr_hu_tls" ]]; then
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    if [[ "$server_ip" = "dual" ]]; then
      local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
      local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
      local tr_hu_link_v4="trojan://$uuid_tr_hu_tls@$v4_addr:$p_tr_hu_tls?security=tls&sni=$tls_sni&type=httpupgrade&path=%2F${uuid_tr_hu_tls}&${tr_tls_params}#tr-hu-tls-$hostname-IPV4"
      local tr_hu_link_v6="trojan://$uuid_tr_hu_tls@[$v6_addr]:$p_tr_hu_tls?security=tls&sni=$tls_sni&type=httpupgrade&path=%2F${uuid_tr_hu_tls}&${tr_tls_params}#tr-hu-tls-$hostname-IPV6"
      echo -e "$tr_hu_link_v4\n$tr_hu_link_v6" > "$SBFOLDER/tr_hu_tls.txt"
      red "🚀【 Trojan-HTTPUpgrade-TLS-IPV4 】节点信息如下：" && sleep 1
      echo -e "${yellow}$tr_hu_link_v4${plain}\n"
      print_qr "$tr_hu_link_v4"
      red "🚀【 Trojan-HTTPUpgrade-TLS-IPV6 】节点信息如下：" && sleep 1
      echo -e "${yellow}$tr_hu_link_v6${plain}\n"
      print_qr "$tr_hu_link_v6"
    else
      local tr_hu_link="trojan://$uuid_tr_hu_tls@$s_ip_hu:$p_tr_hu_tls?security=tls&sni=$tls_sni&type=httpupgrade&path=%2F${uuid_tr_hu_tls}&${tr_tls_params}#tr-hu-tls-$hostname-$ip_tag"
      echo "$tr_hu_link" > "$SBFOLDER/tr_hu_tls.txt"
      red "🚀【 Trojan-HTTPUpgrade-TLS-$ip_tag 】节点信息如下：" && sleep 2
      echo -e "${yellow}$tr_hu_link${plain}\n"
      print_qr "$tr_hu_link"
    fi
  fi
}

resshadowsocks() {
  [[ -z "$port_ss" ]] && return 0
  echo
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
  local b64_cred=$(echo -n "${ss_method:-2022-blake3-aes-128-gcm}:$ss_password" | base64 -w 0)
  local ip_tag="IPV4"
  if [[ "$server_ip" =~ : ]]; then ip_tag="IPV6"; fi
  
  if [[ "$server_ip" = "dual" ]]; then
    local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
    local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
    local ss_link_v4="ss://$b64_cred@$v4_addr:$port_ss#ss-$hostname-IPV4"
    local ss_link_v6="ss://$b64_cred@[$v6_addr]:$port_ss#ss-$hostname-IPV6"
    echo -e "$ss_link_v4\n$ss_link_v6" > "$SBFOLDER/ss.txt"
    red "🚀【 Shadowsocks-IPV4 】节点信息如下：" && sleep 1
    echo -e "${yellow}$ss_link_v4${plain}\n"
    print_qr "$ss_link_v4"
    red "🚀【 Shadowsocks-IPV6 】节点信息如下：" && sleep 1
    echo -e "${yellow}$ss_link_v6${plain}\n"
    print_qr "$ss_link_v6"
  else
    local ss_link="ss://$b64_cred@$server_ip:$port_ss#ss-$hostname-$ip_tag"
    echo "$ss_link" > "$SBFOLDER/ss.txt"
    red "🚀【 Shadowsocks-$ip_tag 】节点信息如下：" && sleep 2
    echo -e "${yellow}$ss_link${plain}\n"
    print_qr "$ss_link"
  fi
}

resvmess_tcp() {
  [[ -z "$port_vm_tcp" ]] && return 0
  echo
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
  if [[ "$server_ip" = "dual" ]]; then
    local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
    local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
    local vm_tcp_link_v4="vmess://$(echo '{"add":"'$v4_addr'","aid":"0","host":"","id":"'$uuid_vm_tcp'","net":"tcp","path":"","port":"'$port_vm_tcp'","ps":"vm-tcp-'$hostname'-IPV4","tls":"","sni":"","type":"none","v":"2"}' | base64 -w 0)"
    local vm_tcp_link_v6="vmess://$(echo '{"add":"['$v6_addr']","aid":"0","host":"","id":"'$uuid_vm_tcp'","net":"tcp","path":"","port":"'$port_vm_tcp'","ps":"vm-tcp-'$hostname'-IPV6","tls":"","sni":"","type":"none","v":"2"}' | base64 -w 0)"
    echo -e "$vm_tcp_link_v4\n$vm_tcp_link_v6" > "$SBFOLDER/vm_tcp.txt"
    red "🚀【 VMess-TCP-IPV4 】节点信息如下：" && sleep 1
    echo -e "${yellow}$vm_tcp_link_v4${plain}\n"
    print_qr "$vm_tcp_link_v4"
    red "🚀【 VMess-TCP-IPV6 】节点信息如下：" && sleep 1
    echo -e "${yellow}$vm_tcp_link_v6${plain}\n"
    print_qr "$vm_tcp_link_v6"
  else
    local ip_tag="IPV4"
    if [[ "$server_ip" =~ : ]]; then ip_tag="IPV6"; fi
    local vm_tcp_link="vmess://$(echo '{"add":"'$server_ip'","aid":"0","host":"","id":"'$uuid_vm_tcp'","net":"tcp","path":"","port":"'$port_vm_tcp'","ps":"vm-tcp-'$hostname'-'$ip_tag'","tls":"","sni":"","type":"none","v":"2"}' | base64 -w 0)"
    echo "$vm_tcp_link" > "$SBFOLDER/vm_tcp.txt"
    red "🚀【 VMess-TCP-$ip_tag 】节点信息如下：" && sleep 2
    echo -e "${yellow}$vm_tcp_link${plain}\n"
    print_qr "$vm_tcp_link"
  fi
}

resvmess_http() {
  [[ -z "$port_vm_http" ]] && return 0
  echo
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
  if [[ "$server_ip" = "dual" ]]; then
    local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
    local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
    local vm_http_link_v4="vmess://$(echo '{"add":"'$v4_addr'","aid":"0","host":"","id":"'$uuid_vm_http'","net":"tcp","path":"","port":"'$port_vm_http'","ps":"vm-http-'$hostname'-IPV4","tls":"","sni":"","type":"http","v":"2"}' | base64 -w 0)"
    local vm_http_link_v6="vmess://$(echo '{"add":"['$v6_addr']","aid":"0","host":"","id":"'$uuid_vm_http'","net":"tcp","path":"","port":"'$port_vm_http'","ps":"vm-http-'$hostname'-IPV6","tls":"","sni":"","type":"http","v":"2"}' | base64 -w 0)"
    echo -e "$vm_http_link_v4\n$vm_http_link_v6" > "$SBFOLDER/vm_http.txt"
    red "🚀【 VMess-HTTP-IPV4 】节点信息如下：" && sleep 1
    echo -e "${yellow}$vm_http_link_v4${plain}\n"
    print_qr "$vm_http_link_v4"
    red "🚀【 VMess-HTTP-IPV6 】节点信息如下：" && sleep 1
    echo -e "${yellow}$vm_http_link_v6${plain}\n"
    print_qr "$vm_http_link_v6"
  else
    local ip_tag="IPV4"
    if [[ "$server_ip" =~ : ]]; then ip_tag="IPV6"; fi
    local vm_http_link="vmess://$(echo '{"add":"'$server_ip'","aid":"0","host":"","id":"'$uuid_vm_http'","net":"tcp","path":"","port":"'$port_vm_http'","ps":"vm-http-'$hostname'-'$ip_tag'","tls":"","sni":"","type":"http","v":"2"}' | base64 -w 0)"
    echo "$vm_http_link" > "$SBFOLDER/vm_http.txt"
    red "🚀【 VMess-HTTP-$ip_tag 】节点信息如下：" && sleep 2
    echo -e "${yellow}$vm_http_link${plain}\n"
    print_qr "$vm_http_link"
  fi
}

resvmess_quic() {
  [[ -z "$port_vm_quic" ]] && return 0
  echo
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
  if [[ "$server_ip" = "dual" ]]; then
    local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
    local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
    local vm_quic_link_v4="vmess://$(echo '{"add":"'$v4_addr'","aid":"0","host":"","id":"'$uuid_vm_quic'","net":"quic","path":"","port":"'$port_vm_quic'","ps":"vm-quic-'$hostname'-IPV4","tls":"tls","sni":"'$tls_sni'","alpn":"h3","type":"none","v":"2"}' | base64 -w 0)"
    local vm_quic_link_v6="vmess://$(echo '{"add":"['$v6_addr']","aid":"0","host":"","id":"'$uuid_vm_quic'","net":"quic","path":"","port":"'$port_vm_quic'","ps":"vm-quic-'$hostname'-IPV6","tls":"tls","sni":"'$tls_sni'","alpn":"h3","type":"none","v":"2"}' | base64 -w 0)"
    echo -e "$vm_quic_link_v4\n$vm_quic_link_v6" > "$SBFOLDER/vm_quic.txt"
    red "🚀【 VMess-QUIC-IPV4 】节点信息如下：" && sleep 1
    echo -e "${yellow}$vm_quic_link_v4${plain}\n"
    print_qr "$vm_quic_link_v4"
    red "🚀【 VMess-QUIC-IPV6 】节点信息如下：" && sleep 1
    echo -e "${yellow}$vm_quic_link_v6${plain}\n"
    print_qr "$vm_quic_link_v6"
  else
    local ip_tag="IPV4"
    if [[ "$server_ip" =~ : ]]; then ip_tag="IPV6"; fi
    local vm_quic_link="vmess://$(echo '{"add":"'$server_ip'","aid":"0","host":"","id":"'$uuid_vm_quic'","net":"quic","path":"","port":"'$port_vm_quic'","ps":"vm-quic-'$hostname'-'$ip_tag'","tls":"tls","sni":"'$tls_sni'","alpn":"h3","type":"none","v":"2"}' | base64 -w 0)"
    echo "$vm_quic_link" > "$SBFOLDER/vm_quic.txt"
    red "🚀【 VMess-QUIC-$ip_tag 】节点信息如下：" && sleep 2
    echo -e "${yellow}$vm_quic_link${plain}\n"
    print_qr "$vm_quic_link"
  fi
}

resvmess_h2_tls() {
  [[ -z "$port_vm_h2_tls" ]] && return 0
  echo
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
  
  local caddy_active=false
  if systemctl is-active --quiet caddy 2>/dev/null || rc-service caddy status 2>/dev/null | grep -q "started"; then
    caddy_active=true
  fi

  local p_vm_h2="$port_vm_h2_tls"
  local s_ip_h2="$server_ip"
  local h2_sni="$ym_domain"
  if $caddy_active; then
    p_vm_h2="443"
    local cert_type=$(cat /var/Sing-Box-DuolaD/cert_type.log 2>/dev/null || echo "self")
    if [[ "$cert_type" == "domain" && -n "$ym_domain" ]]; then
      s_ip_h2="$ym_domain"
    elif [[ "$cert_type" == "ip" ]]; then
      h2_sni="$server_ip"
    fi
  fi

  if [[ "$server_ip" = "dual" ]]; then
    local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
    local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
    local s_v4_h2="$v4_addr"
    local s_v6_h2="[$v6_addr]"
    if $caddy_active && [[ "$cert_type" == "domain" && -n "$ym_domain" ]]; then
      s_v4_h2="$ym_domain"
      s_v6_h2="$ym_domain"
    fi
    local vm_h2_link_v4="vmess://$(echo '{"add":"'$s_v4_h2'","aid":"0","host":"'$h2_sni'","id":"'$uuid_vm_h2_tls'","net":"h2","path":"'$uuid_vm_h2_tls'","port":"'$p_vm_h2'","ps":"vm-h2-tls-'$hostname'-IPV4","tls":"tls","sni":"'$h2_sni'","type":"none","v":"2"}' | base64 -w 0)"
    local vm_h2_link_v6="vmess://$(echo '{"add":"'$s_v6_h2'","aid":"0","host":"'$h2_sni'","id":"'$uuid_vm_h2_tls'","net":"h2","path":"'$uuid_vm_h2_tls'","port":"'$p_vm_h2'","ps":"vm-h2-tls-'$hostname'-IPV6","tls":"tls","sni":"'$h2_sni'","type":"none","v":"2"}' | base64 -w 0)"
    echo -e "$vm_h2_link_v4\n$vm_h2_link_v6" > "$SBFOLDER/vm_h2_tls.txt"
    red "🚀【 VMess-H2-TLS-IPV4 】节点信息如下：" && sleep 1
    echo -e "${yellow}$vm_h2_link_v4${plain}\n"
    print_qr "$vm_h2_link_v4"
    red "🚀【 VMess-H2-TLS-IPV6 】节点信息如下：" && sleep 1
    echo -e "${yellow}$vm_h2_link_v6${plain}\n"
    print_qr "$vm_h2_link_v6"
  else
    local ip_tag="IPV4"
    if [[ "$server_ip" =~ : ]]; then ip_tag="IPV6"; fi
    local vm_h2_link="vmess://$(echo '{"add":"'$s_ip_h2'","aid":"0","host":"'$h2_sni'","id":"'$uuid_vm_h2_tls'","net":"h2","path":"'$uuid_vm_h2_tls'","port":"'$p_vm_h2'","ps":"vm-h2-tls-'$hostname'-'$ip_tag'","tls":"tls","sni":"'$h2_sni'","type":"none","v":"2"}' | base64 -w 0)"
    echo "$vm_h2_link" > "$SBFOLDER/vm_h2_tls.txt"
    red "🚀【 VMess-H2-TLS-$ip_tag 】节点信息如下：" && sleep 2
    echo -e "${yellow}$vm_h2_link${plain}\n"
    print_qr "$vm_h2_link"
  fi
}

resvless_h2_tls() {
  [[ -z "$port_vl_h2_tls" ]] && return 0
  echo
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
  local vl_tls_params="insecure=0&allowInsecure=0"
  if [[ "$is_self_signed" = "true" ]]; then
    vl_tls_params+="&pinnedPeerCertSha256=$SHA256"
  fi

  local caddy_active=false
  if systemctl is-active --quiet caddy 2>/dev/null || rc-service caddy status 2>/dev/null | grep -q "started"; then
    caddy_active=true
  fi

  local p_vl_h2="$port_vl_h2_tls"
  local s_ip_h2="$server_ip"
  local h2_sni="$ym_domain"
  if $caddy_active; then
    p_vl_h2="443"
    local cert_type=$(cat /var/Sing-Box-DuolaD/cert_type.log 2>/dev/null || echo "self")
    if [[ "$cert_type" == "domain" && -n "$ym_domain" ]]; then
      s_ip_h2="$ym_domain"
    elif [[ "$cert_type" == "ip" ]]; then
      h2_sni="$server_ip"
    fi
  fi

  if [[ "$server_ip" = "dual" ]]; then
    local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
    local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
    local s_v4_h2="$v4_addr"
    local s_v6_h2="[$v6_addr]"
    if $caddy_active && [[ "$cert_type" == "domain" && -n "$ym_domain" ]]; then
      s_v4_h2="$ym_domain"
      s_v6_h2="$ym_domain"
    fi
    local vl_h2_link_v4="vless://$uuid_vl_h2@$s_v4_h2:$p_vl_h2?encryption=none&security=tls&sni=$h2_sni&type=h2&host=$h2_sni&path=%2F${uuid_vl_h2}&${vl_tls_params}#vl-h2-tls-$hostname-IPV4"
    local vl_h2_link_v6="vless://$uuid_vl_h2@$s_v6_h2:$p_vl_h2?encryption=none&security=tls&sni=$h2_sni&type=h2&host=$h2_sni&path=%2F${uuid_vl_h2}&${vl_tls_params}#vl-h2-tls-$hostname-IPV6"
    echo -e "$vl_h2_link_v4\n$vl_h2_link_v6" > "$SBFOLDER/vl_h2_tls.txt"
    red "🚀【 VLESS-H2-TLS-IPV4 】节点信息如下：" && sleep 1
    echo -e "${yellow}$vl_h2_link_v4${plain}\n"
    print_qr "$vl_h2_link_v4"
    red "🚀【 VLESS-H2-TLS-IPV6 】节点信息如下：" && sleep 1
    echo -e "${yellow}$vl_h2_link_v6${plain}\n"
    print_qr "$vl_h2_link_v6"
  else
    local ip_tag="IPV4"
    if [[ "$server_ip" =~ : ]]; then ip_tag="IPV6"; fi
    local vl_h2_link="vless://$uuid_vl_h2@$s_ip_h2:$p_vl_h2?encryption=none&security=tls&sni=$h2_sni&type=h2&host=$h2_sni&path=%2F${uuid_vl_h2}&${vl_tls_params}#vl-h2-tls-$hostname-$ip_tag"
    echo "$vl_h2_link" > "$SBFOLDER/vl_h2_tls.txt"
    red "🚀【 VLESS-H2-TLS-$ip_tag 】节点信息如下：" && sleep 2
    echo -e "${yellow}$vl_h2_link${plain}\n"
    print_qr "$vl_h2_link"
  fi
}

restrojan_h2_tls() {
  [[ -z "$port_tr_h2_tls" ]] && return 0
  echo
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)

  local caddy_active=false
  if systemctl is-active --quiet caddy 2>/dev/null || rc-service caddy status 2>/dev/null | grep -q "started"; then
    caddy_active=true
  fi

  local p_tr_h2="$port_tr_h2_tls"
  local s_ip_h2="$server_ip"
  local h2_sni="$ym_domain"
  if $caddy_active; then
    p_tr_h2="443"
    local cert_type=$(cat /var/Sing-Box-DuolaD/cert_type.log 2>/dev/null || echo "self")
    if [[ "$cert_type" == "domain" && -n "$ym_domain" ]]; then
      s_ip_h2="$ym_domain"
    elif [[ "$cert_type" == "ip" ]]; then
      h2_sni="$server_ip"
    fi
  fi

  if [[ "$server_ip" = "dual" ]]; then
    local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
    local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
    local s_v4_h2="$v4_addr"
    local s_v6_h2="[$v6_addr]"
    if $caddy_active && [[ "$cert_type" == "domain" && -n "$ym_domain" ]]; then
      s_v4_h2="$ym_domain"
      s_v6_h2="$ym_domain"
    fi
    local tr_h2_link_v4="trojan://$uuid_tr_h2_tls@$s_v4_h2:$p_tr_h2?security=tls&sni=$h2_sni&type=h2&host=$h2_sni&path=%2F${uuid_tr_h2_tls}#tr-h2-tls-$hostname-IPV4"
    local tr_h2_link_v6="trojan://$uuid_tr_h2_tls@$s_v6_h2:$p_tr_h2?security=tls&sni=$h2_sni&type=h2&host=$h2_sni&path=%2F${uuid_tr_h2_tls}#tr-h2-tls-$hostname-IPV6"
    echo -e "$tr_h2_link_v4\n$tr_h2_link_v6" > "$SBFOLDER/tr_h2_tls.txt"
    red "🚀【 Trojan-H2-TLS-IPV4 】节点信息如下：" && sleep 1
    echo -e "${yellow}$tr_h2_link_v4${plain}\n"
    print_qr "$tr_h2_link_v4"
    red "🚀【 Trojan-H2-TLS-IPV6 】节点信息如下：" && sleep 1
    echo -e "${yellow}$tr_h2_link_v6${plain}\n"
    print_qr "$tr_h2_link_v6"
  else
    local ip_tag="IPV4"
    if [[ "$server_ip" =~ : ]]; then ip_tag="IPV6"; fi
    local tr_h2_link="trojan://$uuid_tr_h2_tls@$s_ip_h2:$p_tr_h2?security=tls&sni=$h2_sni&type=h2&host=$h2_sni&path=%2F${uuid_tr_h2_tls}#tr-h2-tls-$hostname-$ip_tag"
    echo "$tr_h2_link" > "$SBFOLDER/tr_h2_tls.txt"
    red "🚀【 Trojan-H2-TLS-$ip_tag 】节点信息如下：" && sleep 2
    echo -e "${yellow}$tr_h2_link${plain}\n"
    print_qr "$tr_h2_link"
  fi
}

resvless_h2_re() {
  [[ -z "$port_vl_h2_re" ]] && return 0
  echo
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
  if [[ "$server_ip" = "dual" ]]; then
    local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
    local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
    local vl_h2_re_link_v4="vless://$uuid_vl_h2_re@$v4_addr:$port_vl_h2_re?encryption=none&security=reality&sni=$vl_name&fp=chrome&pbk=$public_key&sid=$short_id&type=h2&path=%2F${uuid_vl_h2_re}#vl-h2-reality-$hostname-IPV4"
    local vl_h2_re_link_v6="vless://$uuid_vl_h2_re@[$v6_addr]:$port_vl_h2_re?encryption=none&security=reality&sni=$vl_name&fp=chrome&pbk=$public_key&sid=$short_id&type=h2&path=%2F${uuid_vl_h2_re}#vl-h2-reality-$hostname-IPV6"
    echo -e "$vl_h2_re_link_v4\n$vl_h2_re_link_v6" > "$SBFOLDER/vl_h2_reality.txt"
    red "🚀【 VLESS-HTTP2-REALITY-IPV4 】节点信息如下：" && sleep 1
    echo -e "${yellow}$vl_h2_re_link_v4${plain}\n"
    print_qr "$vl_h2_re_link_v4"
    red "🚀【 VLESS-HTTP2-REALITY-IPV6 】节点信息如下：" && sleep 1
    echo -e "${yellow}$vl_h2_re_link_v6${plain}\n"
    print_qr "$vl_h2_re_link_v6"
  else
    local ip_tag="IPV4"
    if [[ "$server_ip" =~ : ]]; then ip_tag="IPV6"; fi
    local vl_h2_re_link="vless://$uuid_vl_h2_re@$server_ip:$port_vl_h2_re?encryption=none&security=reality&sni=$vl_name&fp=chrome&pbk=$public_key&sid=$short_id&type=h2&path=%2F${uuid_vl_h2_re}#vl-h2-reality-$hostname-$ip_tag"
    echo "$vl_h2_re_link" > "$SBFOLDER/vl_h2_reality.txt"
    red "🚀【 VLESS-HTTP2-REALITY-$ip_tag 】节点信息如下：" && sleep 2
    echo -e "${yellow}$vl_h2_re_link${plain}\n"
    print_qr "$vl_h2_re_link"
  fi
}

ressocks() {
  [[ -z "$port_socks" ]] && return 0
  echo
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
  if [[ "$server_ip" = "dual" ]]; then
    local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
    local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
    local socks_link_v4="socks://$socks_username:$socks_password@$v4_addr:$port_socks#socks-$hostname-IPV4"
    local socks_link_v6="socks://$socks_username:$socks_password@[$v6_addr]:$port_socks#socks-$hostname-IPV6"
    echo -e "$socks_link_v4\n$socks_link_v6" > "$SBFOLDER/socks.txt"
    red "🚀【 Socks5-IPV4 】代理信息如下：" && sleep 1
    echo -e "${yellow}$socks_link_v4${plain}\n"
    red "🚀【 Socks5-IPV6 】代理信息如下：" && sleep 1
    echo -e "${yellow}$socks_link_v6${plain}\n"
    print_qr "$socks_link_v4"
  else
    local ip_tag="IPV4"
    if [[ "$server_ip" =~ : ]]; then ip_tag="IPV6"; fi
    local socks_link="socks://$socks_username:$socks_password@$server_ip:$port_socks#socks-$hostname-$ip_tag"
    echo "$socks_link" > "$SBFOLDER/socks.txt"
    red "🚀【 Socks5-$ip_tag 】代理信息如下：" && sleep 2
    echo -e "${yellow}$socks_link${plain}\n"
    green "客户端地址：$server_ip"
    green "客户端端口：$port_socks"
    green "客户端用户名：$socks_username"
    green "客户端密码：$socks_password"
    echo
    print_qr "$socks_link"
  fi
}

sb_client() {
  # This builds the complete client configurations for SFA/SFI/SFW and Clash Meta (Mihomo)
  # dynamically utilizing jq, reducing 1000+ lines of duplicate templates.

  local cur_cert_type=$(cat /var/Sing-Box-DuolaD/cert_type.log 2>/dev/null || echo "self")
  local cert_content=""
  if [[ "$is_self_signed" == "true" ]]; then
    if [[ -f "$SBFOLDER/ca.pem" ]]; then
      cert_content=$(awk '/-----BEGIN CERTIFICATE-----/{flag=1} flag{print} /-----END CERTIFICATE-----/{flag=0; exit}' "$SBFOLDER/ca.pem")
    elif [[ -f "$SBFOLDER/cert.pem" ]]; then
      cert_content=$(awk '/-----BEGIN CERTIFICATE-----/{flag=1} flag{print} /-----END CERTIFICATE-----/{flag=0; exit}' "$SBFOLDER/cert.pem")
    fi
  fi

  local caddy_active=false
  if systemctl is-active --quiet caddy 2>/dev/null || rc-service caddy status 2>/dev/null | grep -q "started"; then
    caddy_active=true
  fi

  # Helper variables for Caddy port/server overrides
  local cl_p_vl_ws="$port_vl_ws_tls"
  local cl_p_vl_hu="$port_vl_hu_tls"
  local cl_p_vl_h2="$port_vl_h2_tls"
  local cl_p_vm_ws="$port_vm_ws_tls"
  local cl_p_vm_hu="$port_vm_hu_tls"
  local cl_p_vm_h2="$port_vm_h2_tls"
  local cl_p_tr_ws="$port_tr_ws_tls"
  local cl_p_tr_hu="$port_tr_hu_tls"
  local cl_p_tr_h2="$port_tr_h2_tls"

  local cl_s_vl_ws="$tls_sni"
  local cl_s_vl_hu="$tls_sni"
  local cl_s_vl_h2="$tls_sni"
  local cl_s_vm_ws="$tls_sni"
  local cl_s_vm_hu="$tls_sni"
  local cl_s_vm_h2="$tls_sni"
  local cl_s_tr_ws="$tls_sni"
  local cl_s_tr_hu="$tls_sni"
  local cl_s_tr_h2="$tls_sni"

  if $caddy_active; then
    cl_p_vl_ws="443"
    cl_p_vl_hu="443"
    cl_p_vl_h2="443"
    cl_p_vm_ws="443"
    cl_p_vm_hu="443"
    cl_p_vm_h2="443"
    cl_p_tr_ws="443"
    cl_p_tr_hu="443"
    cl_p_tr_h2="443"
    
    local cert_type=$(cat /var/Sing-Box-DuolaD/cert_type.log 2>/dev/null || echo "self")
    if [[ "$cert_type" == "domain" && -n "$tls_sni" ]]; then
      cl_s_vl_ws="$tls_sni"
      cl_s_vl_hu="$tls_sni"
      cl_s_vl_h2="$tls_sni"
      cl_s_vm_ws="$tls_sni"
      cl_s_vm_hu="$tls_sni"
      cl_s_vm_h2="$tls_sni"
      cl_s_tr_ws="$tls_sni"
      cl_s_tr_hu="$tls_sni"
      cl_s_tr_h2="$tls_sni"
    fi
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

  local outs='[]'
  local v4_addr=$(cat "$SBFOLDER/v4.log" 2>/dev/null)
  local v6_addr=$(cat "$SBFOLDER/v6.log" 2>/dev/null)
  if [[ "$server_ipcl" = "dual" ]]; then
    if [[ -z "$v4_addr" || -z "$v6_addr" ]]; then
      v4v6
      v4_addr="$v4"
      v6_addr="$v6"
    fi
  fi

  add_sb_outbound() {
    local tag="$1"
    local type="$2"
    local server="$3"
    local port="$4"
    local extra_json="$5"
    outs=$(echo "$outs" | jq --arg tag "$tag" --arg type "$type" --arg server "$server" --arg port "$port" --argjson extra "$extra_json" \
      '. + [{
        "type": $type,
        "tag": $tag,
        "server": $server,
        "server_port": ($port | tonumber)
      } + $extra]')
  }

  local clash_proxies=""
  local clash_tags=()
  
  add_clash_proxy() {
    local name="$1"
    local type="$2"
    local server="$3"
    local port="$4"
    local extra_yaml="$5"
    
    clash_proxies+="- name: $name
  type: $type
  server: $server
  port: $port
  udp: true
$extra_yaml\n\n"
    clash_tags+=("$name")
  }

  resolve_servers() {
    local var_port="$1"
    local default_server="$2"
    if [[ -z "$var_port" ]]; then
      return 0
    fi
    if [[ -f "$SBFOLDER/cfvmadd_local.txt" ]]; then
      local local_cdn=$(cat "$SBFOLDER/cfvmadd_local.txt" 2>/dev/null)
      echo "single|$local_cdn"
    else
      local is_domain=false
      if [[ "$is_self_signed" == "false" && -n "$ym_domain" && "$ym_domain" != "$(get_self_domain)" ]]; then
        if ! [[ "$ym_domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
          is_domain=true
        fi
      fi
      if $is_domain; then
        echo "single|$ym_domain"
      elif [[ "$server_ipcl" = "dual" ]]; then
        echo "v4|$v4_addr v6|$v6_addr"
      else
        local server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null || curl -s4 ip.sb)
        echo "single|${server_ip:-$default_server}"
      fi
    fi
  }

  local cl_tls_common=""
  if [[ "$is_self_signed" = "true" ]]; then
    local indented_cert=$(echo "$cert_content" | sed 's/^/    /')
    cl_tls_common="  skip-cert-verify: false
  ca-str: |
$indented_cert"
  else
    cl_tls_common="  skip-cert-verify: false"
  fi

  local cl_tls_caddy=""
  if $caddy_active; then
    if [[ "$is_self_signed" = "true" ]]; then
      cl_tls_caddy="  skip-cert-verify: true"
    else
      cl_tls_caddy="  skip-cert-verify: false"
    fi
  else
    cl_tls_caddy="$cl_tls_common"
  fi

  # 1. VLESS Reality
  if [[ -n "$port_vl_re" ]]; then
    local servers_list=$(resolve_servers "$port_vl_re" "$server_ipcl")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local ip_tag="IPV4"
      if [[ "$s_type" == "v6" || "$s_addr" =~ : ]]; then ip_tag="IPV6"; fi
      local suffix="-$hostname-$ip_tag"
      
      local vl_re_extra=$(jq -n --arg uuid "$uuid_vl_re" --arg name "$vl_name" --arg pbk "$public_key" --arg sid "$short_id" \
        '{uuid: $uuid, flow: "xtls-rprx-vision", tls: {enabled: true, server_name: $name, utls: {enabled: true, fingerprint: "chrome"}, reality: {enabled: true, public_key: $pbk, short_id: $sid}}}')
      add_sb_outbound "vless-reality${suffix}" "vless" "$s_addr" "$port_vl_re" "$vl_re_extra"
      
      local cl_vl_re_opts="  uuid: $uuid_vl_re
  network: tcp
  tls: true
  flow: xtls-rprx-vision
  servername: $vl_name
  reality-opts:
    public-key: $public_key
    short-id: $short_id
  client-fingerprint: chrome"
      add_clash_proxy "vless-reality${suffix}" "vless" "$s_addr" "$port_vl_re" "$cl_vl_re_opts"
    done
  fi

  # 2. VLESS WS TLS
  if [[ -n "$port_vl_ws_tls" ]]; then
    local servers_list=$(resolve_servers "$cl_p_vl_ws" "$cl_s_vl_ws")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local ip_tag="IPV4"
      if [[ "$s_type" == "v6" || "$s_addr" =~ : ]]; then ip_tag="IPV6"; fi
      local suffix="-$hostname-$ip_tag"
      local node_sni="$tls_sni"
      [[ "$cur_cert_type" == "ip" ]] && node_sni="$s_addr"
      
      local vl_ws_extra=$(jq -n --arg uuid "$uuid_vl_ws" --arg sni "$node_sni" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{uuid: $uuid, transport: {type: "ws", path: $uuid}, tls: ({enabled: true, server_name: $sni, insecure: false, utls: {enabled: true, fingerprint: "chrome"}} + (if $is_self and ($cert | length) > 0 then {certificate: [$cert]} else {} end))}')
      add_sb_outbound "vless-ws-tls${suffix}" "vless" "$s_addr" "$cl_p_vl_ws" "$vl_ws_extra"
      
      local cl_vl_ws_opts="  uuid: $uuid_vl_ws
  network: ws
  tls: true
  servername: $node_sni
$cl_tls_caddy
  ws-opts:
    path: \"/${uuid_vl_ws}\"
    headers:
      Host: $node_sni"
      add_clash_proxy "vless-ws-tls${suffix}" "vless" "$s_addr" "$cl_p_vl_ws" "$cl_vl_ws_opts"
    done
  fi

  # 3. VLESS HTTPUpgrade TLS
  if [[ -n "$port_vl_hu_tls" ]]; then
    local servers_list=$(resolve_servers "$cl_p_vl_hu" "$cl_s_vl_hu")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local ip_tag="IPV4"
      if [[ "$s_type" == "v6" || "$s_addr" =~ : ]]; then ip_tag="IPV6"; fi
      local suffix="-$hostname-$ip_tag"
      local node_sni="$tls_sni"
      [[ "$cur_cert_type" == "ip" ]] && node_sni="$s_addr"
      
      local vl_hu_extra=$(jq -n --arg uuid "$uuid_vl_hu" --arg sni "$node_sni" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{uuid: $uuid, transport: {type: "httpupgrade", path: $uuid}, tls: ({enabled: true, server_name: $sni, insecure: false, utls: {enabled: true, fingerprint: "chrome"}} + (if $is_self and ($cert | length) > 0 then {certificate: [$cert]} else {} end))}')
      add_sb_outbound "vless-hu-tls${suffix}" "vless" "$s_addr" "$cl_p_vl_hu" "$vl_hu_extra"
      
      local cl_vl_hu_opts="  uuid: $uuid_vl_hu
  network: httpupgrade
  tls: true
  servername: $node_sni
$cl_tls_caddy
  httpupgrade-opts:
    path: \"/${uuid_vl_hu}\"
    headers:
      Host: $node_sni"
      add_clash_proxy "vless-hu-tls${suffix}" "vless" "$s_addr" "$cl_p_vl_hu" "$cl_vl_hu_opts"
    done
  fi

  # 4. VMess WS (No TLS)
  if [[ -n "$port_vm_ws" ]]; then
    local servers_list=$(resolve_servers "$port_vm_ws" "$tls_sni")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local ip_tag="IPV4"
      if [[ "$s_type" == "v6" || "$s_addr" =~ : ]]; then ip_tag="IPV6"; fi
      local suffix="-$hostname-$ip_tag"
      
      local vm_ws_extra=$(jq -n --arg uuid "$uuid_vm_ws" \
        '{uuid: $uuid, security: "auto", packet_encoding: "packetaddr", transport: {type: "ws", path: $uuid}}')
      add_sb_outbound "vmess-ws${suffix}" "vmess" "$s_addr" "$port_vm_ws" "$vm_ws_extra"
      
      local cl_vm_ws_opts="  uuid: $uuid_vm_ws
  alterId: 0
  cipher: auto
  network: ws
  tls: false
  ws-opts:
    path: \"/${uuid_vm_ws}\"
    headers:
      Host: $tls_sni"
      add_clash_proxy "vmess-ws${suffix}" "vmess" "$s_addr" "$port_vm_ws" "$cl_vm_ws_opts"
    done
  fi

  # 5. VMess WS TLS
  if [[ -n "$port_vm_ws_tls" ]]; then
    local servers_list=$(resolve_servers "$cl_p_vm_ws" "$cl_s_vm_ws")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local ip_tag="IPV4"
      if [[ "$s_type" == "v6" || "$s_addr" =~ : ]]; then ip_tag="IPV6"; fi
      local suffix="-$hostname-$ip_tag"
      local node_sni="$tls_sni"
      [[ "$cur_cert_type" == "ip" ]] && node_sni="$s_addr"
      
      local vm_ws_tls_extra=$(jq -n --arg uuid "$uuid_vm_ws_tls" --arg sni "$node_sni" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{uuid: $uuid, security: "auto", packet_encoding: "packetaddr", transport: {type: "ws", path: $uuid}, tls: ({enabled: true, server_name: $sni, insecure: false, utls: {enabled: true, fingerprint: "chrome"}} + (if $is_self and ($cert | length) > 0 then {certificate: [$cert]} else {} end))}')
      add_sb_outbound "vmess-ws-tls${suffix}" "vmess" "$s_addr" "$cl_p_vm_ws" "$vm_ws_tls_extra"
      
      local cl_vm_ws_tls_opts="  uuid: $uuid_vm_ws_tls
  alterId: 0
  cipher: auto
  network: ws
  tls: true
  servername: $node_sni
$cl_tls_caddy
  ws-opts:
    path: \"/${uuid_vm_ws_tls}\"
    headers:
      Host: $node_sni"
      add_clash_proxy "vmess-ws-tls${suffix}" "vmess" "$s_addr" "$cl_p_vm_ws" "$cl_vm_ws_tls_opts"
    done
  fi

  # 6. VMess HTTPUpgrade TLS
  if [[ -n "$port_vm_hu_tls" ]]; then
    local servers_list=$(resolve_servers "$cl_p_vm_hu" "$cl_s_vm_hu")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local ip_tag="IPV4"
      if [[ "$s_type" == "v6" || "$s_addr" =~ : ]]; then ip_tag="IPV6"; fi
      local suffix="-$hostname-$ip_tag"
      local node_sni="$tls_sni"
      [[ "$cur_cert_type" == "ip" ]] && node_sni="$s_addr"
      
      local vm_hu_tls_extra=$(jq -n --arg uuid "$uuid_vm_hu_tls" --arg sni "$node_sni" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{uuid: $uuid, security: "auto", packet_encoding: "packetaddr", transport: {type: "httpupgrade", path: $uuid}, tls: ({enabled: true, server_name: $sni, insecure: false, utls: {enabled: true, fingerprint: "chrome"}} + (if $is_self and ($cert | length) > 0 then {certificate: [$cert]} else {} end))}')
      add_sb_outbound "vmess-hu-tls${suffix}" "vmess" "$s_addr" "$cl_p_vm_hu" "$vm_hu_tls_extra"
      
      local cl_vm_hu_tls_opts="  uuid: $uuid_vm_hu_tls
  alterId: 0
  cipher: auto
  network: httpupgrade
  tls: true
  servername: $node_sni
$cl_tls_caddy
  httpupgrade-opts:
    path: \"/${uuid_vm_hu_tls}\"
    headers:
      Host: $node_sni"
      add_clash_proxy "vmess-hu-tls${suffix}" "vmess" "$s_addr" "$cl_p_vm_hu" "$cl_vm_hu_tls_opts"
    done
  fi

  # 7. Trojan TLS
  if [[ -n "$port_tr_tls" ]]; then
    local servers_list=$(resolve_servers "$port_tr_tls" "$tls_sni")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local ip_tag="IPV4"
      if [[ "$s_type" == "v6" || "$s_addr" =~ : ]]; then ip_tag="IPV6"; fi
      local suffix="-$hostname-$ip_tag"
      local node_sni="$tls_sni"
      [[ "$cur_cert_type" == "ip" ]] && node_sni="$s_addr"
      
      local tr_tls_extra=$(jq -n --arg uuid "$uuid_tr_tls" --arg sni "$node_sni" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{password: $uuid, tls: ({enabled: true, server_name: $sni, insecure: false, utls: {enabled: true, fingerprint: "chrome"}} + (if $is_self and ($cert | length) > 0 then {certificate: [$cert]} else {} end))}')
      add_sb_outbound "trojan-tls${suffix}" "trojan" "$s_addr" "$port_tr_tls" "$tr_tls_extra"
      
      local cl_tr_tls_opts="  password: $uuid_tr_tls
  network: tcp
  tls: true
  servername: $node_sni
$cl_tls_common"
      add_clash_proxy "trojan-tls${suffix}" "trojan" "$s_addr" "$port_tr_tls" "$cl_tr_tls_opts"
    done
  fi

  # 8. Trojan WS TLS
  if [[ -n "$port_tr_ws_tls" ]]; then
    local servers_list=$(resolve_servers "$cl_p_tr_ws" "$cl_s_tr_ws")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local ip_tag="IPV4"
      if [[ "$s_type" == "v6" || "$s_addr" =~ : ]]; then ip_tag="IPV6"; fi
      local suffix="-$hostname-$ip_tag"
      local node_sni="$tls_sni"
      [[ "$cur_cert_type" == "ip" ]] && node_sni="$s_addr"
      
      local tr_ws_extra=$(jq -n --arg uuid "$uuid_tr_ws_tls" --arg sni "$node_sni" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{password: $uuid, transport: {type: "ws", path: $uuid}, tls: ({enabled: true, server_name: $sni, insecure: false, utls: {enabled: true, fingerprint: "chrome"}} + (if $is_self and ($cert | length) > 0 then {certificate: [$cert]} else {} end))}')
      add_sb_outbound "trojan-ws-tls${suffix}" "trojan" "$s_addr" "$cl_p_tr_ws" "$tr_ws_extra"
      
      local cl_tr_ws_opts="  password: $uuid_tr_ws_tls
  network: ws
  tls: true
  servername: $node_sni
$cl_tls_caddy
  ws-opts:
    path: \"/${uuid_tr_ws_tls}\"
    headers:
      Host: $node_sni"
      add_clash_proxy "trojan-ws-tls${suffix}" "trojan" "$s_addr" "$cl_p_tr_ws" "$cl_tr_ws_opts"
    done
  fi

  # 9. Trojan HTTPUpgrade TLS
  if [[ -n "$port_tr_hu_tls" ]]; then
    local servers_list=$(resolve_servers "$cl_p_tr_hu" "$cl_s_tr_hu")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local ip_tag="IPV4"
      if [[ "$s_type" == "v6" || "$s_addr" =~ : ]]; then ip_tag="IPV6"; fi
      local suffix="-$hostname-$ip_tag"
      local node_sni="$tls_sni"
      [[ "$cur_cert_type" == "ip" ]] && node_sni="$s_addr"
      
      local tr_hu_extra=$(jq -n --arg uuid "$uuid_tr_hu_tls" --arg sni "$node_sni" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{password: $uuid, transport: {type: "httpupgrade", path: $uuid}, tls: ({enabled: true, server_name: $sni, insecure: false, utls: {enabled: true, fingerprint: "chrome"}} + (if $is_self and ($cert | length) > 0 then {certificate: [$cert]} else {} end))}')
      add_sb_outbound "trojan-hu-tls${suffix}" "trojan" "$s_addr" "$cl_p_tr_hu" "$tr_hu_extra"
      
      local cl_tr_hu_opts="  password: $uuid_tr_hu_tls
  network: httpupgrade
  tls: true
  servername: $node_sni
$cl_tls_caddy
  httpupgrade-opts:
    path: \"/${uuid_tr_hu_tls}\"
    headers:
      Host: $node_sni"
      add_clash_proxy "trojan-hu-tls${suffix}" "trojan" "$s_addr" "$cl_p_tr_hu" "$cl_tr_hu_opts"
    done
  fi

  # 10. Shadowsocks (SS-2022)
  if [[ -n "$port_ss" ]]; then
    local servers_list=$(resolve_servers "$port_ss" "$server_ipcl")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local ip_tag="IPV4"
      if [[ "$s_type" == "v6" || "$s_addr" =~ : ]]; then ip_tag="IPV6"; fi
      local suffix="-$hostname-$ip_tag"
      
      local ss_extra=$(jq -n --arg pass "$ss_password" --arg method "${ss_method:-2022-blake3-aes-128-gcm}" \
        '{method: $method, password: $pass}')
      add_sb_outbound "shadowsocks${suffix}" "shadowsocks" "$s_addr" "$port_ss" "$ss_extra"
      
      local cl_ss_opts="  cipher: ${ss_method:-2022-blake3-aes-128-gcm}
  password: $ss_password"
      add_clash_proxy "shadowsocks${suffix}" "ss" "$s_addr" "$port_ss" "$cl_ss_opts"
    done
  fi

  # 11. Hysteria 2
  if [[ -n "$port_hy2" ]]; then
    local servers_list=$(resolve_servers "$port_hy2" "$cl_hy2_ip")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local ip_tag="IPV4"
      if [[ "$s_type" == "v6" || "$s_addr" =~ : ]]; then ip_tag="IPV6"; fi
      local suffix="-$hostname-$ip_tag"
      local cur_hy2_sni="$hy2_name"
      [[ "$cur_cert_type" == "ip" ]] && cur_hy2_sni="$s_addr"
      
      local ports_array="[]"
      [[ -n "$sbhy2pt" ]] && ports_array="[$sbhy2pt]"
      
      local hy2_tls_obj=$(jq -n --arg name "$cur_hy2_sni" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{enabled: true, server_name: $name, insecure: false, alpn: ["h3"]} + (if $is_self and ($cert | length) > 0 then { certificate: [$cert] } else {} end)')
      local hy2_extra=$(jq -n --arg password "$uuid_hy2" --argjson tls "$hy2_tls_obj" --argjson extra_ports "$ports_array" \
        '{password: $password, tls: $tls} + (if ($extra_ports | length) > 0 then { server_ports: $extra_ports } else {} end)')
      add_sb_outbound "hysteria2${suffix}" "hysteria2" "$s_addr" "$port_hy2" "$hy2_extra"
      
      local cl_hy2_opts="  password: $uuid_hy2
  alpn:
    - h3
  sni: $cur_hy2_sni
$cl_tls_common"
      if [[ "$is_self_signed" = "true" && -n "$SHA256" ]]; then
        cl_hy2_opts+="
  fingerprint: $SHA256"
      fi
      cl_hy2_opts+="
  fast-open: true"
      if [[ -n "$cmhy2pt" ]]; then
        cl_hy2_opts+="
  ports: $cmhy2pt"
      fi
      add_clash_proxy "hysteria2${suffix}" "hysteria2" "$s_addr" "$port_hy2" "$cl_hy2_opts"
    done
  fi

  # 12. Tuic-v5
  if [[ -n "$port_tu" ]]; then
    local servers_list=$(resolve_servers "$port_tu" "$cl_tu5_ip")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local ip_tag="IPV4"
      if [[ "$s_type" == "v6" || "$s_addr" =~ : ]]; then ip_tag="IPV6"; fi
      local suffix="-$hostname-$ip_tag"
      local cur_tu5_sni="$tu5_name"
      [[ "$cur_cert_type" == "ip" ]] && cur_tu5_sni="$s_addr"
      
      local tu5_tls_obj=$(jq -n --arg name "$cur_tu5_sni" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{enabled: true, server_name: $name, insecure: false, alpn: ["h3"]} + (if $is_self and ($cert | length) > 0 then { certificate: [$cert] } else {} end)')
      local tu_extra=$(jq -n --arg uuid "$uuid_tu" --argjson tls "$tu5_tls_obj" \
        '{uuid: $uuid, password: $uuid, congestion_control: "bbr", udp_relay_mode: "native", udp_over_stream: false, zero_rtt_handshake: false, heartbeat: "10s", tls: $tls}')
      add_sb_outbound "tuic5${suffix}" "tuic" "$s_addr" "$port_tu" "$tu_extra"
      
      local cl_tu_opts="  uuid: $uuid_tu
  password: $uuid_tu
  alpn: [h3]
  disable-sni: $is_self_signed
  reduce-rtt: true
  udp-relay-mode: native
  congestion-controller: bbr
  sni: $cur_tu5_sni
$cl_tls_common"
      add_clash_proxy "tuic5${suffix}" "tuic" "$s_addr" "$port_tu" "$cl_tu_opts"
    done
  fi

  # 13. AnyTLS
  if [[ -n "$port_an" ]]; then
    local servers_list=$(resolve_servers "$port_an" "$sb_an_ip")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local ip_tag="IPV4"
      if [[ "$s_type" == "v6" || "$s_addr" =~ : ]]; then ip_tag="IPV6"; fi
      local suffix="-$hostname-$ip_tag"
      
      local an_tls_obj=$(jq -n --arg name "$an_name" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{enabled: true, server_name: $name, insecure: false} + (if $is_self and ($cert | length) > 0 then { certificate: [$cert] } else {} end)')
      local an_extra=$(jq -n --arg password "$uuid_an" --argjson tls "$an_tls_obj" \
        '{password: $password, idle_session_check_interval: "30s", idle_session_timeout: "30s", min_idle_session: 5, tls: $tls}')
      add_sb_outbound "anytls${suffix}" "anytls" "$s_addr" "$port_an" "$an_extra"
    done
  fi

  # VMess-TCP
  if [[ -n "$port_vm_tcp" ]]; then
    local servers_list=$(resolve_servers "$port_vm_tcp" "$server_ipcl")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local ip_tag="IPV4"
      if [[ "$s_type" == "v6" || "$s_addr" =~ : ]]; then ip_tag="IPV6"; fi
      local suffix="-$hostname-$ip_tag"
      local vm_tcp_extra=$(jq -n --arg uuid "$uuid_vm_tcp" '{uuid: $uuid, security: "auto", packet_encoding: "packetaddr"}')
      add_sb_outbound "vmess-tcp${suffix}" "vmess" "$s_addr" "$port_vm_tcp" "$vm_tcp_extra"
      local cl_vm_tcp_opts="  uuid: $uuid_vm_tcp
  alterId: 0
  cipher: auto
  network: tcp
  tls: false"
      add_clash_proxy "vmess-tcp${suffix}" "vmess" "$s_addr" "$port_vm_tcp" "$cl_vm_tcp_opts"
    done
  fi

  # VMess-HTTP
  if [[ -n "$port_vm_http" ]]; then
    local servers_list=$(resolve_servers "$port_vm_http" "$server_ipcl")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local ip_tag="IPV4"
      if [[ "$s_type" == "v6" || "$s_addr" =~ : ]]; then ip_tag="IPV6"; fi
      local suffix="-$hostname-$ip_tag"
      local vm_http_extra=$(jq -n --arg uuid "$uuid_vm_http" '{uuid: $uuid, security: "auto", packet_encoding: "packetaddr", transport: {type: "http"}}')
      add_sb_outbound "vmess-http${suffix}" "vmess" "$s_addr" "$port_vm_http" "$vm_http_extra"
      local cl_vm_http_opts="  uuid: $uuid_vm_http
  alterId: 0
  cipher: auto
  network: http
  tls: false"
      add_clash_proxy "vmess-http${suffix}" "vmess" "$s_addr" "$port_vm_http" "$cl_vm_http_opts"
    done
  fi

  # VMess-QUIC
  if [[ -n "$port_vm_quic" ]]; then
    local servers_list=$(resolve_servers "$port_vm_quic" "$tls_sni")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local ip_tag="IPV4"
      if [[ "$s_type" == "v6" || "$s_addr" =~ : ]]; then ip_tag="IPV6"; fi
      local suffix="-$hostname-$ip_tag"
      local node_sni="$tls_sni"
      [[ "$cur_cert_type" == "ip" ]] && node_sni="$s_addr"
      local vm_quic_extra=$(jq -n --arg uuid "$uuid_vm_quic" --arg sni "$node_sni" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{uuid: $uuid, security: "auto", packet_encoding: "packetaddr", transport: {type: "quic"}, tls: ({enabled: true, server_name: $sni, insecure: false, alpn: ["h3"]} + (if $is_self and ($cert | length) > 0 then {certificate: [$cert]} else {} end))}')
      add_sb_outbound "vmess-quic${suffix}" "vmess" "$s_addr" "$port_vm_quic" "$vm_quic_extra"
      local cl_vm_quic_opts="  uuid: $uuid_vm_quic
  alterId: 0
  cipher: auto
  network: quic
  tls: true
  servername: $node_sni
$cl_tls_common"
      add_clash_proxy "vmess-quic${suffix}" "vmess" "$s_addr" "$port_vm_quic" "$cl_vm_quic_opts"
    done
  fi

  # VMess-H2-TLS
  if [[ -n "$port_vm_h2_tls" ]]; then
    local servers_list=$(resolve_servers "$cl_p_vm_h2" "$cl_s_vm_h2")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local ip_tag="IPV4"
      if [[ "$s_type" == "v6" || "$s_addr" =~ : ]]; then ip_tag="IPV6"; fi
      local suffix="-$hostname-$ip_tag"
      local vm_h2_extra=$(jq -n --arg uuid "$uuid_vm_h2_tls" --arg sni "$cl_s_vm_h2" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{uuid: $uuid, security: "auto", packet_encoding: "packetaddr", transport: {type: "http", host: [$sni], path: $uuid}, tls: ({enabled: true, server_name: $sni, insecure: false} + (if $is_self and ($cert | length) > 0 then {certificate: [$cert]} else {} end))}')
      add_sb_outbound "vmess-h2-tls${suffix}" "vmess" "$s_addr" "$cl_p_vm_h2" "$vm_h2_extra"
      local cl_vm_h2_opts="  uuid: $uuid_vm_h2_tls
  alterId: 0
  cipher: auto
  network: h2
  tls: true
  servername: $cl_s_vm_h2
$cl_tls_caddy
  h2-opts:
    host:
      - $cl_s_vm_h2
    path: /$uuid_vm_h2_tls"
      add_clash_proxy "vmess-h2-tls${suffix}" "vmess" "$s_addr" "$cl_p_vm_h2" "$cl_vm_h2_opts"
    done
  fi

  # VLESS-H2-TLS
  if [[ -n "$port_vl_h2_tls" ]]; then
    local servers_list=$(resolve_servers "$cl_p_vl_h2" "$cl_s_vl_h2")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local ip_tag="IPV4"
      if [[ "$s_type" == "v6" || "$s_addr" =~ : ]]; then ip_tag="IPV6"; fi
      local suffix="-$hostname-$ip_tag"
      local vl_h2_extra=$(jq -n --arg uuid "$uuid_vl_h2" --arg sni "$cl_s_vl_h2" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{uuid: $uuid, transport: {type: "http", host: [$sni], path: $uuid}, tls: ({enabled: true, server_name: $sni, insecure: false} + (if $is_self and ($cert | length) > 0 then {certificate: [$cert]} else {} end))}')
      add_sb_outbound "vless-h2-tls${suffix}" "vless" "$s_addr" "$cl_p_vl_h2" "$vl_h2_extra"
      local cl_vl_h2_opts="  uuid: $uuid_vl_h2
  network: h2
  tls: true
  servername: $cl_s_vl_h2
$cl_tls_caddy
  h2-opts:
    host:
      - $cl_s_vl_h2
    path: /$uuid_vl_h2"
      add_clash_proxy "vless-h2-tls${suffix}" "vless" "$s_addr" "$cl_p_vl_h2" "$cl_vl_h2_opts"
    done
  fi

  # Trojan-H2-TLS
  if [[ -n "$port_tr_h2_tls" ]]; then
    local servers_list=$(resolve_servers "$cl_p_tr_h2" "$cl_s_tr_h2")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local ip_tag="IPV4"
      if [[ "$s_type" == "v6" || "$s_addr" =~ : ]]; then ip_tag="IPV6"; fi
      local suffix="-$hostname-$ip_tag"
      local tr_h2_extra=$(jq -n --arg password "$uuid_tr_h2_tls" --arg sni "$cl_s_tr_h2" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{password: $password, transport: {type: "http", host: [$sni], path: $password}, tls: ({enabled: true, server_name: $sni, insecure: false} + (if $is_self and ($cert | length) > 0 then {certificate: [$cert]} else {} end))}')
      add_sb_outbound "trojan-h2-tls${suffix}" "trojan" "$s_addr" "$cl_p_tr_h2" "$tr_h2_extra"
      local cl_tr_h2_opts="  password: $uuid_tr_h2_tls
  network: h2
  tls: true
  servername: $cl_s_tr_h2
$cl_tls_caddy
  h2-opts:
    host:
      - $cl_s_tr_h2
    path: /$uuid_tr_h2_tls"
      add_clash_proxy "trojan-h2-tls${suffix}" "trojan" "$s_addr" "$cl_p_tr_h2" "$cl_tr_h2_opts"
    done
  fi

  # VLESS-HTTP2-REALITY
  if [[ -n "$port_vl_h2_re" ]]; then
    local servers_list=$(resolve_servers "$port_vl_h2_re" "$server_ipcl")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local ip_tag="IPV4"
      if [[ "$s_type" == "v6" || "$s_addr" =~ : ]]; then ip_tag="IPV6"; fi
      local suffix="-$hostname-$ip_tag"
      local vl_h2_re_extra=$(jq -n --arg uuid "$uuid_vl_h2_re" --arg name "$vl_name" --arg pbk "$public_key" --arg sid "$short_id" \
        '{uuid: $uuid, transport: {type: "http", host: [$name], path: $uuid}, tls: {enabled: true, server_name: $name, utls: {enabled: true, fingerprint: "chrome"}, reality: {enabled: true, public_key: $pbk, short_id: $sid}}}')
      add_sb_outbound "vless-h2-reality${suffix}" "vless" "$s_addr" "$port_vl_h2_re" "$vl_h2_re_extra"
      local cl_vl_h2_re_opts="  uuid: $uuid_vl_h2_re
  network: h2
  tls: true
  servername: $vl_name
  reality-opts:
    public-key: $public_key
    short-id: $short_id
  client-fingerprint: chrome
  h2-opts:
    host:
      - $vl_name
    path: /$uuid_vl_h2_re"
      add_clash_proxy "vless-h2-reality${suffix}" "vless" "$s_addr" "$port_vl_h2_re" "$cl_vl_h2_re_opts"
    done
  fi

  # Socks
  if [[ -n "$port_socks" ]]; then
    local servers_list=$(resolve_servers "$port_socks" "$server_ipcl")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local suffix=""
      [[ "$server_ipcl" = "dual" ]] && suffix="-${s_type^^}"
      local socks_extra=$(jq -n --arg user "${socks_username}" --arg pass "$socks_password" \
        '{version: "5", username: $user, password: $pass}')
      add_sb_outbound "socks${suffix}" "socks" "$s_addr" "$port_socks" "$socks_extra"
      local cl_socks_opts="  username: ${socks_username}
  password: $socks_password"
      add_clash_proxy "socks${suffix}" "socks" "$s_addr" "$port_socks" "$cl_socks_opts"
    done
  fi

  # 14. Cloudflare Argo Tunnels
  local argo_path="${uuid_vm_ws}"
  if [[ -n "$port_vm_ws" ]]; then
    if ps -ef 2>/dev/null | grep -q '[c]loudflared.*run'; then
      local argogd=$(cat "$SBFOLDER/sbargoym.log" 2>/dev/null)
      local argo_fixed_extra=$(jq -n --arg uuid "$uuid_vm_ws" --arg host "$argogd" --arg path "$argo_path" \
        '{uuid: $uuid, security: "auto", packet_encoding: "packetaddr", transport: {type: "ws", path: $path, headers: {Host: $host}}, tls: {enabled: true, server_name: $host, insecure: false, utls: {enabled: true, fingerprint: "chrome"}}}')
      add_sb_outbound "vmess-tls-argo固定-$hostname" "vmess" "$vmadd_argo" "443" "$argo_fixed_extra"
      
      local cl_argo_fixed_opts="  uuid: $uuid_vm_ws
  alterId: 0
  cipher: auto
  network: ws
  tls: true
  servername: $argogd
  ws-opts:
    path: \"$argo_path\"
    headers:
      Host: $argogd"
      add_clash_proxy "vmess-tls-argo固定-$hostname" "vmess" "$vmadd_argo" "443" "$cl_argo_fixed_opts"
    fi
    
    if ps -ef 2>/dev/null | grep -q "[l]ocalhost:$port_vm_ws"; then
      local argo_domain=$(grep -a -o -E '[a-zA-Z0-9.-]+\.trycloudflare\.com' "$SBFOLDER/argo.log" 2>/dev/null | head -n 1)
      local argo_temp_extra=$(jq -n --arg uuid "$uuid_vm_ws" --arg host "$argo_domain" --arg path "$argo_path" \
        '{uuid: $uuid, security: "auto", packet_encoding: "packetaddr", transport: {type: "ws", path: $path, headers: {Host: $host}}, tls: {enabled: true, server_name: $host, insecure: false, utls: {enabled: true, fingerprint: "chrome"}}}')
      add_sb_outbound "vmess-tls-argo临时-$hostname" "vmess" "$vmadd_argo" "443" "$argo_temp_extra"
      
      local cl_argo_temp_opts="  uuid: $uuid_vm_ws
  alterId: 0
  cipher: auto
  network: ws
  tls: true
  servername: $argo_domain
  ws-opts:
    path: \"$argo_path\"
    headers:
      Host: $argo_domain"
      add_clash_proxy "vmess-tls-argo临时-$hostname" "vmess" "$vmadd_argo" "443" "$cl_argo_temp_opts"
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
  rm -rf "$SBFOLDER"/{jhdy,vl_reality,vl_ws_tls,vl_hu_tls,vm_ws_argols,vm_ws_argogd,vm_ws,vm_ws_tls,vm_hu_tls,hy2,tuic5,an,tr_tls,tr_ws_tls,tr_hu_tls,ss,vm_tcp,vm_http,vm_quic,vm_h2_tls,vl_h2_tls,tr_h2_tls,vl_h2_reality,socks}.txt
  
  local show_qr_code=false
  local show_client_config=false
  if [ -t 1 ]; then
    readp "是否需要同时在控制台输出各个节点的二维码？[y/N] (默认不输出)：" qr_choice
    if [[ "$qr_choice" =~ ^[Yy]$ ]]; then
      show_qr_code=true
    fi
    if [[ "$1" == "install" ]]; then
      show_client_config=true
      readp "是否需要同时在控制台输出Mihomo、Sing-box客户端SFA/SFI/SFW三合一配置？[Y/n] (默认输出)：" client_choice
      if [[ "$client_choice" =~ ^[Nn]$ ]]; then
        show_client_config=false
      fi
    fi
  fi

  print_qr() {
    local link="$1"
    if $show_qr_code; then
      echo "二维码："
      qrencode -o - -t ANSIUTF8 "$link"
      echo
    fi
  }

  result_vl_vm_hy_tu
  resvless
  resvmess
  reshy2
  restu5
  resan
  restrojan
  resshadowsocks
  resvmess_tcp
  resvmess_http
  resvmess_quic
  resvmess_h2_tls
  resvless_h2_tls
  restrojan_h2_tls
  resvless_h2_re
  ressocks
  
  cat "$SBFOLDER/vl_reality.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/vl_ws_tls.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/vl_hu_tls.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/vm_ws_argols.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/vm_ws_argogd.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/vm_ws.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/vm_ws_tls.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/vm_hu_tls.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/hy2.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/tuic5.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/an.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/tr_tls.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/tr_ws_tls.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/tr_hu_tls.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/ss.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/vm_tcp.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/vm_http.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/vm_quic.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/vm_h2_tls.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/vl_h2_tls.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/tr_h2_tls.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/vl_h2_reality.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  cat "$SBFOLDER/socks.txt" 2>/dev/null >> "$SBFOLDER/jhdy.txt"
  
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

  if $show_client_config; then
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
  fi
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
  local vm_inbound=$(echo "$clean_json" | jq -r '.inbounds[] | select(.type == "vmess") // empty')
  if [[ -z "$vm_inbound" ]]; then
    yellow "因未安装 VMess 协议，无法开启 Argo 隧道！" && sleep 2 && changeserv
    return
  fi
  local vm_no_tls=$(echo "$clean_json" | jq -r ' (.inbounds[] | select(.tag == "vmess-ws-sb") | .listen_port) // empty')
  if [[ -n "$vm_no_tls" ]]; then
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
  local vm_listen_port=$(echo "$clean_json" | jq -r ' (.inbounds[] | select(.tag == "vmess-ws-sb") | .listen_port) // empty')
  if [ "$menu" = "1" ]; then
    green "请稍等……"
    cloudflaredargo
    ps -ef | grep "[l]ocalhost:$vm_listen_port" | awk '{print $2}' | xargs kill 2>/dev/null
    nohup "$SBFOLDER/cloudflared" tunnel --url "http://localhost:$vm_listen_port" --edge-ip-version auto --no-autoupdate --protocol http2 > "$SBFOLDER/argo.log" 2>&1 &
    local argo_url=""
    local count=0
    while [ $count -lt 15 ]; do
      sleep 2
      argo_url=$(grep -a -o -E '[a-zA-Z0-9.-]+\.trycloudflare\.com' "$SBFOLDER/argo.log" 2>/dev/null | head -n 1)
      if [[ -n "$argo_url" ]]; then
        break
      fi
      count=$((count + 1))
    done

    local verified=false
    if [[ -n "$argo_url" ]]; then
      local vcount=0
      while [ $vcount -lt 5 ]; do
        if [[ -n $(curl -sL "https://$argo_url/" -I 2>/dev/null | awk 'NR==1 && /404|400|503|200|502/') ]]; then
          verified=true
          break
        fi
        sleep 2
        vcount=$((vcount + 1))
      done
    fi

    if [ "$verified" = "true" ]; then
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
  readp "1：更换Reality域名伪装地址、切换自签证书与Acme域名证书、开关TLS\n2：更换全协议UUID(密码)、Vmess-Path路径\n3：设置Argo临时隧道、固定隧道\n4：切换IPV4或IPV6的代理优先级\n5：更换Warp-wireguard出站账户/对端IP(Endpoint)\n6：设置所有Vmess节点的CDN优选地址\n0：返回上层\n请选择【0-6】：" menu
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
  
  query_inbound_val() {
    local type="$1"
    local query="$2"
    echo "$clean_json" | jq -r ".inbounds[] | select(.type == \"$type\") | $query // empty" 2>/dev/null | head -n 1
  }

  vl_port=$(query_inbound_val "vless" ".listen_port")
  vm_port=$(query_inbound_val "vmess" ".listen_port")
  hy2_port=$(query_inbound_val "hysteria2" ".listen_port")
  tu5_port=$(query_inbound_val "tuic" ".listen_port")
  an_port=$(query_inbound_val "anytls" ".listen_port")

  hy2_ports=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$hy2_port" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ',' | sed 's/,$//')
  tu5_ports=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$tu5_port" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ',' | sed 's/,$//')
  [[ -n $hy2_ports ]] && hy2zfport="$hy2_ports" || hy2zfport="未添加"
  [[ -n $tu5_ports ]] && tu5zfport="$tu5_ports" || tu5zfport="未添加"
}

# --- Port Management (Main changeport function) ---
changeport() {
  sbactive
  result_vl_vm_hy_tu
  
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
    result_vl_vm_hy_tu
    hy2_ports=$(echo "$hy2_ports" | sed 's/,/,/g')
    IFS=',' read -ra ports <<< "$hy2_ports"
    for port in "${ports[@]}"; do
      iptables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$port_hy2
      ip6tables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$port_hy2
    done
    netfilter-persistent save >/dev/null 2>&1
    service iptables save >/dev/null 2>&1
  }
  
  tu5deports() {
    result_vl_vm_hy_tu
    tu5_ports=$(echo "$tu5_ports" | sed 's/,/,/g')
    IFS=',' read -ra ports <<< "$tu5_ports"
    for port in "${ports[@]}"; do
      iptables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$port_tu
      ip6tables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$port_tu
    done
    netfilter-persistent save >/dev/null 2>&1
    service iptables save >/dev/null 2>&1
  }

  update_inbound_port() {
    local tag="$1"
    local new_port="$2"
    for file in $SBFILES; do
      [ -f "$file" ] && jq --arg tag "$tag" --argjson p "$new_port" ' (.inbounds[] | select(.tag == $tag)).listen_port = $p' "$file" > /tmp/tmp.json && mv /tmp/tmp.json "$file"
    done
  }

  prompt_new_port() {
    local proto_name="$1"
    local current_p="$2"
    local input_port
    while true; do
      readp "\n请输入 ${proto_name} 新端口 [1-65535] (当前为 ${current_p}，直接回车随机分配)：" input_port
      if [[ -z "$input_port" ]]; then
        input_port=$(shuf -i 1000-65535 -n 1)
        break
      elif [[ "$input_port" =~ ^[0-9]+$ && "$input_port" -ge 1 && "$input_port" -le 65535 ]]; then
        break
      else
        red "请输入正确的端口！"
      fi
    done
    echo "$input_port"
  }

  green "更改端口选项："
  echo
  [[ -n "$port_vl_re" ]] && green " 1：VLESS-Reality协议 ${yellow}端口:$port_vl_re${plain}"
  [[ -n "$port_vl_ws_tls" ]] && green " 2：VLESS-WS-TLS协议 ${yellow}端口:$port_vl_ws_tls${plain}"
  [[ -n "$port_vl_hu_tls" ]] && green " 3：VLESS-HTTPUpgrade-TLS协议 ${yellow}端口:$port_vl_hu_tls${plain}"
  [[ -n "$port_vl_h2_tls" ]] && green " 4：VLESS-H2-TLS协议 ${yellow}端口:$port_vl_h2_tls${plain}"
  [[ -n "$port_vl_h2_re" ]] && green " 5：VLESS-HTTP2-REALITY协议 ${yellow}端口:$port_vl_h2_re${plain}"
  [[ -n "$port_vm_ws" ]] && green " 6：VMess-WS协议 ${yellow}端口:$port_vm_ws${plain}"
  [[ -n "$port_vm_ws_tls" ]] && green " 7：VMess-WS-TLS协议 ${yellow}端口:$port_vm_ws_tls${plain}"
  [[ -n "$port_vm_hu_tls" ]] && green " 8：VMess-HTTPUpgrade-TLS协议 ${yellow}端口:$port_vm_hu_tls${plain}"
  [[ -n "$port_vm_tcp" ]] && green " 9：VMess-TCP协议 ${yellow}端口:$port_vm_tcp${plain}"
  [[ -n "$port_vm_http" ]] && green "10：VMess-HTTP协议 ${yellow}端口:$port_vm_http${plain}"
  [[ -n "$port_vm_quic" ]] && green "11：VMess-QUIC协议 ${yellow}端口:$port_vm_quic${plain}"
  [[ -n "$port_vm_h2_tls" ]] && green "12：VMess-H2-TLS协议 ${yellow}端口:$port_vm_h2_tls${plain}"
  [[ -n "$port_tr_tls" ]] && green "13：Trojan-TLS协议 ${yellow}端口:$port_tr_tls${plain}"
  [[ -n "$port_tr_ws_tls" ]] && green "14：Trojan-WS-TLS协议 ${yellow}端口:$port_tr_ws_tls${plain}"
  [[ -n "$port_tr_hu_tls" ]] && green "15：Trojan-HTTPUpgrade-TLS协议 ${yellow}端口:$port_tr_hu_tls${plain}"
  [[ -n "$port_tr_h2_tls" ]] && green "16：Trojan-H2-TLS协议 ${yellow}端口:$port_tr_h2_tls${plain}"
  [[ -n "$port_ss" ]] && green "17：Shadowsocks协议 ${yellow}端口:$port_ss${plain}"
  [[ -n "$port_hy2" ]] && green "18：Hysteria 2协议 ${yellow}端口:$port_hy2  转发多端口: $hy2zfport${plain}"
  [[ -n "$port_tu" ]] && green "19：Tuic-v5协议 ${yellow}端口:$port_tu  转发多端口: $tu5zfport${plain}"
  if [[ -n "$port_an" ]]; then
    green "20：AnyTLS协议 ${yellow}端口:$port_an${plain}"
  fi
  [[ -n "$port_socks" ]] && green "21：Socks协议 ${yellow}端口:$port_socks${plain}"
  green " 0：返回上层"
  readp "请选择要变更端口的协议：" menu
  
  case "$menu" in
    1)
      [[ -z "$port_vl_re" ]] && red "协议未安装！" && sleep 2 && changeport && return
      local p=$(prompt_new_port "VLESS-Reality" "$port_vl_re")
      update_inbound_port "vless-reality-sb" "$p"
      restartsb && sbshare > /dev/null 2>&1
      blue "VLESS-Reality端口已变更为 $p"
      ;;
    2)
      [[ -z "$port_vl_ws_tls" ]] && red "协议未安装！" && sleep 2 && changeport && return
      local p=$(prompt_new_port "VLESS-WS-TLS" "$port_vl_ws_tls")
      update_inbound_port "vless-ws-tls-sb" "$p"
      restartsb && sbshare > /dev/null 2>&1
      blue "VLESS-WS-TLS端口已变更为 $p"
      ;;
    3)
      [[ -z "$port_vl_hu_tls" ]] && red "协议未安装！" && sleep 2 && changeport && return
      local p=$(prompt_new_port "VLESS-HTTPUpgrade-TLS" "$port_vl_hu_tls")
      update_inbound_port "vless-hu-tls-sb" "$p"
      restartsb && sbshare > /dev/null 2>&1
      blue "VLESS-HTTPUpgrade-TLS端口已变更为 $p"
      ;;
    4)
      [[ -z "$port_vl_h2_tls" ]] && red "协议未安装！" && sleep 2 && changeport && return
      local p=$(prompt_new_port "VLESS-H2-TLS" "$port_vl_h2_tls")
      update_inbound_port "vless-h2-tls-sb" "$p"
      restartsb && sbshare > /dev/null 2>&1
      blue "VLESS-H2-TLS端口已变更为 $p"
      ;;
    5)
      [[ -z "$port_vl_h2_re" ]] && red "协议未安装！" && sleep 2 && changeport && return
      local p=$(prompt_new_port "VLESS-HTTP2-REALITY" "$port_vl_h2_re")
      update_inbound_port "vless-h2-reality-sb" "$p"
      restartsb && sbshare > /dev/null 2>&1
      blue "VLESS-HTTP2-REALITY端口已变更为 $p"
      ;;
    6)
      [[ -z "$port_vm_ws" ]] && red "协议未安装！" && sleep 2 && changeport && return
      local p=$(prompt_new_port "VMess-WS" "$port_vm_ws")
      update_inbound_port "vmess-ws-sb" "$p"
      restartsb && sbshare > /dev/null 2>&1
      blue "VMess-WS端口已变更为 $p"
      blue "切记：如果Argo使用中，临时隧道必须重置，固定隧道的CF设置界面端口必须修改为$p"
      ;;
    7)
      [[ -z "$port_vm_ws_tls" ]] && red "协议未安装！" && sleep 2 && changeport && return
      local p=$(prompt_new_port "VMess-WS-TLS" "$port_vm_ws_tls")
      update_inbound_port "vmess-ws-tls-sb" "$p"
      restartsb && sbshare > /dev/null 2>&1
      blue "VMess-WS-TLS端口已变更为 $p"
      ;;
    8)
      [[ -z "$port_vm_hu_tls" ]] && red "协议未安装！" && sleep 2 && changeport && return
      local p=$(prompt_new_port "VMess-HTTPUpgrade-TLS" "$port_vm_hu_tls")
      update_inbound_port "vmess-hu-tls-sb" "$p"
      restartsb && sbshare > /dev/null 2>&1
      blue "VMess-HTTPUpgrade-TLS端口已变更为 $p"
      ;;
    9)
      [[ -z "$port_vm_tcp" ]] && red "协议未安装！" && sleep 2 && changeport && return
      local p=$(prompt_new_port "VMess-TCP" "$port_vm_tcp")
      update_inbound_port "vmess-tcp-sb" "$p"
      restartsb && sbshare > /dev/null 2>&1
      blue "VMess-TCP端口已变更为 $p"
      ;;
    10)
      [[ -z "$port_vm_http" ]] && red "协议未安装！" && sleep 2 && changeport && return
      local p=$(prompt_new_port "VMess-HTTP" "$port_vm_http")
      update_inbound_port "vmess-http-sb" "$p"
      restartsb && sbshare > /dev/null 2>&1
      blue "VMess-HTTP端口已变更为 $p"
      ;;
    11)
      [[ -z "$port_vm_quic" ]] && red "协议未安装！" && sleep 2 && changeport && return
      local p=$(prompt_new_port "VMess-QUIC" "$port_vm_quic")
      update_inbound_port "vmess-quic-sb" "$p"
      restartsb && sbshare > /dev/null 2>&1
      blue "VMess-QUIC端口已变更为 $p"
      ;;
    12)
      [[ -z "$port_vm_h2_tls" ]] && red "协议未安装！" && sleep 2 && changeport && return
      local p=$(prompt_new_port "VMess-H2-TLS" "$port_vm_h2_tls")
      update_inbound_port "vmess-h2-tls-sb" "$p"
      restartsb && sbshare > /dev/null 2>&1
      blue "VMess-H2-TLS端口已变更为 $p"
      ;;
    13)
      [[ -z "$port_tr_tls" ]] && red "协议未安装！" && sleep 2 && changeport && return
      local p=$(prompt_new_port "Trojan-TLS" "$port_tr_tls")
      update_inbound_port "trojan-tls-sb" "$p"
      restartsb && sbshare > /dev/null 2>&1
      blue "Trojan-TLS端口已变更为 $p"
      ;;
    14)
      [[ -z "$port_tr_ws_tls" ]] && red "协议未安装！" && sleep 2 && changeport && return
      local p=$(prompt_new_port "Trojan-WS-TLS" "$port_tr_ws_tls")
      update_inbound_port "trojan-ws-tls-sb" "$p"
      restartsb && sbshare > /dev/null 2>&1
      blue "Trojan-WS-TLS端口已变更为 $p"
      ;;
    15)
      [[ -z "$port_tr_hu_tls" ]] && red "协议未安装！" && sleep 2 && changeport && return
      local p=$(prompt_new_port "Trojan-HTTPUpgrade-TLS" "$port_tr_hu_tls")
      update_inbound_port "trojan-hu-tls-sb" "$p"
      restartsb && sbshare > /dev/null 2>&1
      blue "Trojan-HTTPUpgrade-TLS端口已变更为 $p"
      ;;
    16)
      [[ -z "$port_tr_h2_tls" ]] && red "协议未安装！" && sleep 2 && changeport && return
      local p=$(prompt_new_port "Trojan-H2-TLS" "$port_tr_h2_tls")
      update_inbound_port "trojan-h2-tls-sb" "$p"
      restartsb && sbshare > /dev/null 2>&1
      blue "Trojan-H2-TLS端口已变更为 $p"
      ;;
    17)
      [[ -z "$port_ss" ]] && red "协议未安装！" && sleep 2 && changeport && return
      local p=$(prompt_new_port "Shadowsocks" "$port_ss")
      update_inbound_port "shadowsocks-sb" "$p"
      restartsb && sbshare > /dev/null 2>&1
      blue "Shadowsocks端口已变更为 $p"
      ;;
    18)
      [[ -z "$port_hy2" ]] && red "协议未安装！" && sleep 2 && changeport && return
      green "1：更换Hysteria 2主端口 (原多端口自动重置删除)"
      green "2：添加Hysteria 2多端口"
      green "3：重置删除Hysteria 2多端口"
      green "0：返回上层"
      readp "请选择【0-3】：" menu
      if [ "$menu" = "1" ]; then
        [ -n "$hy2_ports" ] && hy2deports
        local p=$(prompt_new_port "Hysteria 2" "$port_hy2")
        update_inbound_port "hy2-sb" "$p"
        restartsb && sbshare > /dev/null 2>&1
        blue "Hysteria 2端口已变更为 $p"
      elif [ "$menu" = "2" ]; then
        green "1：添加Hysteria 2范围端口"
        green "2：添加Hysteria 2单端口"
        green "0：返回上层"
        readp "请选择【0-2】：" menu
        port=$port_hy2
        if [ "$menu" = "1" ]; then
          fports && sbshare > /dev/null 2>&1 && changeport
        elif [ "$menu" = "2" ]; then
          fport && sbshare > /dev/null 2>&1 && changeport
        else
          changeport
        fi
      elif [ "$menu" = "3" ]; then
        if [ -n "$hy2_ports" ]; then
          hy2deports && sbshare > /dev/null 2>&1 && yellow "Hysteria 2多端口已删除" && changeport
        else
          sbshare > /dev/null 2>&1 && yellow "Hysteria 2未设置多端口" && changeport
        fi
      else
        changeport
      fi
      ;;
    19)
      [[ -z "$port_tu" ]] && red "协议未安装！" && sleep 2 && changeport && return
      green "1：更换Tuic-v5主端口 (原多端口自动重置删除)"
      green "2：添加Tuic-v5多端口"
      green "3：重置删除Tuic-v5多端口"
      green "0：返回上层"
      readp "请选择【0-3】：" menu
      if [ "$menu" = "1" ]; then
        [ -n "$tu5_ports" ] && tu5deports
        local p=$(prompt_new_port "Tuic-v5" "$port_tu")
        update_inbound_port "tuic5-sb" "$p"
        restartsb && sbshare > /dev/null 2>&1
        blue "Tuic-v5端口已变更为 $p"
      elif [ "$menu" = "2" ]; then
        green "1：添加Tuic-v5范围端口"
        green "2：添加Tuic-v5单端口"
        green "0：返回上层"
        readp "请选择【0-2】：" menu
        port=$port_tu
        if [ "$menu" = "1" ]; then
          fports && sbshare > /dev/null 2>&1 && changeport
        elif [ "$menu" = "2" ]; then
          fport && sbshare > /dev/null 2>&1 && changeport
        else
          changeport
        fi
      elif [ "$menu" = "3" ]; then
        if [ -n "$tu5_ports" ]; then
          tu5deports && sbshare > /dev/null 2>&1 && yellow "Tuic-v5多端口已删除" && changeport
        else
          sbshare > /dev/null 2>&1 && yellow "Tuic-v5未设置多端口" && changeport
        fi
      else
        changeport
      fi
      ;;
    20)
      if [[ -n "$port_an" ]]; then
        local p=$(prompt_new_port "AnyTLS" "$port_an")
        update_inbound_port "anytls-sb" "$p"
        restartsb && sbshare > /dev/null 2>&1
        blue "AnyTLS端口已变更为 $p"
      else
        sb
      fi
      ;;
    21)
      [[ -z "$port_socks" ]] && red "协议未安装！" && sleep 2 && changeport && return
      local p=$(prompt_new_port "Socks" "$port_socks")
      update_inbound_port "socks-sb" "$p"
      restartsb && sbshare > /dev/null 2>&1
      blue "Socks端口已变更为 $p"
      ;;
    *)
      sb
      ;;
  esac
}

# --- Change UUID / VMess Path ---
changeuuid() {
  echo
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
  uuid_vl_re=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vless-reality-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_vl_ws=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vless-ws-tls-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_vl_hu=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vless-hu-tls-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_vm_ws=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vmess-ws-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_vm_ws_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vmess-ws-tls-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_vm_hu_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vmess-hu-tls-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_tr_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "trojan-tls-sb") | .users[0].password // empty' 2>/dev/null | head -n 1)
  uuid_tr_ws_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "trojan-ws-tls-sb") | .users[0].password // empty' 2>/dev/null | head -n 1)
  uuid_tr_hu_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "trojan-hu-tls-sb") | .users[0].password // empty' 2>/dev/null | head -n 1)
  uuid_hy2=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "hy2-sb") | .users[0].password // empty' 2>/dev/null | head -n 1)
  uuid_tu=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "tuic5-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_an=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "anytls-sb") | .users[0].password // empty' 2>/dev/null | head -n 1)
  uuid_vm_tcp=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vmess-tcp-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_vm_http=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vmess-http-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_vm_quic=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vmess-quic-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_vm_h2_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vmess-h2-tls-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_vl_h2=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vless-h2-tls-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  uuid_tr_h2_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "trojan-h2-tls-sb") | .users[0].password // empty' 2>/dev/null | head -n 1)
  uuid_vl_h2_re=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vless-h2-reality-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  socks_username=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "socks-sb") | .users[0].username // empty' 2>/dev/null | head -n 1)
  socks_password=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "socks-sb") | .users[0].password // empty' 2>/dev/null | head -n 1)

  green "当前各已安装协议独立的uuid (密码)："
  [[ -n "$uuid_vl_re" ]] && green "  VLESS-Reality: $uuid_vl_re"
  [[ -n "$uuid_vl_ws" ]] && green "  VLESS-WS-TLS:  $uuid_vl_ws"
  [[ -n "$uuid_vl_hu" ]] && green "  VLESS-HU-TLS:  $uuid_vl_hu"
  [[ -n "$uuid_vm_ws" ]] && green "  VMess-WS:      $uuid_vm_ws"
  [[ -n "$uuid_vm_ws_tls" ]] && green "  VMess-WS-TLS:  $uuid_vm_ws_tls"
  [[ -n "$uuid_vm_hu_tls" ]] && green "  VMess-HU-TLS:  $uuid_vm_hu_tls"
  [[ -n "$uuid_tr_tls" ]] && green "  Trojan-TLS:    $uuid_tr_tls"
  [[ -n "$uuid_tr_ws_tls" ]] && green "  Trojan-WS-TLS: $uuid_tr_ws_tls"
  [[ -n "$uuid_tr_hu_tls" ]] && green "  Trojan-HU-TLS: $uuid_tr_hu_tls"
  [[ -n "$uuid_hy2" ]] && green "  Hysteria 2:    $uuid_hy2"
  [[ -n "$uuid_tu" ]] && green "  Tuic-v5:       $uuid_tu"
  [[ -n "$uuid_an" ]] && green "  AnyTLS:        $uuid_an"
  [[ -n "$uuid_vm_tcp" ]] && green "  VMess-TCP:     $uuid_vm_tcp"
  [[ -n "$uuid_vm_http" ]] && green "  VMess-HTTP:    $uuid_vm_http"
  [[ -n "$uuid_vm_quic" ]] && green "  VMess-QUIC:    $uuid_vm_quic"
  [[ -n "$uuid_vm_h2_tls" ]] && green "  VMess-H2-TLS:  $uuid_vm_h2_tls"
  [[ -n "$uuid_vl_h2" ]] && green "  VLESS-H2-TLS:  $uuid_vl_h2"
  [[ -n "$uuid_tr_h2_tls" ]] && green "  Trojan-H2-TLS: $uuid_tr_h2_tls"
  [[ -n "$uuid_vl_h2_re" ]] && green "  VLESS-H2-Re:   $uuid_vl_h2_re"
  [[ -n "$socks_username" ]] && green "  Socks-User:    $socks_username"
  [[ -n "$socks_password" ]] && green "  Socks-Pass:    $socks_password"

  oldvmpath=$(echo "$clean_json" | jq -r ' (.inbounds[] | select(.tag == "vmess-ws-sb") | .transport.path) // empty')
  if [[ -n "$oldvmpath" ]]; then
    green "Vmess-WS的path路径：$oldvmpath"
  fi
  echo
  yellow "1：自定义/随机重置各协议的uuid (密码)"
  if [[ -n "$oldvmpath" ]]; then
    yellow "2：自定义Vmess-WS的path路径"
  fi
  yellow "0：返回上层"
  readp "请选择【0-2】：" menu
  if [ "$menu" = "1" ]; then
    readp "输入自定义uuid (回车表示随机生成各协议独立uuid)：" menu
    if [ -z "$menu" ]; then
      uuid_vl_re=$("$SBFOLDER/sing-box" generate uuid)
      uuid_vl_ws=$("$SBFOLDER/sing-box" generate uuid)
      uuid_vl_hu=$("$SBFOLDER/sing-box" generate uuid)
      uuid_vm_ws=$("$SBFOLDER/sing-box" generate uuid)
      uuid_vm_ws_tls=$("$SBFOLDER/sing-box" generate uuid)
      uuid_vm_hu_tls=$("$SBFOLDER/sing-box" generate uuid)
      uuid_tr_tls=$("$SBFOLDER/sing-box" generate uuid)
      uuid_tr_ws_tls=$("$SBFOLDER/sing-box" generate uuid)
      uuid_tr_hu_tls=$("$SBFOLDER/sing-box" generate uuid)
      uuid_hy2=$("$SBFOLDER/sing-box" generate uuid)
      uuid_tu=$("$SBFOLDER/sing-box" generate uuid)
      uuid_an=$("$SBFOLDER/sing-box" generate uuid)
      uuid_vm_tcp=$("$SBFOLDER/sing-box" generate uuid)
      uuid_vm_http=$("$SBFOLDER/sing-box" generate uuid)
      uuid_vm_quic=$("$SBFOLDER/sing-box" generate uuid)
      uuid_vm_h2_tls=$("$SBFOLDER/sing-box" generate uuid)
      uuid_vl_h2=$("$SBFOLDER/sing-box" generate uuid)
      uuid_tr_h2_tls=$("$SBFOLDER/sing-box" generate uuid)
      uuid_vl_h2_re=$("$SBFOLDER/sing-box" generate uuid)
      socks_username=$("$SBFOLDER/sing-box" generate uuid)
      socks_password=$("$SBFOLDER/sing-box" generate uuid)
    else
      uuid_vl_re=$menu
      uuid_vl_ws=$menu
      uuid_vl_hu=$menu
      uuid_vm_ws=$menu
      uuid_vm_ws_tls=$menu
      uuid_vm_hu_tls=$menu
      uuid_tr_tls=$menu
      uuid_tr_ws_tls=$menu
      uuid_tr_hu_tls=$menu
      uuid_hy2=$menu
      uuid_tu=$menu
      uuid_an=$menu
      uuid_vm_tcp=$menu
      uuid_vm_http=$menu
      uuid_vm_quic=$menu
      uuid_vm_h2_tls=$menu
      uuid_vl_h2=$menu
      uuid_tr_h2_tls=$menu
      uuid_vl_h2_re=$menu
      socks_username=$menu
      socks_password=$menu
    fi
    for file in $SBFILES; do
      if [ -f "$file" ]; then
        if [[ $(basename "$file") == "sb.json" ]]; then
          jq \
            --arg vl_re "$uuid_vl_re" \
            --arg vl_ws "$uuid_vl_ws" \
            --arg vl_hu "$uuid_vl_hu" \
            --arg vm_ws "$uuid_vm_ws" \
            --arg vm_ws_tls "$uuid_vm_ws_tls" \
            --arg vm_hu_tls "$uuid_vm_hu_tls" \
            --arg tr_tls "$uuid_tr_tls" \
            --arg tr_ws_tls "$uuid_tr_ws_tls" \
            --arg tr_hu_tls "$uuid_tr_hu_tls" \
            --arg hy2 "$uuid_hy2" \
            --arg tu "$uuid_tu" \
            --arg an "$uuid_an" \
            --arg vm_tcp "$uuid_vm_tcp" \
            --arg vm_http "$uuid_vm_http" \
            --arg vm_quic "$uuid_vm_quic" \
            --arg vm_h2 "$uuid_vm_h2_tls" \
            --arg vl_h2 "$uuid_vl_h2" \
            --arg tr_h2 "$uuid_tr_h2_tls" \
            --arg vl_h2_re "$uuid_vl_h2_re" \
            --arg socks_u "$socks_username" \
            --arg socks_p "$socks_password" \
            '.inbounds[] |= (
              if .tag == "vless-reality-sb" then .users[0].uuid = $vl_re
              elif .tag == "vless-ws-tls-sb" then .users[0].uuid = $vl_ws | .transport.path = ("/" + $vl_ws)
              elif .tag == "vless-hu-tls-sb" then .users[0].uuid = $vl_hu | .transport.path = ("/" + $vl_hu)
              elif .tag == "vmess-ws-sb" then .users[0].uuid = $vm_ws | .transport.path = ("/" + $vm_ws)
              elif .tag == "vmess-ws-tls-sb" then .users[0].uuid = $vm_ws_tls | .transport.path = ("/" + $vm_ws_tls)
              elif .tag == "vmess-hu-tls-sb" then .users[0].uuid = $vm_hu_tls | .transport.path = ("/" + $vm_hu_tls)
              elif .tag == "trojan-tls-sb" then .users[0].password = $tr_tls
              elif .tag == "trojan-ws-tls-sb" then .users[0].password = $tr_ws_tls | .transport.path = ("/" + $tr_ws_tls)
              elif .tag == "trojan-hu-tls-sb" then .users[0].password = $tr_hu_tls | .transport.path = ("/" + $tr_hu_tls)
              elif .tag == "hy2-sb" then .users[0].password = $hy2
              elif .tag == "tuic5-sb" then .users[0].uuid = $tu | .users[0].password = $tu
              elif .tag == "anytls-sb" then .users[0].password = $an
              elif .tag == "vmess-tcp-sb" then .users[0].uuid = $vm_tcp
              elif .tag == "vmess-http-sb" then .users[0].uuid = $vm_http
              elif .tag == "vmess-quic-sb" then .users[0].uuid = $vm_quic
              elif .tag == "vmess-h2-tls-sb" then .users[0].uuid = $vm_h2 | .transport.path = ("/" + $vm_h2)
              elif .tag == "vless-h2-tls-sb" then .users[0].uuid = $vl_h2 | .transport.path = ("/" + $vl_h2)
              elif .tag == "trojan-h2-tls-sb" then .users[0].password = $tr_h2 | .transport.path = ("/" + $tr_h2)
              elif .tag == "vless-h2-reality-sb" then .users[0].uuid = $vl_h2_re | .transport.path = ("/" + $vl_h2_re)
              elif .tag == "socks-sb" then .users[0].username = $socks_u | .users[0].password = $socks_p
              else . end
            )' "$file" > /tmp/tmp.json && mv /tmp/tmp.json "$file"
        fi
      fi
    done
    restartsb && sbshare > /dev/null 2>&1
    blue "已确认各协议的uuid (密码)已更新完成！"
  elif [ "$menu" = "2" ]; then
    if [[ -z "$oldvmpath" ]]; then
      red "Vmess-WS协议未安装，无法修改其Path路径！" && sleep 2 && changeuuid
      return
    fi
    readp "输入Vmess-WS of path路径，回车表示不变：" menu
    if [ -n "$menu" ]; then
      vmpath=$menu
      [[ "$vmpath" != /* ]] && vmpath="/$vmpath"
      for file in $SBFILES; do
        if [ -f "$file" ]; then
          jq --arg p "$vmpath" ' (.inbounds[] | select(.tag == "vmess-ws-sb")).transport.path = $p' "$file" > /tmp/tmp.json && mv /tmp/tmp.json "$file"
        fi
      done
      restartsb && sbshare > /dev/null 2>&1
    fi
    blue "已确认Vmess-WS的path路径：$(strip_json_comments "$SBFOLDER/sb.json" | jq -r ' (.inbounds[] | select(.tag == "vmess-ws-sb") | .transport.path) // empty')"
  else
    changeserv
  fi
}

# --- Change IP Priority ---
changeip() {
  v4v6
  chip() {
    jq --arg strat "$rrpip" '
      (.outbounds[]) |= del(.domain_strategy) |
      if (.route.rules | map(select(.action == "resolve")) | length) > 0 then
        .route.rules |= map(if .action == "resolve" then .strategy = $strat | del(.domain_suffix) else . end)
      else
        .route.rules = [{"action": "resolve", "strategy": $strat}] + .route.rules
      end
    ' "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
    restartsb
  }
  readp "1. IPV4优先\n2. IPV6优先\n3. 仅IPV4\n4. 仅IPV6\n请选择：" choose
  if [[ $choose == "1" && -n $v4 ]]; then
    rrpip="prefer_ipv4" && chip && v4_6="IPV4优先出站($showv4)"
  elif [[ $choose == "2" && -n $v6 ]]; then
    rrpip="prefer_ipv6" && chip && v4_6="IPV6优先出站($showv6)"
  elif [[ $choose == "3" && -n $v4 ]]; then
    rrpip="ipv4_only" && chip && v4_6="仅IPV4出站($showv4)"
  elif [[ $choose == "4" && -n $v6 ]]; then
    rrpip="ipv6_only" && chip && v4_6="仅IPV6出站($showv6)"
  else 
    red "当前不存在你选择的IPV4/IPV6地址，或者输入错误" && changeip
  fi
  blue "当前已更换的IP优先级：${v4_6}" && sb
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

test_warp_204() {
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
  local ep_json=$(echo "$clean_json" | jq '.endpoints // []' 2>/dev/null)
  
  if [ -z "$ep_json" ] || [ "$ep_json" = "[]" ]; then
    echo "未配置 (不存在 WireGuard 出站)"
    return
  fi

  local sb_bin=""
  if [ -f "$SBFOLDER/sing-box" ]; then
    sb_bin="$SBFOLDER/sing-box"
  elif command -v sing-box >/dev/null 2>&1; then
    sb_bin="sing-box"
  elif [ -f "/var/Sing-Box-DuolaD/sing-box" ]; then
    sb_bin="/var/Sing-Box-DuolaD/sing-box"
  fi

  if [ -z "$sb_bin" ]; then
    echo "未知 (未找到 sing-box 内核)"
    return
  fi

  cat <<EOF > /tmp/sb_warp_test.json
{
  "log": { "disabled": true },
  "inbounds": [
    {
      "type": "socks",
      "tag": "socks-test",
      "listen": "127.0.0.1",
      "listen_port": 49151
    }
  ],
  "endpoints": $ep_json,
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [
      {
        "outbound": "warp-out"
      }
    ]
  }
}
EOF

  "$sb_bin" run -c /tmp/sb_warp_test.json >/dev/null 2>&1 &
  local test_pid=$!
  sleep 1.2

  local http_code=$(curl -s4m4 -o /dev/null -w "%{http_code}" --socks5 127.0.0.1:49151 https://www.google.com/generate_204 2>/dev/null)
  if [ "$http_code" != "204" ]; then
    http_code=$(curl -s6m4 -o /dev/null -w "%{http_code}" --socks5 127.0.0.1:49151 https://www.google.com/generate_204 2>/dev/null)
  fi

  kill -9 $test_pid >/dev/null 2>&1
  wait $test_pid 2>/dev/null
  rm -f /tmp/sb_warp_test.json

  if [ "$http_code" = "204" ]; then
    echo "HTTP 204 (连通成功)"
  else
    echo "失败 (HTTP ${http_code:-000} / 无法连通)"
  fi
}

changewg() {
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
  wgipv6=$(echo "$clean_json" | jq -r '.endpoints[]? | select(.type == "wireguard") | .address[1] | split("/")[0]' 2>/dev/null)
  wgprkey=$(echo "$clean_json" | jq -r '.endpoints[]? | select(.type == "wireguard") | .private_key' 2>/dev/null)
  wgres=$(echo "$clean_json" | jq -c '.endpoints[]? | select(.type == "wireguard") | .peers[0].reserved' 2>/dev/null)
  wgip=$(echo "$clean_json" | jq -r '.endpoints[]? | select(.type == "wireguard") | .peers[0].address' 2>/dev/null)
  wgpo=$(echo "$clean_json" | jq -r '.endpoints[]? | select(.type == "wireguard") | .peers[0].port' 2>/dev/null)

  echo
  green "当前warp-wireguard可更换的参数如下："
  green "Private_key私钥：$wgprkey"
  green "IPV6地址：$wgipv6"
  green "Reserved值：$wgres"
  green "对端IP：$wgip:$wgpo"
  echo
  yellow "1：更换warp-wireguard账户"
  yellow "2：更换/优选warp-wireguard对端IP与端口 (不建议随意改动)"
  yellow "3：测试WireGuard出站连通性 (204响应)"
  yellow "0：返回上层"
  readp "请选择【0-3】：" menu
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
    
    # Use JQ for clean and robust updates on sb.json
    jq --arg key "$menu_key" --arg ip "$menu_ip/128" --argjson res "[$menu_res]" \
       '(.endpoints[]? | select(.type == "wireguard")) |= (.private_key = $key | .address[1] = $ip | .peers[0].reserved = $res)' \
       "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
        
    restartsb
    green "设置结束"
  elif [ "$menu" = "2" ]; then
    echo
    red "⚠️ 提示：对端 IP/Endpoint 为 WARP 连接通讯的关键入口，非特殊网络需求不建议随意改动！"
    echo
    local check_v4=$(curl -s4m3 icanhazip.com -k)
    local check_v6=""
    if ip addr show 2>/dev/null | grep -q "inet6 [23]"; then
      check_v6=$(curl -s6m3 icanhazip.com -k)
    fi

    local net_type="unknown"
    local opt_v4_idx=""
    local opt_v6_idx=""
    local max_idx=2

    if [ -n "$check_v4" ] && [ -n "$check_v6" ]; then
      net_type="双栈网络 (IPv4 + IPv6)"
      opt_v4_idx="3"
      opt_v6_idx="4"
      max_idx=4
    elif [ -n "$check_v4" ]; then
      net_type="IPv4 Only"
      opt_v4_idx="3"
      max_idx=3
    elif [ -n "$check_v6" ]; then
      net_type="IPv6 Only"
      opt_v6_idx="3"
      max_idx=3
    else
      net_type="未识别 (默认允许双栈切换)"
      opt_v4_idx="3"
      opt_v6_idx="4"
      max_idx=4
    fi

    green "网络检测结果：当前服务器为【$net_type】"
    echo
    yellow "1：手动输入自定义对端 IP/域名 和 端口"
    yellow "2：自动获取优选warp-wireguard对端IP"
    if [ -n "$opt_v4_idx" ]; then
      yellow "${opt_v4_idx}：更换至 IPv4 Endpoint (162.159.192.1)"
    fi
    if [ -n "$opt_v6_idx" ]; then
      yellow "${opt_v6_idx}：更换至 IPv6 Endpoint (2606:4700:d0::a29f:c001)"
    fi
    yellow "0：返回上层"
    readp "请选择【0-${max_idx}】：" sub_menu

    if [ "$sub_menu" = "1" ]; then
      readp "输入自定义对端IP或域名 [当前: $wgip] (回车保持不变)：" menu_endip
      [ -z "$menu_endip" ] && menu_endip=$wgip
      readp "输入自定义对端端口Port [当前: ${wgpo:-2408}] (回车保持不变)：" menu_endpo
      [ -z "$menu_endpo" ] && menu_endpo=${wgpo:-2408}
      
      jq --arg ip "$menu_endip" --argjson port "$menu_endpo" \
         '(.endpoints[]? | select(.type == "wireguard")) |= (.peers[0].address = $ip | .peers[0].port = $port)' \
         "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
      restartsb
      green "warp-wireguard对端IP/Endpoint设置结束"
    elif [ "$sub_menu" = "2" ]; then
      green "正在获取优选对端IP，请稍等..."
      if [ -z "$(curl -s4m5 icanhazip.com -k)" ]; then
        curl -sSL https://gitlab.com/rwkgyg/CFwarp/raw/main/point/endip.sh -o /tmp/endip.sh && chmod +x /tmp/endip.sh && (echo -e "1\n2\n") | bash /tmp/endip.sh > /dev/null 2>&1
        nwgip=$(awk -F, 'NR==2 {print $1}' /root/result.csv 2>/dev/null | grep -o '\[.*\]' | tr -d '[]')
        nwgpo=$(awk -F, 'NR==2 {print $1}' /root/result.csv 2>/dev/null | awk -F "]" '{print $2}' | tr -d ':')
      else
        curl -sSL https://gitlab.com/rwkgyg/CFwarp/raw/main/point/endip.sh -o /tmp/endip.sh && chmod +x /tmp/endip.sh && (echo -e "1\n1\n") | bash /tmp/endip.sh > /dev/null 2>&1
        nwgip=$(awk -F, 'NR==2 {print $1}' /root/result.csv 2>/dev/null | awk -F: '{print $1}')
        nwgpo=$(awk -F, 'NR==2 {print $1}' /root/result.csv 2>/dev/null | awk -F: '{print $2}')
      fi
      rm -f /tmp/endip.sh
      if [ -n "$nwgip" ] && [ -n "$nwgpo" ]; then
        jq --arg ip "$nwgip" --argjson port "$nwgpo" \
           '(.endpoints[]? | select(.type == "wireguard")) |= (.peers[0].address = $ip | .peers[0].port = $port)' \
           "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
        restartsb
        green "自动优选 Warp 对端 IP 成功：$nwgip:$nwgpo"
      else
        red "获取优选对端 IP 失败，未更改配置"
      fi
    elif [ -n "$opt_v4_idx" ] && [ "$sub_menu" = "$opt_v4_idx" ]; then
      local target_port=${wgpo:-2408}
      jq --arg ip "162.159.192.1" --argjson port "$target_port" \
         '(.endpoints[]? | select(.type == "wireguard")) |= (.peers[0].address = $ip | .peers[0].port = $port)' \
         "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
      restartsb
      green "已成功更改为 IPv4 Endpoint：162.159.192.1:$target_port (端口保持不变)"
    elif [ -n "$opt_v6_idx" ] && [ "$sub_menu" = "$opt_v6_idx" ]; then
      local target_port=${wgpo:-2408}
      jq --arg ip "2606:4700:d0::a29f:c001" --argjson port "$target_port" \
         '(.endpoints[]? | select(.type == "wireguard")) |= (.peers[0].address = $ip | .peers[0].port = $port)' \
         "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
      restartsb
      green "已成功更改为 IPv6 Endpoint：[2606:4700:d0::a29f:c001]:$target_port (端口保持不变)"
    else
      changewg
    fi
  elif [ "$menu" = "3" ]; then
    echo
    green "正在进行 WireGuard 出站连通性测试 (https://www.google.com/generate_204)..."
    local test_res=$(test_warp_204)
    if [[ "$test_res" == *"204"* ]]; then
      green "测试结果：$test_res"
    else
      red "测试结果：$test_res"
    fi
    echo
    readp "按回车键返回..." temp_input
    changewg
  else
    changeserv
  fi
}

# --- Change Reality Domain / Acme Certificate ---
changeym() {
  result_vl_vm_hy_tu
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
  
  echo
  green "证书及域名管理与协议增删："
  echo
  green "1：新增协议"
  green "2：修改现有协议配置"
  green "3：SSL 证书设置"
  green "4：删除协议"
  green "0：返回上层"
  readp "请选择【0-4】：" menu
  
  if [ "$menu" = "1" ]; then
    add_protocol
    changeym
  elif [ "$menu" = "2" ]; then
    modify_protocol_config
    changeym
  elif [ "$menu" = "3" ]; then
    ssl_certificate_settings
    changeym
  elif [ "$menu" = "4" ]; then
    delete_protocol
    changeym
  else
    sb
  fi
}

config_apply_cert() {
  local target_type="$1"
  echo "$target_type" > /var/Sing-Box-DuolaD/cert_type.log
  
  if [[ "$target_type" == "self" ]]; then
    cp -f /var/Sing-Box-DuolaD/self_cert.pem /var/Sing-Box-DuolaD/cert.pem
    cp -f /var/Sing-Box-DuolaD/self_private.key /var/Sing-Box-DuolaD/private.key
  elif [[ "$target_type" == "ip" ]]; then
    cp -f /var/Sing-Box-DuolaD/ip_cert.pem /var/Sing-Box-DuolaD/cert.pem
    cp -f /var/Sing-Box-DuolaD/ip_private.key /var/Sing-Box-DuolaD/private.key
  elif [[ "$target_type" == "domain" ]]; then
    cp -f /var/Sing-Box-DuolaD/domain_cert.pem /var/Sing-Box-DuolaD/cert.pem
    cp -f /var/Sing-Box-DuolaD/domain_private.key /var/Sing-Box-DuolaD/private.key
  fi
  
  cp -f /var/Sing-Box-DuolaD/cert.pem "$SBFOLDER/cert.pem" 2>/dev/null
  cp -f /var/Sing-Box-DuolaD/private.key "$SBFOLDER/private.key" 2>/dev/null
  
  write_caddyfile
  restartsb
  sbshare > /dev/null 2>&1
  blue "已成功切换并应用生效证书为：$target_type"
  sleep 2
}

ssl_deploy_menu() {
  echo
  green "部署/更新证书："
  echo "1：部署/更新 自签证书"
  echo "2：部署/更新 纯 IP 证书"
  echo "3：部署/更新 域名证书"
  echo "0：返回上层"
  readp "请选择【0-3】：" opt
  case "$opt" in
    1)
      cert_type="self"
      local cur_self_dom=$(get_self_domain)
      local new_self_dom="$cur_self_dom"
      if [[ -s "/var/Sing-Box-DuolaD/self_cert.pem" && -s "/var/Sing-Box-DuolaD/self_private.key" ]]; then
        echo -e "当前自签证书伪装域名为: ${cyan}$cur_self_dom${plain}"
        readp "是否需要修改自签证书伪装域名？[y/N] (默认不修改) ：" change_dom_choice
        if [[ "$change_dom_choice" =~ ^[Yy]$ ]]; then
          readp "请输入新的自签证书伪装域名 (回车使用 $cur_self_dom)：" input_self_dom
          new_self_dom=${input_self_dom:-$cur_self_dom}
        fi
      else
        readp "请输入自签证书伪装域名 (回车默认使用 dl.delivery.mp.microsoft.com)：" input_self_dom
        new_self_dom=${input_self_dom:-dl.delivery.mp.microsoft.com}
      fi
      mkdir -p /var/Sing-Box-DuolaD
      echo "$new_self_dom" > /var/Sing-Box-DuolaD/self_domain.log
      
      setup_caddy_cert
      cp -f /var/Sing-Box-DuolaD/cert.pem /var/Sing-Box-DuolaD/self_cert.pem
      cp -f /var/Sing-Box-DuolaD/private.key /var/Sing-Box-DuolaD/self_private.key
      config_apply_cert "self"
      
      local check_self_usage=false
      local proto_tags=("vless-ws-tls-sb" "vless-hu-tls-sb" "vless-h2-tls-sb" "vmess-ws-tls-sb" "vmess-hu-tls-sb" "vmess-h2-tls-sb" "trojan-ws-tls-sb" "trojan-hu-tls-sb" "trojan-h2-tls-sb")
      local global_cert_type=$(cat /var/Sing-Box-DuolaD/cert_type.log 2>/dev/null || echo "self")
      local tag
      for tag in "${proto_tags[@]}"; do
        if [[ -f "$SBFOLDER/conf/${tag}.json" ]]; then
          local p_cert=$(grep -w "^${tag}:" /var/Sing-Box-DuolaD/proto_certs.log 2>/dev/null | cut -d: -f2)
          [[ -z "$p_cert" ]] && p_cert="$global_cert_type"
          [[ "$p_cert" == "self" ]] && check_self_usage=true
        fi
      done
      local direct_tags=("trojan-tls-sb" "hy2-sb" "tuic5-sb" "anytls-sb")
      for tag in "${direct_tags[@]}"; do
        local f_conf="$SBFOLDER/conf/${tag}.json"
        if [[ -f "$f_conf" ]]; then
          local cpath=$(jq -r '.inbounds[0].tls.certificate_path // empty' "$f_conf")
          if [[ "$cpath" == "/var/Sing-Box-DuolaD/self_cert.pem" || ("$cpath" == "/var/Sing-Box-DuolaD/cert.pem" && "$global_cert_type" == "self") ]]; then
            check_self_usage=true
          fi
        fi
      done
      if $check_self_usage; then
        yellow "\n提示：自签证书及其密钥指纹已更新，所有使用自签证书的协议需要重新导出并更新客户端代理配置信息才能正常连接！"
        sleep 3
      fi
      ;;
    2)
      cert_type="ip"
      rm -f /var/Sing-Box-DuolaD/ip_cert_mode.log
      select_ip_cert_mode
      setup_caddy_cert
      if [[ "$cert_type" == "ip" ]]; then
        cp -f /var/Sing-Box-DuolaD/cert.pem /var/Sing-Box-DuolaD/ip_cert.pem
        cp -f /var/Sing-Box-DuolaD/private.key /var/Sing-Box-DuolaD/ip_private.key
        config_apply_cert "ip"
      fi
      ;;
    3)
      cert_type="domain"
      ym_domain=""
      rm -f /var/Sing-Box-DuolaD/acme_provider.log /var/Sing-Box-DuolaD/dns_api.log
      
      echo
      while true; do
        readp "请输入解析或需要申请证书的域名 (如 sub.domain.com 或 *.domain.com)：" ym_domain
        if [[ -z "$ym_domain" ]]; then
          red "域名不能为空，请重新输入！"
        else
          break
        fi
      done

      local is_wildcard=false
      if [[ "$ym_domain" == \*.* ]]; then
        is_wildcard=true
      fi

      local acme_mode_choice=""
      if $is_wildcard; then
        echo
        yellow "检测到您输入的是泛域名 ($ym_domain)！"
        blue "根据 ACME 协议规范，泛域名证书强制要求使用 DNS API 验证模式。"
        acme_mode_choice="2"
      else
        echo
        green "请选择域名证书验证模式："
        echo "1：HTTP 80 端口 / Caddy 反代验证模式 (推荐，零 API 密钥配置，默认)"
        echo "2：DNS API 验证模式 (需配置 Cloudflare / DNSPod / 阿里云 API 密钥)"
        readp "请选择【1-2】(默认回车选择 1)：" acme_mode_choice
        acme_mode_choice=${acme_mode_choice:-1}
      fi

      if [[ "$acme_mode_choice" == "2" ]]; then
        echo
        green "请选择托管域名解析服务商："
        echo "1：Cloudflare"
        echo "2：腾讯云 DNSPod"
        echo "3：阿里云 Aliyun"
        readp "请选择【1-3】：" dns_prov_choice
        local dns_provider=""
        case "$dns_prov_choice" in
          1)
            dns_provider="dns_cf"
            yellow "请选择 Cloudflare DNS API 验证方式："
            yellow "1. API Token (推荐)"
            yellow "2. Global API Key"
            readp "请选择【1-2】(默认1)：" cf_choice
            cf_choice=${cf_choice:-1}
            if [[ "$cf_choice" == "1" ]]; then
              readp "请输入 Cloudflare Account ID (账户ID)：" cf_acc_id
              readp "请输入 Cloudflare DNS API Token (API令牌)：" cf_token
              mkdir -p /var/Sing-Box-DuolaD
              echo "dns_cf|token|$cf_acc_id|$cf_token" > /var/Sing-Box-DuolaD/dns_api.log
            else
              readp "请输入登录 Cloudflare 的注册邮箱地址：" cf_email
              readp "请复制 Cloudflare 的 Global API Key：" cf_key
              mkdir -p /var/Sing-Box-DuolaD
              echo "dns_cf|key|$cf_email|$cf_key" > /var/Sing-Box-DuolaD/dns_api.log
            fi
            ;;
          2)
            dns_provider="dns_dp"
            readp "请复制腾讯云 DNSPod 的 DP_Id：" dp_id
            readp "请复制腾讯云 DNSPod 的 DP_Key：" dp_key
            mkdir -p /var/Sing-Box-DuolaD
            echo "dns_dp|$dp_id|$dp_key" > /var/Sing-Box-DuolaD/dns_api.log
            ;;
          3)
            dns_provider="dns_ali"
            readp "请复制阿里云 Aliyun 的 Ali_Key：" ali_key
            readp "请复制阿里云 Aliyun 的 Ali_Secret：" ali_secret
            mkdir -p /var/Sing-Box-DuolaD
            echo "dns_ali|$ali_key|$ali_secret" > /var/Sing-Box-DuolaD/dns_api.log
            ;;
          *)
            red "输入错误，取消申请！"
            return
            ;;
        esac
        echo "$dns_provider" > /var/Sing-Box-DuolaD/acme_provider.log
      else
        local resolved_ip=$(dig +short "$ym_domain" 2>/dev/null || nslookup "$ym_domain" 2>/dev/null | awk '/Address:/ {print $2}' | tail -n 1)
        if [[ -z "$resolved_ip" ]]; then
          resolved_ip=$(ping -c 1 -W 2 "$ym_domain" 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
        fi
        local vps_ip=$(curl -s4 ip.sb || curl -s6 ip.sb)
        if [[ "$resolved_ip" != "$vps_ip" ]]; then
          yellow "警告：域名解析IP ($resolved_ip) 与本机IP ($vps_ip) 不符！"
          readp "是否强行继续申请？[y/N] (默认不继续) ：" force_req
          if [[ "$force_req" =~ ^[Yy]$ ]]; then
            :
          else
            return
          fi
        fi
      fi
      mkdir -p /var/Sing-Box-DuolaD
      echo "$ym_domain" > /var/Sing-Box-DuolaD/domain.log
      setup_caddy_cert
      if [[ "$cert_type" == "domain" ]]; then
        cp -f /var/Sing-Box-DuolaD/cert.pem /var/Sing-Box-DuolaD/domain_cert.pem
        cp -f /var/Sing-Box-DuolaD/private.key /var/Sing-Box-DuolaD/domain_private.key
        config_apply_cert "domain"
      fi
      ;;
    *)
      return
      ;;
  esac
}

ssl_uninstall_menu() {
  echo
  green "卸载证书："
  echo "1：卸载 自签证书"
  echo "2：卸载 纯 IP 证书"
  echo "3：卸载 域名证书"
  echo "0：返回上层"
  readp "请选择【0-3】：" opt
  
  local target_type=""
  local target_name=""
  case "$opt" in
    1) target_type="self"; target_name="自签证书" ;;
    2) target_type="ip"; target_name="纯 IP 证书" ;;
    3) target_type="domain"; target_name="域名证书" ;;
    *) return ;;
  esac

  local cert_file="/var/Sing-Box-DuolaD/${target_type}_cert.pem"
  if [[ ! -s "$cert_file" ]]; then
    red "该证书 ($target_name) 未部署，无需卸载！" && sleep 2
    return
  fi

  local proto_names=("VLESS-Reality" "VLESS-WS-TLS" "VLESS-HTTPUpgrade-TLS" "VLESS-H2-TLS" "VLESS-HTTP2-REALITY" "VMess-WS" "VMess-WS-TLS" "VMess-HTTPUpgrade-TLS" "VMess-TCP" "VMess-HTTP" "VMess-QUIC" "VMess-H2-TLS" "Trojan-TLS" "Trojan-WS-TLS" "Trojan-HTTPUpgrade-TLS" "Trojan-H2-TLS" "Shadowsocks" "Hysteria 2" "Tuic-v5" "AnyTLS" "Socks")
  local proto_tags=("vless-reality-sb" "vless-ws-tls-sb" "vless-hu-tls-sb" "vless-h2-tls-sb" "vless-h2-reality-sb" "vmess-ws-sb" "vmess-ws-tls-sb" "vmess-hu-tls-sb" "vmess-tcp-sb" "vmess-http-sb" "vmess-quic-sb" "vmess-h2-tls-sb" "trojan-tls-sb" "trojan-ws-tls-sb" "trojan-hu-tls-sb" "trojan-h2-tls-sb" "shadowsocks-sb" "hy2-sb" "tuic5-sb" "anytls-sb" "socks-sb")

  local global_cert_type=$(cat /var/Sing-Box-DuolaD/cert_type.log 2>/dev/null || echo "self")
  local affected_protocols=()

  local i
  for ((i=0; i<${#proto_names[@]}; i++)); do
    local tag="${proto_tags[$i]}"
    local name="${proto_names[$i]}"
    local file="$SBFOLDER/conf/${tag}.json"
    if [[ -f "$file" ]]; then
      local bound_cert=""
      if [[ "$tag" == "vless-ws-tls-sb" || "$tag" == "vless-hu-tls-sb" || "$tag" == "vless-h2-tls-sb" || \
            "$tag" == "vmess-ws-tls-sb" || "$tag" == "vmess-hu-tls-sb" || "$tag" == "vmess-h2-tls-sb" || \
            "$tag" == "trojan-ws-tls-sb" || "$tag" == "trojan-hu-tls-sb" || "$tag" == "trojan-h2-tls-sb" ]]; then
        bound_cert=$(grep -w "^${tag}:" /var/Sing-Box-DuolaD/proto_certs.log 2>/dev/null | cut -d: -f2)
        [[ -z "$bound_cert" ]] && bound_cert="$global_cert_type"
      elif [[ "$tag" == "trojan-tls-sb" || "$tag" == "hy2-sb" || "$tag" == "tuic5-sb" || "$tag" == "anytls-sb" ]]; then
        local cpath=$(jq -r '.inbounds[0].tls.certificate_path // empty' "$file")
        if [[ "$cpath" == "/var/Sing-Box-DuolaD/${target_type}_cert.pem" ]]; then
          bound_cert="$target_type"
        elif [[ "$cpath" == "/var/Sing-Box-DuolaD/cert.pem" || "$cpath" == "$SBFOLDER/cert.pem" ]]; then
          bound_cert="$global_cert_type"
        fi
      fi

      if [[ "$bound_cert" == "$target_type" ]]; then
        affected_protocols+=("$name")
      fi
    fi
  done

  if [[ ${#affected_protocols[@]} -gt 0 ]]; then
    red "\n无法卸载！检测到以下依赖该证书 ($target_name) 的运行中协议："
    for name in "${affected_protocols[@]}"; do
      yellow " - $name"
    done
    yellow "\n请先在【修改现有协议配置】或【切换当前全部协议依赖证书】中将这些协议切换至其它证书，再进行卸载！"
    sleep 4
    return
  fi

  readp "确认卸载 $target_name 吗？[y/N] (默认不卸载)：" confirm_uninst
  if [[ ! "$confirm_uninst" =~ ^[Yy]$ ]]; then
    return
  fi

  rm -f "/var/Sing-Box-DuolaD/${target_type}_cert.pem" "/var/Sing-Box-DuolaD/${target_type}_private.key"
  if [[ "$target_type" == "ip" ]]; then
    local server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null || curl -s4 ip.sb)
    if command -v ~/.acme.sh/acme.sh &>/dev/null; then
      ~/.acme.sh/acme.sh --remove -d "$server_ip" >/dev/null 2>&1
    fi
  elif [[ "$target_type" == "domain" ]]; then
    local ym_domain=$(cat /var/Sing-Box-DuolaD/domain.log 2>/dev/null)
    if [[ -n "$ym_domain" ]] && command -v ~/.acme.sh/acme.sh &>/dev/null; then
      ~/.acme.sh/acme.sh --remove -d "$ym_domain" >/dev/null 2>&1
    fi
  fi

  blue "\n证书 $target_name 已成功卸载清理！"
  sleep 2
}

ssl_preset_default_menu() {
  echo
  green "切换预设默认依赖证书："
  yellow "说明：此选项将对后续新增的协议生效，对当前已有的协议不生效。"
  echo
  echo "1：后续默认使用 自签证书"
  echo "2：后续默认使用 纯 IP 证书"
  echo "3：后续默认使用 域名证书"
  echo "0：返回上层"
  readp "请选择【0-3】：" opt
  
  local target_type=""
  local target_name=""
  case "$opt" in
    1) target_type="self"; target_name="自签证书" ;;
    2) target_type="ip"; target_name="纯 IP 证书" ;;
    3) target_type="domain"; target_name="域名证书" ;;
    *) return ;;
  esac

  if [[ ! -s "/var/Sing-Box-DuolaD/${target_type}_cert.pem" || ! -s "/var/Sing-Box-DuolaD/${target_type}_private.key" ]]; then
    red "所选证书类型 ($target_name) 未部署！请先进行部署。" && sleep 2
    return
  fi

  readp "确认将后续新增协议的默认证书切换为 $target_name 吗？[y/N] (默认不切换)：" confirm_opt
  if [[ ! "$confirm_opt" =~ ^[Yy]$ ]]; then
    return
  fi

  echo "$target_type" > /var/Sing-Box-DuolaD/cert_type.log
  blue "预设默认依赖证书已成功切换为：$target_name"
  sleep 2
}

ssl_switch_all_protocols_menu() {
  echo
  green "切换当前全部协议依赖证书："
  yellow "说明：此选项将对当前已有的所有协议生效。"
  echo
  echo "1：将所有现有协议证书切换至 自签证书"
  echo "2：将所有现有协议证书切换至 纯 IP 证书"
  echo "3：将所有现有协议证书切换至 域名证书"
  echo "0：返回上层"
  readp "请选择【0-3】：" opt

  local target_type=""
  local target_name=""
  case "$opt" in
    1) target_type="self"; target_name="自签证书" ;;
    2) target_type="ip"; target_name="纯 IP 证书" ;;
    3) target_type="domain"; target_name="域名证书" ;;
    *) return ;;
  esac

  if [[ ! -s "/var/Sing-Box-DuolaD/${target_type}_cert.pem" || ! -s "/var/Sing-Box-DuolaD/${target_type}_private.key" ]]; then
    red "所选证书类型 ($target_name) 未部署！请先进行部署。" && sleep 2
    return
  fi

  readp "确认将所有现有协议的证书切换为 $target_name 吗？[y/N] (默认不切换)：" confirm_opt
  if [[ ! "$confirm_opt" =~ ^[Yy]$ ]]; then
    return
  fi

  local proto_tags=("vless-ws-tls-sb" "vless-hu-tls-sb" "vless-h2-tls-sb" "vmess-ws-tls-sb" "vmess-hu-tls-sb" "vmess-h2-tls-sb" "trojan-ws-tls-sb" "trojan-hu-tls-sb" "trojan-h2-tls-sb")
  touch /var/Sing-Box-DuolaD/proto_certs.log
  local tag
  for tag in "${proto_tags[@]}"; do
    sed -i "/^${tag}:/d" /var/Sing-Box-DuolaD/proto_certs.log
    echo "${tag}:${target_type}" >> /var/Sing-Box-DuolaD/proto_certs.log
  done

  local direct_tags=("trojan-tls-sb" "hy2-sb" "tuic5-sb" "anytls-sb")
  for tag in "${direct_tags[@]}"; do
    local f_conf="$SBFOLDER/conf/${tag}.json"
    if [[ -f "$f_conf" ]]; then
      local cpath="/var/Sing-Box-DuolaD/${target_type}_cert.pem"
      local kpath="/var/Sing-Box-DuolaD/${target_type}_private.key"
      jq --arg cert "$cpath" --arg key "$kpath" \
         '.inbounds[0].tls.certificate_path = $cert | .inbounds[0].tls.key_path = $key' \
         "$f_conf" > /tmp/tmp.json && mv /tmp/tmp.json "$f_conf"
    fi
  done

  config_apply_cert "$target_type"
  blue "\n所有现有协议证书已成功切换至：$target_name"
  yellow "提示：证书配置已变更，请重新导出并更新客户端的代理配置信息，以确保正常连接！"
  sleep 3
}

ssl_certificate_settings() {
  echo
  green "SSL 证书管理设置："
  echo
  
  local has_self=false
  local has_ip=false
  local has_domain=false
  
  if [[ -s "/var/Sing-Box-DuolaD/self_cert.pem" && -s "/var/Sing-Box-DuolaD/self_private.key" ]]; then
    has_self=true
  fi
  
  if [[ -s "/var/Sing-Box-DuolaD/cert.pem" && -s "/var/Sing-Box-DuolaD/private.key" ]]; then
    local cert_type_log=$(cat /var/Sing-Box-DuolaD/cert_type.log 2>/dev/null || echo "self")
    if [[ "$cert_type_log" == "self" ]]; then
      if ! $has_self; then
        cp -f /var/Sing-Box-DuolaD/cert.pem /var/Sing-Box-DuolaD/self_cert.pem
        cp -f /var/Sing-Box-DuolaD/private.key /var/Sing-Box-DuolaD/self_private.key
        has_self=true
      fi
    elif [[ "$cert_type_log" == "ip" ]]; then
      if ! $has_ip; then
        cp -f /var/Sing-Box-DuolaD/cert.pem /var/Sing-Box-DuolaD/ip_cert.pem
        cp -f /var/Sing-Box-DuolaD/private.key /var/Sing-Box-DuolaD/ip_private.key
        has_ip=true
      fi
    elif [[ "$cert_type_log" == "domain" ]]; then
      if ! $has_domain; then
        cp -f /var/Sing-Box-DuolaD/cert.pem /var/Sing-Box-DuolaD/domain_cert.pem
        cp -f /var/Sing-Box-DuolaD/private.key /var/Sing-Box-DuolaD/domain_private.key
        has_domain=true
      fi
    fi
  fi
  
  if [[ -s "/var/Sing-Box-DuolaD/ip_cert.pem" && -s "/var/Sing-Box-DuolaD/ip_private.key" ]]; then
    has_ip=true
  fi
  if [[ -s "/var/Sing-Box-DuolaD/domain_cert.pem" && -s "/var/Sing-Box-DuolaD/domain_private.key" ]]; then
    has_domain=true
  fi

  local active_type="未知"
  if [[ -f "/var/Sing-Box-DuolaD/cert_type.log" ]]; then
    local ctype=$(cat /var/Sing-Box-DuolaD/cert_type.log)
    if [[ "$ctype" == "self" ]]; then
      active_type="自签证书"
    elif [[ "$ctype" == "ip" ]]; then
      active_type="纯 IP 证书"
    elif [[ "$ctype" == "domain" ]]; then
      active_type="域名证书"
    fi
  fi

  echo -e "当前设备已部署的证书状况："
  if $has_self; then
    echo -e " - ${green}自签证书${plain}: ${green}已部署${plain} (伪装域名: $(get_self_domain))"
  else
    echo -e " - ${green}自签证书${plain}: ${yellow}未部署${plain}"
  fi
  
  if $has_ip; then
    local ip_val=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null || curl -s4 ip.sb)
    echo -e " - ${green}纯 IP 证书${plain}: ${green}已部署${plain} (IP: $ip_val)"
  else
    echo -e " - ${green}纯 IP 证书${plain}: ${yellow}未部署${plain}"
  fi
  
  if $has_domain; then
    local dm_val=$(cat /var/Sing-Box-DuolaD/domain.log 2>/dev/null)
    echo -e " - ${green}域名证书${plain}: ${green}已部署${plain} (域名: ${dm_val:-未知})"
  else
    echo -e " - ${green}域名证书${plain}: ${yellow}未部署${plain}"
  fi
  echo -e "当前预设默认依赖证书类型: ${cyan}$active_type${plain}"
  echo

  echo "1：部署/更新证书"
  echo "2：卸载证书"
  echo "3：切换预设默认依赖证书"
  echo "4：切换当前全部协议依赖证书"
  echo "0：返回上层"
  readp "请选择【0-4】：" main_opt

  case "$main_opt" in
    1) ssl_deploy_menu; ssl_certificate_settings ;;
    2) ssl_uninstall_menu; ssl_certificate_settings ;;
    3) ssl_preset_default_menu; ssl_certificate_settings ;;
    4) ssl_switch_all_protocols_menu; ssl_certificate_settings ;;
    *) return ;;
  esac
}

modify_protocol_config() {
  result_vl_vm_hy_tu
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")

  local proto_names=("VLESS-Reality" "VLESS-WS-TLS" "VLESS-HTTPUpgrade-TLS" "VLESS-H2-TLS" "VLESS-HTTP2-REALITY" "VMess-WS" "VMess-WS-TLS" "VMess-HTTPUpgrade-TLS" "VMess-TCP" "VMess-HTTP" "VMess-QUIC" "VMess-H2-TLS" "Trojan-TLS" "Trojan-WS-TLS" "Trojan-HTTPUpgrade-TLS" "Trojan-H2-TLS" "Shadowsocks" "Hysteria 2" "Tuic-v5" "AnyTLS" "Socks")
  local proto_tags=("vless-reality-sb" "vless-ws-tls-sb" "vless-hu-tls-sb" "vless-h2-tls-sb" "vless-h2-reality-sb" "vmess-ws-sb" "vmess-ws-tls-sb" "vmess-hu-tls-sb" "vmess-tcp-sb" "vmess-http-sb" "vmess-quic-sb" "vmess-h2-tls-sb" "trojan-tls-sb" "trojan-ws-tls-sb" "trojan-hu-tls-sb" "trojan-h2-tls-sb" "shadowsocks-sb" "hy2-sb" "tuic5-sb" "anytls-sb" "socks-sb")
  local proto_vars=("vl_re" "vl_ws_tls" "vl_hu_tls" "vl_h2_tls" "vl_h2_re" "vm_ws" "vm_ws_tls" "vm_hu_tls" "vm_tcp" "vm_http" "vm_quic" "vm_h2_tls" "tr_tls" "tr_ws_tls" "tr_hu_tls" "tr_h2_tls" "ss" "hy2" "tu" "an" "socks")

  local active_names=()
  local active_tags=()
  local active_vars=()
  
  local i
  for ((i=0; i<${#proto_names[@]}; i++)); do
    local tag="${proto_tags[$i]}"
    local var="${proto_vars[$i]}"
    if [[ -f "$SBFOLDER/conf/${tag}.json" ]]; then
      active_names+=("${proto_names[$i]}")
      active_tags+=("$tag")
      active_vars+=("$var")
    fi
  done

  if [[ ${#active_names[@]} -eq 0 ]]; then
    red "当前没有安装任何协议，无法修改配置！" && sleep 2
    return
  fi

  echo
  green "请选择要修改配置的协议："
  for ((i=0; i<${#active_names[@]}; i++)); do
    echo -e "$((i+1))：${active_names[$i]}"
  done
  echo "0：返回上层"
  readp "请选择【0-${#active_names[@]}】：" choice
  if [[ -z "$choice" || "$choice" == "0" ]]; then
    return
  fi

  if [[ "$choice" -lt 1 || "$choice" -gt ${#active_names[@]} ]]; then
    red "选择无效！" && sleep 2 && modify_protocol_config
    return
  fi

  local sel_idx=$((choice-1))
  local sel_name="${active_names[$sel_idx]}"
  local sel_tag="${active_tags[$sel_idx]}"
  local sel_var="${active_vars[$sel_idx]}"
  local file_path="$SBFOLDER/conf/${sel_tag}.json"

  local has_uuid=false
  local has_password=false
  local has_path=false
  local has_reality=false
  local is_ss=false
  local is_socks=false

  if [[ "$sel_var" == "vl_re" || "$sel_var" == "vl_h2_re" ]]; then
    has_uuid=true
    has_reality=true
  elif [[ "$sel_var" == "vl_ws_tls" || "$sel_var" == "vl_hu_tls" || "$sel_var" == "vl_h2_tls" || \
          "$sel_var" == "vm_ws" || "$sel_var" == "vm_ws_tls" || "$sel_var" == "vm_hu_tls" || \
          "$sel_var" == "vm_tcp" || "$sel_var" == "vm_http" || "$sel_var" == "vm_quic" || \
          "$sel_var" == "vm_h2_tls" || "$sel_var" == "vl_h2_tls" || "$sel_var" == "tu" || "$sel_var" == "an" ]]; then
    has_uuid=true
  fi

  if [[ "$sel_var" == "vl_ws_tls" || "$sel_var" == "vl_hu_tls" || "$sel_var" == "vm_ws" || \
        "$sel_var" == "vm_ws_tls" || "$sel_var" == "vm_hu_tls" || "$sel_var" == "tr_ws_tls" || \
        "$sel_var" == "tr_hu_tls" || "$sel_var" == "vl_h2_tls" || "$sel_var" == "vm_h2_tls" || \
        "$sel_var" == "tr_h2_tls" || "$sel_var" == "vl_h2_re" ]]; then
    has_path=true
  fi

  if [[ "$sel_var" == "tr_tls" || "$sel_var" == "tr_ws_tls" || "$sel_var" == "tr_hu_tls" || \
        "$sel_var" == "tr_h2_tls" || "$sel_var" == "hy2" || "$sel_var" == "tu" || "$sel_var" == "an" ]]; then
    has_password=true
  fi

  if [[ "$sel_var" == "ss" ]]; then
    is_ss=true
  elif [[ "$sel_var" == "socks" ]]; then
    is_socks=true
  fi

  local need_ssl=false
  if [[ "$sel_var" == "vl_ws_tls" || "$sel_var" == "vl_hu_tls" || "$sel_var" == "vl_h2_tls" || \
        "$sel_var" == "vm_ws_tls" || "$sel_var" == "vm_hu_tls" || "$sel_var" == "vm_h2_tls" || \
        "$sel_var" == "tr_tls" || "$sel_var" == "tr_ws_tls" || "$sel_var" == "tr_hu_tls" || \
        "$sel_var" == "tr_h2_tls" || "$sel_var" == "hy2" || "$sel_var" == "tu" || "$sel_var" == "an" ]]; then
    need_ssl=true
  fi

  echo
  green "请选择要更改的配置项："
  local opt_num=1
  local map_opts=()

  echo "${opt_num}：更改端口 (Port)"
  map_opts+=("port")
  opt_num=$((opt_num+1))

  if $has_uuid; then
    echo "${opt_num}：更改 UUID"
    map_opts+=("uuid")
    opt_num=$((opt_num+1))
  fi

  if $has_password; then
    echo "${opt_num}：更改密码 (Password)"
    map_opts+=("password")
    opt_num=$((opt_num+1))
  fi

  if $has_path; then
    echo "${opt_num}：更改 Path (路径)"
    map_opts+=("path")
    opt_num=$((opt_num+1))
  fi

  if $has_reality; then
    echo "${opt_num}：更改 Reality 伪装域名/SNI"
    map_opts+=("reality_domain")
    opt_num=$((opt_num+1))
    echo "${opt_num}：更换 Reality 密钥对"
    map_opts+=("reality_keys")
    opt_num=$((opt_num+1))
  fi

  if $is_ss; then
    echo "${opt_num}：更改密码 (Password)"
    map_opts+=("ss_password")
    opt_num=$((opt_num+1))
    echo "${opt_num}：更改加密方式 (Method)"
    map_opts+=("ss_method")
    opt_num=$((opt_num+1))
  fi

  if $is_socks; then
    echo "${opt_num}：更改用户名 (Username)"
    map_opts+=("socks_username")
    opt_num=$((opt_num+1))
    echo "${opt_num}：更改密码 (Password)"
    map_opts+=("socks_password")
    opt_num=$((opt_num+1))
  fi

  if $need_ssl; then
    echo "${opt_num}：更改绑定的 SSL 证书类型 (自签/IP/域名)"
    map_opts+=("change_ssl_type")
    opt_num=$((opt_num+1))
  fi

  echo "0：返回上层"
  readp "请选择【0-$((opt_num-1))】：" edit_choice
  if [[ -z "$edit_choice" || "$edit_choice" == "0" ]]; then
    return
  fi

  if [[ "$edit_choice" -lt 1 || "$edit_choice" -ge "$opt_num" ]]; then
    red "选择无效！" && sleep 2 && modify_protocol_config
    return
  fi

  local selected_action="${map_opts[$((edit_choice-1))]}"
  local config_changed=false

  case "$selected_action" in
    port)
      local current_port=$(jq -r '.inbounds[0].listen_port // empty' "$file_path")
      readp "请输入新端口 (当前为: ${current_port:-自动分配}, 回车自动分配随机空闲端口)：" new_port
      
      is_port_in_use_local() {
        local p="$1"
        if [[ -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$p") ]] || \
           [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$p") ]]; then
          return 0
        fi
        local check_tag
        for check_tag in "${proto_tags[@]}"; do
          if [[ "$check_tag" != "$sel_tag" ]]; then
            local p_val=$(jq -r '.inbounds[0].listen_port // empty' "$SBFOLDER/conf/${check_tag}.json" 2>/dev/null)
            if [[ "$p_val" == "$p" ]]; then
              return 0
            fi
          fi
        done
        return 1
      }
      
      if [[ -z "$new_port" ]]; then
        while true; do
          new_port=$(shuf -i 10000-65535 -n 1)
          if ! is_port_in_use_local "$new_port"; then
            break
          fi
        done
        blue "已自动分配可用端口：$new_port"
      else
        if [[ "$new_port" -lt 1 || "$new_port" -gt 65535 ]]; then
          red "端口号不合法！" && sleep 2
          return
        fi
        if is_port_in_use_local "$new_port"; then
          yellow "警告：端口 $new_port 已被占用或与其它协议冲突！"
          readp "是否继续强制使用该端口？[y/N] (默认不使用)：" force_p
          if [[ ! "$force_p" =~ ^[Yy]$ ]]; then
            return
          fi
        fi
      fi
      
      jq --argjson p "$new_port" '.inbounds[0].listen_port = $p' "$file_path" > /tmp/tmp.json && mv /tmp/tmp.json "$file_path"
      config_changed=true
      blue "端口修改完成，新端口为: $new_port"
      ;;
      
    uuid)
      local current_uuid=$(jq -r '.inbounds[0].users[0].uuid // empty' "$file_path")
      readp "请输入新 UUID (当前为: $current_uuid, 回车自动生成随机 UUID)：" new_uuid
      if [[ -z "$new_uuid" ]]; then
        new_uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
      fi
      
      if [[ "$sel_var" == "tu" ]]; then
        jq --arg u "$new_uuid" '.inbounds[0].users[0].uuid = $u | .inbounds[0].users[0].password = $u' "$file_path" > /tmp/tmp.json && mv /tmp/tmp.json "$file_path"
      else
        jq --arg u "$new_uuid" '.inbounds[0].users[0].uuid = $u' "$file_path" > /tmp/tmp.json && mv /tmp/tmp.json "$file_path"
      fi
      config_changed=true
      blue "UUID修改完成，新UUID为: $new_uuid"
      ;;

    password)
      local current_pwd=$(jq -r '.inbounds[0].users[0].password // empty' "$file_path")
      readp "请输入新密码 (当前为: $current_pwd, 回车自动生成随机密码)：" new_pwd
      if [[ -z "$new_pwd" ]]; then
        new_pwd=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
      fi
      jq --arg p "$new_pwd" '.inbounds[0].users[0].password = $p' "$file_path" > /tmp/tmp.json && mv /tmp/tmp.json "$file_path"
      config_changed=true
      blue "密码修改完成，新密码为: $new_pwd"
      ;;

    path)
      local current_path=$(jq -r '.inbounds[0].transport.path // empty' "$file_path")
      readp "请输入新 Path 路径 (当前为: $current_path, 回车自动生成随机路径)：" new_path
      if [[ -z "$new_path" ]]; then
        new_path="/$(cat /proc/sys/kernel/random/uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)"
      fi
      [[ ! "$new_path" =~ ^/ ]] && new_path="/$new_path"
      jq --arg p "$new_path" '.inbounds[0].transport.path = $p' "$file_path" > /tmp/tmp.json && mv /tmp/tmp.json "$file_path"
      config_changed=true
      blue "Path路径修改完成，新Path为: $new_path"
      ;;

    reality_domain)
      local current_dom=$(jq -r '.inbounds[0].tls.server_name // empty' "$file_path")
      readp "请输入新 Reality 伪装域名/SNI (当前为: $current_dom, 回车默认 apple.com)：" new_dom
      [[ -z "$new_dom" ]] && new_dom="apple.com"
      jq --arg d "$new_dom" '.inbounds[0].tls.server_name = $d | .inbounds[0].tls.reality.handshake.server = $d' "$file_path" > /tmp/tmp.json && mv /tmp/tmp.json "$file_path"
      config_changed=true
      blue "Reality伪装域名修改完成，新域名为: $new_dom"
      ;;

    reality_keys)
      local reality_keys=$("$SBFOLDER/sing-box" generate reality-keypair)
      local private_key=$(echo "$reality_keys" | awk '/PrivateKey/{print $NF}' | tr -d '"')
      local public_key=$(echo "$reality_keys" | awk '/PublicKey/{print $NF}' | tr -d '"')
      local short_id=$(openssl rand -hex 8)
      jq --arg priv "$private_key" --arg pub "$public_key" --arg sid "$short_id" \
         '.inbounds[0].tls.reality.private_key = $priv | .inbounds[0].tls.reality.short_id = [$sid]' \
         "$file_path" > /tmp/tmp.json && mv /tmp/tmp.json "$file_path"
      echo "$private_key" > "$SBFOLDER/private.key"
      echo "$public_key" > "$SBFOLDER/public.key"
      config_changed=true
      blue "Reality 密钥对更换完成！"
      yellow "私钥: $private_key"
      yellow "公钥: $public_key"
      ;;

    ss_password)
      local current_pwd=$(jq -r '.inbounds[0].password // empty' "$file_path")
      readp "请输入新 Shadowsocks 密码 (当前为: $current_pwd, 回车自动生成随机密码)：" new_pwd
      if [[ -z "$new_pwd" ]]; then
        new_pwd=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
      fi
      jq --arg p "$new_pwd" '.inbounds[0].password = $p' "$file_path" > /tmp/tmp.json && mv /tmp/tmp.json "$file_path"
      config_changed=true
      blue "Shadowsocks密码修改完成"
      ;;

    ss_method)
      local current_method=$(jq -r '.inbounds[0].method // empty' "$file_path")
      echo
      green "请选择 Shadowsocks 加密方式 (当前为: $current_method)："
      local ss_methods=("aes-128-gcm" "aes-256-gcm" "chacha20-ietf-poly1305" "xchacha20-ietf-poly1305" "2022-blake3-aes-128-gcm" "2022-blake3-aes-256-gcm" "2022-blake3-chacha20-poly1305")
      for ((i=0; i<${#ss_methods[@]}; i++)); do
        echo "$((i+1))：${ss_methods[$i]}"
      done
      readp "请选择【1-${#ss_methods[@]}】：" sm_choice
      if [[ -n "$sm_choice" && "$sm_choice" -ge 1 && "$sm_choice" -le ${#ss_methods[@]} ]]; then
        local new_method="${ss_methods[$((sm_choice-1))]}"
        jq --arg m "$new_method" '.inbounds[0].method = $m' "$file_path" > /tmp/tmp.json && mv /tmp/tmp.json "$file_path"
        config_changed=true
        blue "Shadowsocks加密方式已变更为: $new_method"
      else
        red "选择无效！"
      fi
      ;;

    socks_username)
      local current_user=$(jq -r '.inbounds[0].users[0].username // empty' "$file_path")
      readp "请输入新 Socks 用户名 (当前为: $current_user)：" new_user
      if [[ -n "$new_user" ]]; then
        jq --arg u "$new_user" '.inbounds[0].users[0].username = $u' "$file_path" > /tmp/tmp.json && mv /tmp/tmp.json "$file_path"
        config_changed=true
        blue "Socks用户名修改完成"
      fi
      ;;

    socks_password)
      local current_pwd=$(jq -r '.inbounds[0].users[0].password // empty' "$file_path")
      readp "请输入新 Socks 密码 (当前为: $current_pwd, 回车自动生成随机密码)：" new_pwd
      if [[ -z "$new_pwd" ]]; then
        new_pwd=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
      fi
      jq --arg p "$new_pwd" '.inbounds[0].users[0].password = $p' "$file_path" > /tmp/tmp.json && mv /tmp/tmp.json "$file_path"
      config_changed=true
      blue "Socks密码修改完成"
      ;;

    change_ssl_type)
      local has_self=false
      local has_ip=false
      local has_domain=false
      
      [[ -s "/var/Sing-Box-DuolaD/self_cert.pem" && -s "/var/Sing-Box-DuolaD/self_private.key" ]] && has_self=true
      [[ -s "/var/Sing-Box-DuolaD/ip_cert.pem" && -s "/var/Sing-Box-DuolaD/ip_private.key" ]] && has_ip=true
      [[ -s "/var/Sing-Box-DuolaD/domain_cert.pem" && -s "/var/Sing-Box-DuolaD/domain_private.key" ]] && has_domain=true
      
      if ! $has_self && ! $has_ip && ! $has_domain; then
        red "当前设备未部署任何 SSL 证书，请先去证书管理部署证书！" && sleep 2
        return
      fi
      
      echo
      green "可供选用的已部署证书如下："
      local cert_num=1
      local cert_map=()
      if $has_self; then
        echo "${cert_num}：自签证书 ($(get_self_domain))"
        cert_map+=("self")
        cert_num=$((cert_num+1))
      fi
      if $has_ip; then
        local ip_val=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null || curl -s4 ip.sb)
        echo "${cert_num}：纯 IP 证书 (IP: $ip_val)"
        cert_map+=("ip")
        cert_num=$((cert_num+1))
      fi
      if $has_domain; then
        local dm_val=$(cat /var/Sing-Box-DuolaD/domain.log 2>/dev/null)
        echo "${cert_num}：域名证书 (域名: ${dm_val:-未知})"
        cert_map+=("domain")
        cert_num=$((cert_num+1))
      fi
      echo "0：取消修改"
      readp "请选择【0-$((cert_num-1))】：" choice_cert
      if [[ -z "$choice_cert" || "$choice_cert" == "0" ]]; then
        return
      fi
      
      local chosen_cert_type="${cert_map[$((choice_cert-1))]}"
      
      if [[ "$sel_var" == "vl_ws_tls" || "$sel_var" == "vl_hu_tls" || "$sel_var" == "vl_h2_tls" || \
            "$sel_var" == "vm_ws_tls" || "$sel_var" == "vm_hu_tls" || "$sel_var" == "vm_h2_tls" || \
            "$sel_var" == "tr_ws_tls" || "$sel_var" == "tr_hu_tls" || "$sel_var" == "tr_h2_tls" ]]; then
        touch /var/Sing-Box-DuolaD/proto_certs.log
        sed -i "/^${sel_tag}:/d" /var/Sing-Box-DuolaD/proto_certs.log
        echo "${sel_tag}:${chosen_cert_type}" >> /var/Sing-Box-DuolaD/proto_certs.log
      fi
      
      if [[ "$sel_var" == "tr_tls" || "$sel_var" == "hy2" || "$sel_var" == "tu" || "$sel_var" == "an" || "$sel_var" == "tr_h2_tls" ]]; then
        local cpath="/var/Sing-Box-DuolaD/${chosen_cert_type}_cert.pem"
        local kpath="/var/Sing-Box-DuolaD/${chosen_cert_type}_private.key"
        jq --arg cert "$cpath" --arg key "$kpath" \
           '.inbounds[0].tls.certificate_path = $cert | .inbounds[0].tls.key_path = $key' \
           "$file_path" > /tmp/tmp.json && mv /tmp/tmp.json "$file_path"
      fi
      
      config_changed=true
      blue "该协议所绑定的 SSL 证书类型已成功切换为: $chosen_cert_type"
      ;;
  esac

  if $config_changed; then
    local inbounds_arr="[]"
    local f
    for f in "$SBFOLDER/conf"/*.json; do
      if [[ -f "$f" ]]; then
        local inb=$(jq '.inbounds[0]' "$f" 2>/dev/null)
        if [[ -n "$inb" && "$inb" != "null" ]]; then
          inbounds_arr=$(echo "$inbounds_arr" | jq --argjson inb "$inb" '. += [$inb]' 2>/dev/null)
        fi
      fi
    done
    
    local target
    if [[ -f "$SBFOLDER/sb.json" ]]; then
      jq --argjson inbs "$inbounds_arr" '.inbounds = $inbs' "$SBFOLDER/sb.json" > "$SBFOLDER/sb.json.tmp" && mv "$SBFOLDER/sb.json.tmp" "$SBFOLDER/sb.json"
    fi

    local clean_js=$(strip_json_comments "$SBFOLDER/sb.json")
    local base_config=$(echo "$clean_js" | jq '.inbounds = []' 2>/dev/null)
    if [[ -n "$base_config" ]]; then
      echo "$base_config" > "$SBFOLDER/config.json"
    fi

    write_caddyfile
    restartsb
    sbshare > /dev/null 2>&1
    blue "\n协议配置更新完成并已成功应用！"
  fi
  sleep 2
}

add_protocol() {
  result_vl_vm_hy_tu
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
  
  local proto_names=("VLESS-Reality" "VLESS-WS-TLS" "VLESS-HTTPUpgrade-TLS" "VLESS-H2-TLS" "VLESS-HTTP2-REALITY" "VMess-WS" "VMess-WS-TLS" "VMess-HTTPUpgrade-TLS" "VMess-TCP" "VMess-HTTP" "VMess-QUIC" "VMess-H2-TLS" "Trojan-TLS" "Trojan-WS-TLS" "Trojan-HTTPUpgrade-TLS" "Trojan-H2-TLS" "Shadowsocks" "Hysteria 2" "Tuic-v5" "AnyTLS" "Socks")
  local proto_tags=("vless-reality-sb" "vless-ws-tls-sb" "vless-hu-tls-sb" "vless-h2-tls-sb" "vless-h2-reality-sb" "vmess-ws-sb" "vmess-ws-tls-sb" "vmess-hu-tls-sb" "vmess-tcp-sb" "vmess-http-sb" "vmess-quic-sb" "vmess-h2-tls-sb" "trojan-tls-sb" "trojan-ws-tls-sb" "trojan-hu-tls-sb" "trojan-h2-tls-sb" "shadowsocks-sb" "hy2-sb" "tuic5-sb" "anytls-sb" "socks-sb")
  local proto_vars=("vl_re" "vl_ws_tls" "vl_hu_tls" "vl_h2_tls" "vl_h2_re" "vm_ws" "vm_ws_tls" "vm_hu_tls" "vm_tcp" "vm_http" "vm_quic" "vm_h2_tls" "tr_tls" "tr_ws_tls" "tr_hu_tls" "tr_h2_tls" "ss" "hy2" "tu" "an" "socks")

  local active_vars=()
  local i
  for ((i=0; i<${#proto_names[@]}; i++)); do
    local tag="${proto_tags[$i]}"
    local var="${proto_vars[$i]}"
    if [[ -f "$SBFOLDER/conf/${tag}.json" ]]; then
      eval "use_${var}=true"
      active_vars+=("$var")
    else
      eval "use_${var}=false"
    fi
  done

  echo
  green "请选择要新增的协议（只允许选择 [未安装] 状态的协议，可输入多个数字并用空格分隔，如 1 18 21）："
  green "--- VLESS 组合 ---"
  [[ -f "$SBFOLDER/conf/vless-reality-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
  yellow " 1：VLESS-Reality (Vision + TCP) $state"
  [[ -f "$SBFOLDER/conf/vless-ws-tls-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
  yellow " 2：VLESS-WS-TLS (VLESS over WebSocket + TLS) $state"
  [[ -f "$SBFOLDER/conf/vless-hu-tls-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
  yellow " 3：VLESS-HTTPUpgrade-TLS (VLESS over HTTPUpgrade + TLS) $state"
  [[ -f "$SBFOLDER/conf/vless-h2-tls-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
  yellow " 4：VLESS-H2-TLS (VLESS over HTTP/2 + TLS) $state"
  [[ -f "$SBFOLDER/conf/vless-h2-reality-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
  yellow " 5：VLESS-HTTP2-REALITY (VLESS over HTTP/2 + REALITY) $state"
  green "--- VMess 组合 ---"
  [[ -f "$SBFOLDER/conf/vmess-ws-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
  yellow " 6：VMess-WS (VMess over WebSocket，不启用 TLS) $state"
  [[ -f "$SBFOLDER/conf/vmess-ws-tls-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
  yellow " 7：VMess-WS-TLS (VMess over WebSocket + TLS) $state"
  [[ -f "$SBFOLDER/conf/vmess-hu-tls-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
  yellow " 8：VMess-HTTPUpgrade-TLS (VMess over HTTPUpgrade + TLS) $state"
  [[ -f "$SBFOLDER/conf/vmess-tcp-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
  yellow " 9：VMess-TCP (VMess over TCP，不启用 TLS) $state"
  [[ -f "$SBFOLDER/conf/vmess-http-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
  yellow "10：VMess-HTTP (VMess over HTTP，不启用 TLS) $state"
  [[ -f "$SBFOLDER/conf/vmess-quic-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
  yellow "11：VMess-QUIC (VMess over QUIC，启用 TLS) $state"
  [[ -f "$SBFOLDER/conf/vmess-h2-tls-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
  yellow "12：VMess-H2-TLS (VMess over HTTP/2 + TLS) $state"
  green "--- Trojan 组合 ---"
  [[ -f "$SBFOLDER/conf/trojan-tls-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
  yellow "13：Trojan-TLS (Trojan over TCP + TLS) $state"
  [[ -f "$SBFOLDER/conf/trojan-ws-tls-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
  yellow "14：Trojan-WS-TLS (Trojan over WebSocket + TLS) $state"
  [[ -f "$SBFOLDER/conf/trojan-hu-tls-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
  yellow "15：Trojan-HTTPUpgrade-TLS (Trojan over HTTPUpgrade + TLS) $state"
  [[ -f "$SBFOLDER/conf/trojan-h2-tls-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
  yellow "16：Trojan-H2-TLS (Trojan over HTTP/2 + TLS) $state"
  green "--- 其他经典/高速协议 ---"
  [[ -f "$SBFOLDER/conf/shadowsocks-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
  yellow "17：Shadowsocks (Shadowsocks 多种加密) $state"
  [[ -f "$SBFOLDER/conf/hy2-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
  yellow "18：Hysteria 2 (QUIC/UDP) $state"
  [[ -f "$SBFOLDER/conf/tuic5-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
  yellow "19：Tuic-v5 (QUIC/UDP) $state"
  [[ -f "$SBFOLDER/conf/anytls-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
  yellow "20：AnyTLS $state"
  [[ -f "$SBFOLDER/conf/socks-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
  yellow "21：Socks (Socks5 代理服务) $state"
  echo " 0：返回上层"
  readp "请选择【0-21】：" select_proto
  if [[ -z "$select_proto" || "$select_proto" == "0" ]]; then
    return
  fi

  read -r -a proto_arr <<< "$select_proto"
  local to_add_vars=()
  local to_add_names=()
  local to_add_tags=()

  for item in "${proto_arr[@]}"; do
    item=$(echo "$item" | xargs)
    local sel_idx=""
    case "$item" in
      1) sel_idx=0 ;;
      2) sel_idx=1 ;;
      3) sel_idx=2 ;;
      4) sel_idx=3 ;;
      5) sel_idx=4 ;;
      6) sel_idx=5 ;;
      7) sel_idx=6 ;;
      8) sel_idx=7 ;;
      9) sel_idx=8 ;;
      10) sel_idx=9 ;;
      11) sel_idx=10 ;;
      12) sel_idx=11 ;;
      13) sel_idx=12 ;;
      14) sel_idx=13 ;;
      15) sel_idx=14 ;;
      16) sel_idx=15 ;;
      17) sel_idx=16 ;;
      18) sel_idx=17 ;;
      19) sel_idx=18 ;;
      20) sel_idx=19 ;;
      21) sel_idx=20 ;;
      *) continue ;;
    esac

    if [[ -n "$sel_idx" ]]; then
      local tag="${proto_tags[$sel_idx]}"
      local name="${proto_names[$sel_idx]}"
      local var="${proto_vars[$sel_idx]}"

      if [[ -f "$SBFOLDER/conf/${tag}.json" ]]; then
        yellow "协议 ${name} 已经安装过，跳过。"
      else
        to_add_vars+=("$var")
        to_add_names+=("$name")
        to_add_tags+=("$tag")
      fi
    fi
  done

  if [[ ${#to_add_vars[@]} -eq 0 ]]; then
    red "未选择任何需要新增的协议，或所选协议均已安装！"
    sleep 2 && add_protocol
    return
  fi

  local need_tls_any=false
  local need_caddy_any=false

  local idx
  for ((idx=0; idx<${#to_add_vars[@]}; idx++)); do
    local sel_var="${to_add_vars[$idx]}"
    local sel_name="${to_add_names[$idx]}"
    local sel_tag="${to_add_tags[$idx]}"

    blue "\n配置协议 [$sel_name]："

    # Get port for new protocol
    local allocated_ports=()
    local tag_p
    for tag_p in "${proto_tags[@]}"; do
      local p_val=$(query_inbound_port "$tag_p")
      [[ -n "$p_val" ]] && allocated_ports+=("$p_val")
    done

    is_port_in_use() {
      local p="$1"
      if [[ -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$p") ]] || \
         [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$p") ]]; then
        return 0
      fi
      local check
      for check in "${allocated_ports[@]}"; do
        if [[ "$check" == "$p" ]]; then
          return 0
        fi
      done
      return 1
    }

    get_random_free_port() {
      local free_port
      while true; do
        free_port=$(shuf -i 10000-65535 -n 1)
        if ! is_port_in_use "$free_port"; then
          allocated_ports+=("$free_port")
          echo "$free_port"
          break
        fi
      done
    }

    get_cdn_port() {
      local is_tls="$1"
      local ports
      if [[ "$is_tls" == "true" ]]; then
        ports=("2053" "2083" "2087" "2096" "8443")
      else
        ports=("8080" "8880" "2052" "2082" "2086" "2095")
      fi
      local p
      local shuffled_ports=($(shuf -e "${ports[@]}"))
      for p in "${shuffled_ports[@]}"; do
        if ! is_port_in_use "$p"; then
          allocated_ports+=("$p")
          echo "$p"
          return 0
        fi
      done
      get_random_free_port
    }

    local port=""
    readp "请设置 ${sel_name} 的端口 (回车自动分配可用端口)：" custom_p
    if [[ -n "$custom_p" ]]; then
      if [[ "$custom_p" -ge 1 && "$custom_p" -le 65535 ]]; then
        if is_port_in_use "$custom_p"; then
          yellow "警告：端口 $custom_p 已被占用！"
          readp "是否继续强制使用该端口？[y/N] (默认不使用)：" force_p
          if [[ "$force_p" =~ ^[Yy]$ ]]; then
            port="$custom_p"
          else
            port=$(get_random_free_port)
            blue "已自动分配可用端口：$port"
          fi
        else
          port="$custom_p"
        fi
      else
        red "输入的端口不合法，将自动分配！"
        port=$(get_random_free_port)
      fi
    else
      if [[ "$sel_var" == "vl_ws_tls" || "$sel_var" == "vl_hu_tls" || "$sel_var" == "vl_h2_tls" || \
            "$sel_var" == "vm_ws_tls" || "$sel_var" == "vm_hu_tls" || "$sel_var" == "vm_h2_tls" || \
            "$sel_var" == "tr_ws_tls" || "$sel_var" == "tr_hu_tls" || "$sel_var" == "tr_h2_tls" ]]; then
        port=$(get_cdn_port "true")
      elif [[ "$sel_var" == "vm_ws" ]]; then
        port=$(get_cdn_port "false")
      else
        port=$(get_random_free_port)
      fi
      blue "已自动分配可用端口：$port"
    fi

    eval "port_${sel_var}=\"$port\""

    get_uuid() {
      cat /proc/sys/kernel/random/uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid
    }
    
    if [[ "$sel_var" == "vl_re" ]]; then
      [[ -z "$uuid_vl_re" ]] && uuid_vl_re=$(get_uuid)
    elif [[ "$sel_var" == "vl_ws_tls" ]]; then
      [[ -z "$uuid_vl_ws" ]] && uuid_vl_ws=$(get_uuid)
    elif [[ "$sel_var" == "vl_hu_tls" ]]; then
      [[ -z "$uuid_vl_hu" ]] && uuid_vl_hu=$(get_uuid)
    elif [[ "$sel_var" == "vm_ws" ]]; then
      [[ -z "$uuid_vm_ws" ]] && uuid_vm_ws=$(get_uuid)
    elif [[ "$sel_var" == "vm_ws_tls" ]]; then
      [[ -z "$uuid_vm_ws_tls" ]] && uuid_vm_ws_tls=$(get_uuid)
    elif [[ "$sel_var" == "vm_hu_tls" ]]; then
      [[ -z "$uuid_vm_hu_tls" ]] && uuid_vm_hu_tls=$(get_uuid)
    elif [[ "$sel_var" == "tr_tls" ]]; then
      [[ -z "$uuid_tr_tls" ]] && uuid_tr_tls=$(get_uuid)
    elif [[ "$sel_var" == "tr_ws_tls" ]]; then
      [[ -z "$uuid_tr_ws_tls" ]] && uuid_tr_ws_tls=$(get_uuid)
    elif [[ "$sel_var" == "tr_hu_tls" ]]; then
      [[ -z "$uuid_tr_hu_tls" ]] && uuid_tr_hu_tls=$(get_uuid)
    elif [[ "$sel_var" == "hy2" ]]; then
      [[ -z "$uuid_hy2" ]] && uuid_hy2=$(get_uuid)
    elif [[ "$sel_var" == "tu" ]]; then
      [[ -z "$uuid_tu" ]] && uuid_tu=$(get_uuid)
    elif [[ "$sel_var" == "an" ]]; then
      [[ -z "$uuid_an" ]] && uuid_an=$(get_uuid)
    elif [[ "$sel_var" == "vm_tcp" ]]; then
      [[ -z "$uuid_vm_tcp" ]] && uuid_vm_tcp=$(get_uuid)
    elif [[ "$sel_var" == "vm_http" ]]; then
      [[ -z "$uuid_vm_http" ]] && uuid_vm_http=$(get_uuid)
    elif [[ "$sel_var" == "vm_quic" ]]; then
      [[ -z "$uuid_vm_quic" ]] && uuid_vm_quic=$(get_uuid)
    elif [[ "$sel_var" == "vm_h2_tls" ]]; then
      [[ -z "$uuid_vm_h2_tls" ]] && uuid_vm_h2_tls=$(get_uuid)
    elif [[ "$sel_var" == "vl_h2_tls" ]]; then
      [[ -z "$uuid_vl_h2" ]] && uuid_vl_h2=$(get_uuid)
    elif [[ "$sel_var" == "tr_h2_tls" ]]; then
      [[ -z "$uuid_tr_h2_tls" ]] && uuid_tr_h2_tls=$(get_uuid)
    elif [[ "$sel_var" == "vl_h2_re" ]]; then
      [[ -z "$uuid_vl_h2_re" ]] && uuid_vl_h2_re=$(get_uuid)
    elif [[ "$sel_var" == "ss" ]]; then
      if [[ -z "$ss_password" ]]; then
        ss_method="2022-blake3-aes-128-gcm"
        ss_password=$("$SBFOLDER/sing-box" generate rand 16 --base64)
      fi
    elif [[ "$sel_var" == "socks" ]]; then
      if [[ -z "$socks_username" ]]; then
        socks_username=$("$SBFOLDER/sing-box" generate uuid)
        socks_password=$("$SBFOLDER/sing-box" generate uuid)
      fi
    fi

    if [[ "$sel_var" == "vl_re" || "$sel_var" == "vl_h2_re" ]]; then
      if [[ -z "$public_key" ]]; then
        local reality_keys=$("$SBFOLDER/sing-box" generate reality-keypair)
        private_key=$(echo "$reality_keys" | awk '/PrivateKey/{print $NF}' | tr -d '"')
        public_key=$(echo "$reality_keys" | awk '/PublicKey/{print $NF}' | tr -d '"')
        echo "$private_key" > "$SBFOLDER/private.key"
        echo "$public_key" > "$SBFOLDER/public.key"
        short_id=$(openssl rand -hex 8)
      fi
    fi

    if [[ "$sel_var" == "vl_ws_tls" || "$sel_var" == "vl_hu_tls" || "$sel_var" == "vl_h2_tls" || \
          "$sel_var" == "vm_ws_tls" || "$sel_var" == "vm_hu_tls" || "$sel_var" == "vm_h2_tls" || \
          "$sel_var" == "tr_ws_tls" || "$sel_var" == "tr_hu_tls" || "$sel_var" == "tr_h2_tls" ]]; then
      need_tls_any=true
      need_caddy_any=true
    elif [[ "$sel_var" == "tr_tls" || "$sel_var" == "hy2" || "$sel_var" == "tu" || "$sel_var" == "an" ]]; then
      need_tls_any=true
    fi
  done

  local has_tls=false
  if [[ -f "/var/Sing-Box-DuolaD/cert.pem" ]]; then
    has_tls=true
  fi

  local caddy_installed=false
  if [[ -f /usr/local/bin/caddy ]]; then
    caddy_installed=true
  fi

  if $need_tls_any && ! $has_tls; then
    blue "\n新增的协议需要配置 SSL 证书。"
    if $need_caddy_any; then
      use_caddy="true"
      inscertificate
      caddyservice
    else
      use_caddy="false"
      inscertificate
    fi
  elif $need_caddy_any && ! $caddy_installed; then
    blue "\n检测到新增协议需要使用 443 Caddy 反代，但当前未安装 Caddy。正在安装配置 Caddy..."
    use_caddy="true"
    if [[ -f /var/Sing-Box-DuolaD/domain.log ]]; then
      cert_type="domain"
      ym_domain=$(cat /var/Sing-Box-DuolaD/domain.log)
      tls_sni="$ym_domain"
    elif [[ -f /var/Sing-Box-DuolaD/cert_type.log ]]; then
      cert_type=$(cat /var/Sing-Box-DuolaD/cert_type.log)
    else
      cert_type="self"
    fi
    setup_caddy_cert
    caddyservice
  fi

  local v_add
  for v_add in "${to_add_vars[@]}"; do
    eval "use_${v_add}=true"
  done
  
  inssbjsonser
  restartsb
  
  sbshare > /dev/null 2>&1
  
  blue "\n所选协议已成功新增并启动！"
  sleep 2
}

delete_protocol() {
  result_vl_vm_hy_tu
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")

  local proto_names=("VLESS-Reality" "VLESS-WS-TLS" "VLESS-HTTPUpgrade-TLS" "VLESS-H2-TLS" "VLESS-HTTP2-REALITY" "VMess-WS" "VMess-WS-TLS" "VMess-HTTPUpgrade-TLS" "VMess-TCP" "VMess-HTTP" "VMess-QUIC" "VMess-H2-TLS" "Trojan-TLS" "Trojan-WS-TLS" "Trojan-HTTPUpgrade-TLS" "Trojan-H2-TLS" "Shadowsocks" "Hysteria 2" "Tuic-v5" "AnyTLS" "Socks")
  local proto_tags=("vless-reality-sb" "vless-ws-tls-sb" "vless-hu-tls-sb" "vless-h2-tls-sb" "vless-h2-reality-sb" "vmess-ws-sb" "vmess-ws-tls-sb" "vmess-hu-tls-sb" "vmess-tcp-sb" "vmess-http-sb" "vmess-quic-sb" "vmess-h2-tls-sb" "trojan-tls-sb" "trojan-ws-tls-sb" "trojan-hu-tls-sb" "trojan-h2-tls-sb" "shadowsocks-sb" "hy2-sb" "tuic5-sb" "anytls-sb" "socks-sb")
  local proto_vars=("vl_re" "vl_ws_tls" "vl_hu_tls" "vl_h2_tls" "vl_h2_re" "vm_ws" "vm_ws_tls" "vm_hu_tls" "vm_tcp" "vm_http" "vm_quic" "vm_h2_tls" "tr_tls" "tr_ws_tls" "tr_hu_tls" "tr_h2_tls" "ss" "hy2" "tu" "an" "socks")

  local active_names=()
  local active_tags=()
  local active_vars=()
  
  local i
  for ((i=0; i<${#proto_names[@]}; i++)); do
    local tag="${proto_tags[$i]}"
    local var="${proto_vars[$i]}"
    if [[ -f "$SBFOLDER/conf/${tag}.json" ]]; then
      active_names+=("${proto_names[$i]}")
      active_tags+=("$tag")
      active_vars+=("$var")
    fi
  done

  if [[ ${#active_names[@]} -eq 0 ]]; then
    red "当前没有安装任何协议，无法删除！" && sleep 2
    return
  fi

  echo
  green "请选择要删除的协议（可选择以下列表中已安装的协议，用空格分隔，如 1 2）："
  for ((i=0; i<${#active_names[@]}; i++)); do
    echo -e "$((i+1))：${active_names[$i]}"
  done
  echo "0：返回上层"
  readp "请选择【0-${#active_names[@]}】：" choice_str
  if [[ -z "$choice_str" || "$choice_str" == "0" ]]; then
    return
  fi

  read -r -a del_arr <<< "$choice_str"
  local to_del_tags=()
  local to_del_vars=()
  local to_del_names=()

  for item in "${del_arr[@]}"; do
    item=$(echo "$item" | xargs)
    if [[ "$item" -ge 1 && "$item" -le ${#active_names[@]} ]]; then
      local idx=$((item-1))
      to_del_tags+=("${active_tags[$idx]}")
      to_del_vars+=("${active_vars[$idx]}")
      to_del_names+=("${active_names[$idx]}")
    fi
  done

  if [[ ${#to_del_vars[@]} -eq 0 ]]; then
    red "选择无效！" && sleep 2 && delete_protocol
    return
  fi

  if [[ ${#to_del_vars[@]} -ge ${#active_names[@]} ]]; then
    red "不能删除全部运行中的协议。必须保留至少一个协议运行！"
    yellow "如需彻底清除，请退出并使用主菜单2进行删除卸载。"
    sleep 3
    return
  fi

  green "\n确认删除以下协议吗？"
  for name in "${to_del_names[@]}"; do
    yellow " - $name"
  done
  readp "确认删除？[y/N] (默认不删除)：" confirm_del
  if [[ ! "$confirm_del" =~ ^[Yy]$ ]]; then
    return
  fi

  for tag in "${to_del_tags[@]}"; do
    rm -f "$SBFOLDER/conf/${tag}.json"
  done

  local remaining_vars=()
  for ((i=0; i<${#proto_names[@]}; i++)); do
    local tag_check="${proto_tags[$i]}"
    local var_check="${proto_vars[$i]}"
    if [[ -f "$SBFOLDER/conf/${tag_check}.json" ]]; then
      eval "use_${var_check}=true"
      remaining_vars+=("$var_check")
    else
      eval "use_${var_check}=false"
    fi
  done

  local caddy_active=false
  if systemctl is-active --quiet caddy 2>/dev/null || rc-service caddy status 2>/dev/null | grep -q "started"; then
    caddy_active=true
  fi

  local has_caddy_remaining=false
  for var_item in "${remaining_vars[@]}"; do
    if [[ "$var_item" == "vl_ws_tls" || "$var_item" == "vl_hu_tls" || "$var_item" == "vl_h2_tls" || \
          "$var_item" == "vm_ws_tls" || "$var_item" == "vm_hu_tls" || "$var_item" == "vm_h2_tls" || \
          "$var_item" == "tr_ws_tls" || "$var_item" == "tr_hu_tls" || "$var_item" == "tr_h2_tls" ]]; then
      has_caddy_remaining=true
    fi
  done

  local has_tls_remaining=false
  for var_item in "${remaining_vars[@]}"; do
    if [[ "$var_item" == "vl_ws_tls" || "$var_item" == "vl_hu_tls" || "$var_item" == "vl_h2_tls" || \
          "$var_item" == "vm_ws_tls" || "$var_item" == "vm_hu_tls" || "$var_item" == "vm_h2_tls" || \
          "$var_item" == "tr_ws_tls" || "$var_item" == "tr_hu_tls" || "$var_item" == "tr_h2_tls" || \
          "$var_item" == "tr_tls" || "$var_item" == "hy2" || "$var_item" == "tu" || "$var_item" == "an" ]]; then
      has_tls_remaining=true
    fi
  done

  if $caddy_active && ! $has_caddy_remaining; then
    echo
    yellow "检测到删除后已无任何协议需要使用 443 Caddy 反代。"
    readp "是否需要自动关闭并完全卸载 Caddy？[Y/n] (默认卸载)：" uninstall_caddy
    if [[ -z "$uninstall_caddy" || "$uninstall_caddy" =~ ^[Yy]$ ]]; then
      blue "正在卸载 Caddy..."
      if command -v apk >/dev/null 2>&1; then
        rc-service caddy stop 2>/dev/null
        rc-update del caddy default 2>/dev/null
        rm -f /etc/init.d/caddy
      else
        systemctl stop caddy 2>/dev/null
        systemctl disable caddy 2>/dev/null
        rm -f /etc/systemd/system/caddy.service
        systemctl daemon-reload
      fi
      rm -f /usr/local/bin/caddy
      rm -rf /etc/caddy
      blue "Caddy 卸载完成"
      use_caddy="false"
    fi
  fi

  if ! $has_tls_remaining; then
    echo
    yellow "检测到删除后已无任何协议使用 SSL 证书。"
    readp "是否删除已有的 SSL 证书？[y/N] (默认不删除)：" del_certs
    if [[ "$del_certs" =~ ^[Yy]$ ]]; then
      blue "正在清理 SSL 证书..."
      rm -rf /var/Sing-Box-DuolaD
      rm -f "$SBFOLDER/cert.pem" "$SBFOLDER/private.key" "$SBFOLDER/ca.pem"
      if command -v ~/.acme.sh/acme.sh &>/dev/null; then
        readp "是否同时彻底卸载 acme.sh 证书申请工具？[y/N] (默认不删除)：" del_acme
        if [[ "$del_acme" =~ ^[Yy]$ ]]; then
          ~/.acme.sh/acme.sh --uninstall >/dev/null 2>&1
          rm -rf ~/.acme.sh
          blue "acme.sh 卸载完成"
        fi
      fi
      blue "SSL 证书清理完成"
    fi
  fi

  inssbjsonser
  restartsb

  sbshare > /dev/null 2>&1

  blue "\n所选协议已成功删除！"
  sleep 2
}

# --- Warp / Psiphon Multi-Instance Storage & Utilities ---
WARP_INST_FILE="$SBFOLDER/warp_instances.conf"
DNS_SNI_INST_FILE="$SBFOLDER/dns_sni_instances.conf"

init_warp_instances_db() {
  mkdir -p "$SBFOLDER"
  if [ ! -f "$WARP_INST_FILE" ]; then
    touch "$WARP_INST_FILE"
    if [ -f "$SBFOLDER/warp-plus.log" ]; then
      local log_cmd=$(head -n 1 "$SBFOLDER/warp-plus.log" 2>/dev/null)
      local old_port=$(echo "$log_cmd" | grep -oP ':\K[0-9]+' | head -n 1)
      old_port=${old_port:-40000}
      local old_type="warp"
      local old_country="NONE"
      if echo "$log_cmd" | grep -q "usque"; then
        old_type="usque"
      elif echo "$log_cmd" | grep -q "warp-cli"; then
        old_type="warp-cli"
      elif echo "$log_cmd" | grep -q "--cfon"; then
        old_type="psiphon"
        old_country=$(echo "$log_cmd" | grep -oP '--country\s+\K[A-Z]+' | head -n 1)
        old_country=${old_country:-US}
      fi
      local old_tag="socks-out"
      echo "${old_port}|${old_type}|${old_country}|${old_tag}|running" > "$WARP_INST_FILE"
    fi
  fi
  if [ ! -f "$DNS_SNI_INST_FILE" ]; then
    touch "$DNS_SNI_INST_FILE"
  fi
}

rebuild_singbox_outbounds() {
  init_warp_instances_db
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json" 2>/dev/null)
  
  [ -z "$clean_json" ] && return
  
  # 1. 重载 Socks5 Outbounds
  local base_outs=$(echo "$clean_json" | jq '[.outbounds[] | select(.type != "socks")]' 2>/dev/null)
  local socks_outs="[]"
  
  if [ -s "$WARP_INST_FILE" ]; then
    while IFS='|' read -r i_port i_type i_country i_tag i_status; do
      [[ -z "$i_port" || "$i_status" != "running" ]] && continue
      local item=$(jq -n \
        --arg tag "$i_tag" \
        --argjson port "$i_port" \
        '{type: "socks", tag: $tag, server: "127.0.0.1", server_port: $port, version: "5"}')
      socks_outs=$(echo "$socks_outs" | jq --argjson item "$item" '. + [$item]')
    done < "$WARP_INST_FILE"
  fi
  
  if [[ $(echo "$socks_outs" | jq 'length' 2>/dev/null || echo 0) -eq 0 ]]; then
    socks_outs='[{"type":"socks","tag":"socks-out","server":"127.0.0.1","server_port":40000,"version":"5"}]'
  fi
  
  local tmp_json=$(echo "$clean_json" | jq --argjson s "$socks_outs" --argjson b "$base_outs" '.outbounds = ($b + $s)')

  # 2. 重载 DNS 代理与 SNI 反向代理规则
  if [ -f "$DNS_SNI_INST_FILE" ]; then
    local base_dns_servers=$(echo "$tmp_json" | jq '[.dns.servers[]? | select((.tag | startswith("dns-") | not) and (.tag | startswith("sni-") | not))]' 2>/dev/null)
    local base_dns_rules=$(echo "$tmp_json" | jq '[.dns.rules[]? | select((.server? | startswith("dns-") | not) and (.server? | startswith("sni-") | not))]' 2>/dev/null)
    local base_route_rule_sets=$(echo "$tmp_json" | jq '.route.rule_set // []' 2>/dev/null)

    local add_dns_servers="[]"
    local add_dns_rules="[]"
    local add_route_rule_sets="[]"

    while IFS='|' read -r r_mode r_port r_target r_domains r_tag r_status r_rule_type r_geosites; do
      [[ -z "$r_mode" || "$r_status" != "running" ]] && continue
      
      local dom_arr=$(echo "$r_domains" | tr ',' '\n' | grep -v '^$' | jq -R . | jq -s .)

      # 1. 处理后缀域名规则 (domain)
      if [[ $(echo "$dom_arr" | jq 'length' 2>/dev/null || echo 0) -gt 0 ]]; then
        local dom_d_rule=$(jq -n --arg server "$r_tag" --argjson dom "$dom_arr" '{domain: $dom, server: $server}')
        add_dns_rules=$(echo "$add_dns_rules" | jq --argjson item "$dom_d_rule" '. + [$item]')
      fi

      # 2. 处理 geosite 规则 (rule_set)
      if [[ -n "$r_geosites" ]]; then
        local rs_names="[]"
        while read -r raw_gname; do
          [[ -z "$raw_gname" ]] && continue
          local gname="$raw_gname"
          [[ "$gname" != geosite-* ]] && gname="geosite-${raw_gname}"
          rs_names=$(echo "$rs_names" | jq --arg g "$gname" '. + [$g]')

          local raw_short=${gname#geosite-}
          local srs_url="https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/${raw_short}.srs"
          local rs_item=$(jq -n --arg tag "$gname" --arg url "$srs_url" \
            '{tag: $tag, type: "remote", format: "binary", url: $url, download_detour: "direct"}')
          add_route_rule_sets=$(echo "$add_route_rule_sets" | jq --argjson item "$rs_item" \
            'if any(.[]; .tag == $item.tag) then . else . + [$item] end')
        done < <(echo "$r_geosites" | tr ',' '\n' | tr ' ' '\n')

        local geo_d_rule=$(jq -n --arg server "$r_tag" --argjson rs "$rs_names" '{rule_set: $rs, server: $server}')
        add_dns_rules=$(echo "$add_dns_rules" | jq --argjson item "$geo_d_rule" '. + [$item]')
      fi

      # 3. 构造 DNS Server 条目
      if [[ "$r_mode" == "dns" ]]; then
        local dns_ip=$(echo "$r_target" | cut -d':' -f1)
        local dns_p=$(echo "$r_target" | cut -d':' -f2)
        dns_p=${dns_p:-53}

        local d_serv=$(jq -n --arg tag "$r_tag" --arg server "$dns_ip" --argjson port "$dns_p" \
          '{tag: $tag, type: "udp", server: $server, server_port: $port}')
        add_dns_servers=$(echo "$add_dns_servers" | jq --argjson item "$d_serv" '. + [$item]')

      elif [[ "$r_mode" == "sni" ]]; then
        local predefined_obj="{}"
        while read -r dom; do
          [[ -z "$dom" ]] && continue
          predefined_obj=$(echo "$predefined_obj" | jq --arg d "$dom" --arg ip "$r_target" '. + {($d): $ip}')
        done < <(echo "$r_domains" | tr ',' '\n' | tr ' ' '\n')

        local s_serv=$(jq -n --arg tag "$r_tag" --argjson pre "$predefined_obj" \
          '{tag: $tag, type: "hosts", predefined: $pre}')
        add_dns_servers=$(echo "$add_dns_servers" | jq --argjson item "$s_serv" '. + [$item]')
      fi
    done < "$DNS_SNI_INST_FILE"

    tmp_json=$(echo "$tmp_json" | jq --argjson serv "$base_dns_servers" --argjson add_serv "$add_dns_servers" \
      --argjson rule "$base_dns_rules" --argjson add_rule "$add_dns_rules" \
      --argjson base_rs "$base_route_rule_sets" --argjson add_rs "$add_route_rule_sets" \
      '.dns.servers = ($serv + $add_serv) | .dns.rules = ($add_rule + $rule) | .route.rule_set = ($base_rs + $add_rs | unique_by(.tag))')
  fi

  echo "$tmp_json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
  prune_orphaned_rule_sets
}

# --- Helper: Prune Orphaned Rule Sets and Invalid Empty Rules ---
prune_orphaned_rule_sets() {
  [ ! -f "$SBFOLDER/sb.json" ] && return
  jq '
    ([.route.rules[]?.rule_set? | if type == "array" then .[] elif type == "string" then . else empty end] +
     [.dns.rules[]?.rule_set? | if type == "array" then .[] elif type == "string" then . else empty end]
     | map(select(. != null and . != "")) | unique) as $active_rs
    | .route.rule_set = [(.route.rule_set[]? | select(.tag as $t | $active_rs | index($t) != null))]
    | .route.rules = [(.route.rules[]? | select(
        has("domain_suffix") or has("rule_set") or has("geosite") or has("geoip") or
        has("ip_cidr") or has("domain") or has("port") or has("inbound") or
        has("action") or has("clash_mode")
      ))]
  ' "$SBFOLDER/sb.json" > /tmp/sb.json 2>/dev/null && mv /tmp/sb.json "$SBFOLDER/sb.json"
}

# --- Domain Splitting & Routing Rules Compiler ---
update_routing_rule() {
  local route_channel="$1"
  local rule_type="$2" # "domain_suffix" or "geosite"
  local raw_items="$3"
  
  local json_array
  if [[ -z "$raw_items" || "$raw_items" == "DuolaD" ]]; then
    json_array='["DuolaD"]'
  else
    json_array=$(echo "$raw_items" | jq -R 'split(" ")')
  fi

  local target_outbound=""
  case "$route_channel" in
    w4) target_outbound="warp-IPv4-out" ;;
    w6) target_outbound="warp-IPv6-out" ;;
    s4) target_outbound="socks-IPv4-out" ;;
    s6) target_outbound="socks-IPv6-out" ;;
    ad4) target_outbound="vps-outbound-v4" ;;
    ad6) target_outbound="vps-outbound-v6" ;;
    *) target_outbound="$route_channel" ;;
  esac

  if [[ "$rule_type" == "domain_suffix" ]]; then
    if [[ "$json_array" == '["DuolaD"]' ]]; then
      case "$route_channel" in
        w4)
          jq '
            (.route.rules[] | select(.strategy == "prefer_ipv4")) |= del(.domain_suffix) |
            (.route.rules[] | select(.outbound == "warp-out")) |= del(.domain_suffix)
          ' "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
          ;;
        w6)
          jq '
            (.route.rules[] | select(.strategy == "prefer_ipv6")) |= del(.domain_suffix) |
            (.route.rules[] | select(.outbound == "warp-out")) |= del(.domain_suffix)
          ' "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
          ;;
        s4)
          jq '
            (.route.rules[] | select(.strategy == "prefer_ipv4")) |= del(.domain_suffix) |
            (.route.rules[] | select(.outbound == "socks-out")) |= del(.domain_suffix)
          ' "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
          ;;
        s6)
          jq '
            (.route.rules[] | select(.strategy == "prefer_ipv6")) |= del(.domain_suffix) |
            (.route.rules[] | select(.outbound == "socks-out")) |= del(.domain_suffix)
          ' "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
          ;;
        ad4)
          jq '
            (.route.rules[] | select(.outbound == "vps-outbound-v4")) |= del(.domain_suffix)
          ' "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
          ;;
        ad6)
          jq '
            (.route.rules[] | select(.outbound == "vps-outbound-v6")) |= del(.domain_suffix)
          ' "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
          ;;
        *)
          jq --arg ob "$target_outbound" '
            (.route.rules[] | select(.outbound == $ob)) |= del(.domain_suffix)
          ' "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
          ;;
      esac
    else
      case "$route_channel" in
        w4)
          jq --argjson arr "$json_array" \
             '(if any(.route.rules[]; .strategy == "prefer_ipv4") then (.route.rules[] | select(.strategy == "prefer_ipv4")).domain_suffix = $arr else .route.rules += [{"strategy": "prefer_ipv4", "domain_suffix": $arr}] end) |
              (if any(.route.rules[]; .outbound == "warp-out") then (.route.rules[] | select(.outbound == "warp-out")).domain_suffix = $arr else .route.rules += [{"outbound": "warp-out", "domain_suffix": $arr}] end)' \
             "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
          ;;
        w6)
          jq --argjson arr "$json_array" \
             '(if any(.route.rules[]; .strategy == "prefer_ipv6") then (.route.rules[] | select(.strategy == "prefer_ipv6")).domain_suffix = $arr else .route.rules += [{"strategy": "prefer_ipv6", "domain_suffix": $arr}] end) |
              (if any(.route.rules[]; .outbound == "warp-out") then (.route.rules[] | select(.outbound == "warp-out")).domain_suffix = $arr else .route.rules += [{"outbound": "warp-out", "domain_suffix": $arr}] end)' \
             "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
          ;;
        s4)
          jq --argjson arr "$json_array" \
             '(if any(.route.rules[]; .strategy == "prefer_ipv4") then (.route.rules[] | select(.strategy == "prefer_ipv4")).domain_suffix = $arr else .route.rules += [{"strategy": "prefer_ipv4", "domain_suffix": $arr}] end) |
              (if any(.route.rules[]; .outbound == "socks-out") then (.route.rules[] | select(.outbound == "socks-out")).domain_suffix = $arr else .route.rules += [{"outbound": "socks-out", "domain_suffix": $arr}] end)' \
             "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
          ;;
        s6)
          jq --argjson arr "$json_array" \
             '(if any(.route.rules[]; .strategy == "prefer_ipv6") then (.route.rules[] | select(.strategy == "prefer_ipv6")).domain_suffix = $arr else .route.rules += [{"strategy": "prefer_ipv6", "domain_suffix": $arr}] end) |
              (if any(.route.rules[]; .outbound == "socks-out") then (.route.rules[] | select(.outbound == "socks-out")).domain_suffix = $arr else .route.rules += [{"outbound": "socks-out", "domain_suffix": $arr}] end)' \
             "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
          ;;
        ad4)
          jq --argjson arr "$json_array" \
             'if any(.route.rules[]; .outbound == "vps-outbound-v4") then (.route.rules[] | select(.outbound == "vps-outbound-v4")).domain_suffix = $arr else .route.rules += [{"outbound": "vps-outbound-v4", "domain_suffix": $arr}] end' \
             "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
          ;;
        ad6)
          jq --argjson arr "$json_array" \
             'if any(.route.rules[]; .outbound == "vps-outbound-v6") then (.route.rules[] | select(.outbound == "vps-outbound-v6")).domain_suffix = $arr else .route.rules += [{"outbound": "vps-outbound-v6", "domain_suffix": $arr}] end' \
             "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
          ;;
        *)
          jq --argjson arr "$json_array" --arg ob "$target_outbound" \
             'if any(.route.rules[]; .outbound == $ob) then (.route.rules[] | select(.outbound == $ob)).domain_suffix = $arr else .route.rules += [{"domain_suffix": $arr, "outbound": $ob}] end' \
             "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
          ;;
      esac
    fi
  elif [[ "$rule_type" == "geosite" ]]; then
    if [[ "$json_array" == '["DuolaD"]' ]]; then
      case "$route_channel" in
        w4)
          jq '
            (.route.rules[] | select(.strategy == "prefer_ipv4")) |= del(.rule_set) |
            (.route.rules[] | select(.outbound == "warp-out")) |= del(.rule_set)
          ' "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
          ;;
        w6)
          jq '
            (.route.rules[] | select(.strategy == "prefer_ipv6")) |= del(.rule_set) |
            (.route.rules[] | select(.outbound == "warp-out")) |= del(.rule_set)
          ' "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
          ;;
        s4)
          jq '
            (.route.rules[] | select(.strategy == "prefer_ipv4")) |= del(.rule_set) |
            (.route.rules[] | select(.outbound == "socks-out")) |= del(.rule_set)
          ' "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
          ;;
        s6)
          jq '
            (.route.rules[] | select(.strategy == "prefer_ipv6")) |= del(.rule_set) |
            (.route.rules[] | select(.outbound == "socks-out")) |= del(.rule_set)
          ' "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
          ;;
        ad4)
          jq '
            (.route.rules[] | select(.outbound == "vps-outbound-v4")) |= del(.rule_set)
          ' "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
          ;;
        ad6)
          jq '
            (.route.rules[] | select(.outbound == "vps-outbound-v6")) |= del(.rule_set)
          ' "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
          ;;
        *)
          jq --arg ob "$target_outbound" '
            (.route.rules[] | select(.outbound == $ob)) |= del(.rule_set)
          ' "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
          ;;
      esac
    else
      jq --argjson arr "$json_array" --arg ob "$target_outbound" --arg channel "$route_channel" '
        ($arr | map(gsub("^geosite-";"") | gsub("\\.srs$";""))) as $clean_arr
        | ($clean_arr | map("geosite-" + .)) as $tags
        | ($clean_arr | map({
            "tag": ("geosite-" + .),
            "type": "remote",
            "format": "binary",
            "url": ("https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/" + . + ".srs"),
            "download_detour": "direct"
          })) as $new_rulesets
        | .route.rule_set = (((.route.rule_set // []) + $new_rulesets) | unique_by(.tag))
        | if $channel == "w4" then
            (if any(.route.rules[]; .strategy == "prefer_ipv4") then (.route.rules[] | select(.strategy == "prefer_ipv4")).rule_set = $tags else .route.rules += [{"strategy": "prefer_ipv4", "rule_set": $tags}] end) |
            (if any(.route.rules[]; .outbound == "warp-out") then (.route.rules[] | select(.outbound == "warp-out")).rule_set = $tags else .route.rules += [{"outbound": "warp-out", "rule_set": $tags}] end)
          elif $channel == "w6" then
            (if any(.route.rules[]; .strategy == "prefer_ipv6") then (.route.rules[] | select(.strategy == "prefer_ipv6")).rule_set = $tags else .route.rules += [{"strategy": "prefer_ipv6", "rule_set": $tags}] end) |
            (if any(.route.rules[]; .outbound == "warp-out") then (.route.rules[] | select(.outbound == "warp-out")).rule_set = $tags else .route.rules += [{"outbound": "warp-out", "rule_set": $tags}] end)
          elif $channel == "s4" then
            (if any(.route.rules[]; .strategy == "prefer_ipv4") then (.route.rules[] | select(.strategy == "prefer_ipv4")).rule_set = $tags else .route.rules += [{"strategy": "prefer_ipv4", "rule_set": $tags}] end) |
            (if any(.route.rules[]; .outbound == "socks-out") then (.route.rules[] | select(.outbound == "socks-out")).rule_set = $tags else .route.rules += [{"outbound": "socks-out", "rule_set": $tags}] end)
          elif $channel == "s6" then
            (if any(.route.rules[]; .strategy == "prefer_ipv6") then (.route.rules[] | select(.strategy == "prefer_ipv6")).rule_set = $tags else .route.rules += [{"strategy": "prefer_ipv6", "rule_set": $tags}] end) |
            (if any(.route.rules[]; .outbound == "socks-out") then (.route.rules[] | select(.outbound == "socks-out")).rule_set = $tags else .route.rules += [{"outbound": "socks-out", "rule_set": $tags}] end)
          elif $channel == "ad4" then
            (if any(.route.rules[]; .outbound == "vps-outbound-v4") then (.route.rules[] | select(.outbound == "vps-outbound-v4")).rule_set = $tags else .route.rules += [{"outbound": "vps-outbound-v4", "rule_set": $tags}] end)
          elif $channel == "ad6" then
            (if any(.route.rules[]; .outbound == "vps-outbound-v6") then (.route.rules[] | select(.outbound == "vps-outbound-v6")).rule_set = $tags else .route.rules += [{"outbound": "vps-outbound-v6", "rule_set": $tags}] end)
          else
            if any(.route.rules[]; .outbound == $ob) then (.route.rules[] | select(.outbound == $ob)).rule_set = $tags else .route.rules += [{"outbound": $ob, "rule_set": $tags}] end
          end
      ' "$SBFOLDER/sb.json" > /tmp/sb.json && mv /tmp/sb.json "$SBFOLDER/sb.json"
    fi
  fi
  prune_orphaned_rule_sets
}

sbymfl() {
  sbport=$(cat "$SBFOLDER/warp-plus.log" "$SBFOLDER/sbwpph.log" 2>/dev/null | head -n 1 | awk '{print $3}' | awk -F":" '{print $NF}') 
  sbport=${sbport:-'40000'}
  local resv1=""
  local resv2=""
  local port_listening=false
  if command -v ss >/dev/null 2>&1; then
    if ss -tln | grep -q ":$sbport "; then
      port_listening=true
    fi
  elif command -v netstat >/dev/null 2>&1; then
    if netstat -tln | grep -q ":$sbport "; then
      port_listening=true
    fi
  fi
  if $port_listening; then
    resv1=$(curl -sm2 --socks5 localhost:$sbport icanhazip.com)
    resv2=$(curl -sm2 -x socks5h://localhost:$sbport icanhazip.com)
  fi
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
  extract_dom_jq='[ (.domain_suffix // [])[]? | select(. != "DuolaD") ]'
  extract_geo_jq='[ (.geosite // [])[]?, ((.rule_set // [])[]? | select(type=="string" and startswith("geosite-")) | sub("^geosite-";"")) ] | map(select(. != "DuolaD"))'
  
  wd4=$(echo "$clean_json" | jq -r "[ .route.rules[] | select(.outbound == \"warp-out\" or .strategy == \"prefer_ipv4\") | $extract_dom_jq ] | flatten | unique | join(\" \")" 2>/dev/null)
  args_wg4=$(echo "$clean_json" | jq -r "[ .route.rules[] | select(.outbound == \"warp-out\" or .strategy == \"prefer_ipv4\") | $extract_geo_jq ] | flatten | unique | join(\" \")" 2>/dev/null)
  
  wd6=$(echo "$clean_json" | jq -r "[ .route.rules[] | select(.outbound == \"warp-out\" or .strategy == \"prefer_ipv6\") | $extract_dom_jq ] | flatten | unique | join(\" \")" 2>/dev/null)
  args_wg6=$(echo "$clean_json" | jq -r "[ .route.rules[] | select(.outbound == \"warp-out\" or .strategy == \"prefer_ipv6\") | $extract_geo_jq ] | flatten | unique | join(\" \")" 2>/dev/null)
  
  sd4=$(echo "$clean_json" | jq -r "[ .route.rules[] | select(.outbound == \"socks-out\" or .strategy == \"prefer_ipv4\") | $extract_dom_jq ] | flatten | unique | join(\" \")" 2>/dev/null)
  sg4=$(echo "$clean_json" | jq -r "[ .route.rules[] | select(.outbound == \"socks-out\" or .strategy == \"prefer_ipv4\") | $extract_geo_jq ] | flatten | unique | join(\" \")" 2>/dev/null)
  
  sd6=$(echo "$clean_json" | jq -r "[ .route.rules[] | select(.outbound == \"socks-out\" or .strategy == \"prefer_ipv6\") | $extract_dom_jq ] | flatten | unique | join(\" \")" 2>/dev/null)
  sg6=$(echo "$clean_json" | jq -r "[ .route.rules[] | select(.outbound == \"socks-out\" or .strategy == \"prefer_ipv6\") | $extract_geo_jq ] | flatten | unique | join(\" \")" 2>/dev/null)
  
  ad4=$(echo "$clean_json" | jq -r "[ .route.rules[] | select(.outbound == \"vps-outbound-v4\") | $extract_dom_jq ] | flatten | unique | join(\" \")" 2>/dev/null)
  ag4=$(echo "$clean_json" | jq -r "[ .route.rules[] | select(.outbound == \"vps-outbound-v4\") | $extract_geo_jq ] | flatten | unique | join(\" \")" 2>/dev/null)
  
  ad6=$(echo "$clean_json" | jq -r "[ .route.rules[] | select(.outbound == \"vps-outbound-v6\") | $extract_dom_jq ] | flatten | unique | join(\" \")" 2>/dev/null)
  ag6=$(echo "$clean_json" | jq -r "[ .route.rules[] | select(.outbound == \"vps-outbound-v6\") | $extract_geo_jq ] | flatten | unique | join(\" \")" 2>/dev/null)

  if [[ -z "$wd4" && -z "$args_wg4" ]]; then
    wfl4="${yellow}【warp出站IPV4可用】未分流${plain}"
  else
    swd4=""; swg4=""
    [[ -n "$wd4" ]] && swd4="$wd4 "
    [[ -n "$args_wg4" ]] && swg4=$args_wg4
    wfl4="${yellow}【warp出站IPV4可用】已分流：$swd4$swg4${plain} "
  fi
  
  if [[ -z "$wd6" && -z "$args_wg6" ]]; then
    wfl6="${yellow}【warp出站IPV6自测】未分流${plain}"
  else
    swd6=""; swg6=""
    [[ -n "$wd6" ]] && swd6="$wd6 "
    [[ -n "$args_wg6" ]] && swg6=$args_wg6
    wfl6="${yellow}【warp出站IPV6自测】已分流：$swd6$swg6${plain} "
  fi
  
  if [[ -z "$sd4" && -z "$sg4" ]]; then
    sfl4="${yellow}【$warp_s4_ip】未分流${plain}"
  else
    ssd4=""; ssg4=""
    [[ -n "$sd4" ]] && ssd4="$sd4 "
    [[ -n "$sg4" ]] && ssg4=$sg4
    sfl4="${yellow}【$warp_s4_ip】已分流：$ssd4$ssg4${plain} "
  fi
  
  if [[ -z "$sd6" && -z "$sg6" ]]; then
    sfl6="${yellow}【$warp_s6_ip】未分流${plain}"
  else
    ssd6=""; ssg6=""
    [[ -n "$sd6" ]] && ssd6="$sd6 "
    [[ -n "$sg6" ]] && ssg6=$sg6
    sfl6="${yellow}【$warp_s6_ip】已分流：$ssd6$ssg6${plain} "
  fi
  
  if [[ -z "$ad4" && -z "$ag4" ]]; then
    adfl4="${yellow}【$vps_ipv4】未分流${plain}" 
  else
    sad4=""; sag4=""
    [[ -n "$ad4" ]] && sad4="$ad4 "
    [[ -n "$ag4" ]] && sag4=$ag4
    adfl4="${yellow}【$vps_ipv4】已分流：$sad4$sag4${plain} "
  fi
  
  if [[ -z "$ad6" && -z "$ag6" ]]; then
    adfl6="${yellow}【$vps_ipv6】未分流${plain}" 
  else
    sad6=""; sag6=""
    [[ -n "$ad6" ]] && sad6="$ad6 "
    [[ -n "$ag6" ]] && sag6=$ag6
    adfl6="${yellow}【$vps_ipv6】已分流：$sad6$sag6${plain} "
  fi
}

changefl() {
  sbactive
  blue "对所有协议进行统一的域名分流"
  blue "为确保分流可用，双栈IP（IPV4/IPV6）分流模式为优先模式"
  blue "warp-wireguard默认开启 (选项1与2)"
  blue "VPS本地出站分流 (选项3与4)"
  blue "动态代理与高级分流通道 (选项5及以上)"
  echo
  blue "当前Sing-box内核支持后缀域名与geosite/rule_set分流方式"
  echo
  yellow "注意："
  yellow "一、后缀域名方式只能填域名 (例：谷歌网站填写：google.com googleapis.com)"
  yellow "二、geosite方式须填写geosite规则名 (例：奈飞填写netflix ；迪士尼填写disney ；ChatGPT填写openai ；全局且绕过中国填写geolocation-!cn)"
  yellow "三、同一个完整域名或者geosite切勿重复分流"
  yellow "四、如分流通道中有个别通道无网络，所填分流为黑名单模式，即屏蔽该网站访问"
  changef
}

changef() {
  sbymfl
  echo
  green "1：重置warp-wireguard-ipv4优先分流域名 $wfl4"
  green "2：重置warp-wireguard-ipv6优先分流域名 $wfl6"
  green "3：重置VPS本地ipv4优先分流域名 $adfl4"
  green "4：重置VPS本地ipv6优先分流域名 $adfl6"

  init_warp_instances_db
  local clean_json=$(sed 's|^\s*//.*||g; s|[ \t]\+//.*||g' "$SBFOLDER/sb.json" 2>/dev/null)
  local dyn_idx=5
  declare -A inst_tags
  declare -A inst_descs
  declare -A inst_kinds
  declare -A inst_line_nums
  
  local has_dyn=0
  if [[ -s "$WARP_INST_FILE" || -s "$DNS_SNI_INST_FILE" ]]; then
    has_dyn=1
    echo -e "\n${blue}【已检测到的出栈通道】${plain}"
  fi

  if [ -s "$WARP_INST_FILE" ]; then
    while IFS='|' read -r i_port i_type i_country i_tag i_status; do
      [[ -z "$i_port" || "$i_status" != "running" ]] && continue
      local country_disp="$i_country"
      [[ "$country_disp" == "NONE" || -z "$country_disp" ]] && country_disp="local"
      local cur_domain=$(echo "$clean_json" | jq -r --arg ob "$i_tag" "[ .route.rules[] | select(.outbound == \$ob) | $extract_dom_jq ] | flatten | unique | join(\" \")" 2>/dev/null)
      local cur_geo=$(echo "$clean_json" | jq -r --arg ob "$i_tag" "[ .route.rules[] | select(.outbound == \$ob) | $extract_geo_jq ] | flatten | unique | join(\" \")" 2>/dev/null)
      local cur_rule=""
      [[ -n "$cur_domain" ]] && cur_rule="$cur_domain"
      if [[ -n "$cur_geo" ]]; then
        [[ -n "$cur_rule" ]] && cur_rule="$cur_rule $cur_geo" || cur_rule="$cur_geo"
      fi
      local fl_status=""
      if [[ -z "$cur_rule" ]]; then
        fl_status="${yellow}未分流${plain}"
      else
        fl_status="${yellow}已分流：$cur_rule${plain}"
      fi
      green "$dyn_idx：重置 [Socks5代理] 通道 [$i_tag] (端口:$i_port/国家:$country_disp/类型:$i_type) 分流 $fl_status"
      inst_tags[$dyn_idx]="$i_tag"
      inst_descs[$dyn_idx]="$i_tag(端口:$i_port)"
      inst_kinds[$dyn_idx]="socks"
      ((dyn_idx++))
    done < "$WARP_INST_FILE"
  fi

  if [ -s "$DNS_SNI_INST_FILE" ]; then
    local dns_sni_line_cnt=1
    while IFS='|' read -r r_mode r_port r_target r_domains r_tag r_status r_rule_type r_geosites; do
      if [[ -z "$r_mode" || "$r_status" != "running" ]]; then
        ((dns_sni_line_cnt++))
        continue
      fi
      local dom_str=$(echo "$r_domains" | tr ',' ' ')
      local geo_str=$(echo "$r_geosites" | tr ',' ' ')
      local cur_rule=""
      [[ -n "$dom_str" ]] && cur_rule="$dom_str"
      [[ -n "$geo_str" ]] && { [[ -n "$cur_rule" ]] && cur_rule="$cur_rule $geo_str" || cur_rule="$geo_str"; }
      local fl_status=""
      if [[ -z "$cur_rule" ]]; then
        fl_status="${yellow}未分流${plain}"
      else
        fl_status="${yellow}已分流：$cur_rule${plain}"
      fi
      local kind_desc="DNS代理"
      [[ "$r_mode" == "sni" ]] && kind_desc="SNI反代"
      green "$dyn_idx：重置 [$kind_desc] 通道 [$r_tag] ($r_target) 分流 $fl_status"
      inst_tags[$dyn_idx]="$r_tag"
      inst_descs[$dyn_idx]="$kind_desc:$r_tag($r_target)"
      inst_kinds[$dyn_idx]="$r_mode"
      inst_line_nums[$dyn_idx]="$dns_sni_line_cnt"
      ((dyn_idx++))
      ((dns_sni_line_cnt++))
    done < "$DNS_SNI_INST_FILE"
  fi

  green "0：返回上层"
  echo
  readp "请选择：" menu
  
  if [ "$menu" = "1" ]; then
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
  elif [ "$menu" = "2" ]; then
    readp "1：使用后缀域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu
    if [ "$menu" = "1" ]; then
      readp "每个域名之间留空格，回车跳过表示重置清空warp-wireguard-ipv6的分流通道：" w6flym
      update_routing_rule "w6" "domain_suffix" "$w6flym"
      restartsb && changef
    elif [ "$menu" = "2" ]; then
      readp "每个域名之间留空格，回车跳过表示重置清空warp-wireguard-ipv6的分流通道：" w6flym
      update_routing_rule "w6" "geosite" "$w6flym"
      restartsb && changef
    else
      changef
    fi
  elif [ "$menu" = "3" ]; then
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
  elif [ "$menu" = "4" ]; then
    readp "1：使用后缀域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu
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
  elif [[ -n "${inst_tags[$menu]}" ]]; then
    local target_tag="${inst_tags[$menu]}"
    local target_desc="${inst_descs[$menu]}"
    local kind="${inst_kinds[$menu]}"

    if [[ "$kind" == "socks" ]]; then
      readp "1：使用后缀域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu_type
      if [ "$menu_type" = "1" ]; then
        readp "每个域名之间留空格，回车跳过表示重置清空 [$target_desc] 的分流通道：" dyn_flym
        update_routing_rule "$target_tag" "domain_suffix" "$dyn_flym"
        restartsb && changef
      elif [ "$menu_type" = "2" ]; then
        readp "每个域名之间留空格，回车跳过表示重置清空 [$target_desc] 的分流通道：" dyn_flym
        update_routing_rule "$target_tag" "geosite" "$dyn_flym"
        restartsb && changef
      else
        changef
      fi
    else
      local line_num="${inst_line_nums[$menu]}"
      local target_line=$(sed -n "${line_num}p" "$DNS_SNI_INST_FILE")
      if [[ -n "$target_line" ]]; then
        local r_mode=$(echo "$target_line" | cut -d'|' -f1)
        local r_port=$(echo "$target_line" | cut -d'|' -f2)
        local r_target=$(echo "$target_line" | cut -d'|' -f3)
        local r_domains=$(echo "$target_line" | cut -d'|' -f4)
        local r_tag=$(echo "$target_line" | cut -d'|' -f5)
        local r_status=$(echo "$target_line" | cut -d'|' -f6)
        local r_rule_type=$(echo "$target_line" | cut -d'|' -f7)
        local r_geosites=$(echo "$target_line" | cut -d'|' -f8)

        local dom_str=$(echo "$r_domains" | tr ',' ' ')
        local geo_str=$(echo "$r_geosites" | tr ',' ' ')

        readp "1：使用后缀域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu_type

        if [ "$menu_type" = "1" ]; then
          readp "每个域名之间留空格，回车跳过表示重置清空 [$target_desc] 的分流通道：" raw_doms
          local formatted_doms=$(echo "$raw_doms" | tr ',' ' ' | tr -s ' ' | tr ' ' ',' | sed 's/^,//; s/,$//')
          r_domains="$formatted_doms"
        elif [ "$menu_type" = "2" ]; then
          readp "每个域名之间留空格，回车跳过表示重置清空 [$target_desc] 的分流通道：" raw_geos
          local formatted_geos=$(echo "$raw_geos" | tr ',' ' ' | tr -s ' ' | tr ' ' ',' | sed 's/^,//; s/,$//')
          r_geosites="$formatted_geos"
        else
          changef
          return
        fi

        local new_line="${r_mode}|${r_port}|${r_target}|${r_domains}|${r_tag}|${r_status}|${r_rule_type}|${r_geosites}"
        sed -i "${line_num}c\\${new_line}" "$DNS_SNI_INST_FILE"
        rebuild_singbox_outbounds
        restartsb
        green "[$target_desc] 域名分流规则更新成功！"
        sleep 2
        changef
      fi
    fi
  else
    sb
  fi
}

restartsb() {
  sync_configs_from_sb_json
  if command -v apk >/dev/null 2>&1; then
    rc-service sing-box restart
    if rc-service caddy status 2>/dev/null | grep -q "started"; then
      write_caddyfile
      rc-service caddy restart
    fi
  else
    systemctl enable sing-box >/dev/null 2>&1
    systemctl start sing-box >/dev/null 2>&1
    systemctl restart sing-box >/dev/null 2>&1
    if systemctl is-active --quiet caddy 2>/dev/null; then
      write_caddyfile
      systemctl restart caddy
    fi
  fi
}

# --- Local WARP plus Socks5 Proxy Manager (Multi-Instance) ---
inswarpplus() {
  sbactive
  init_warp_instances_db

  find_free_port() {
    local start_port=${1:-40000}
    local port=$start_port
    while true; do
      if [[ -z $(ss -tunlp 2>/dev/null | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
        echo "$port"
        return 0
      fi
      port=$((port+1))
    done
  }

  ensure_usque() {
    if [ ! -e "/usr/local/bin/usque" ]; then
      green "正在下载 Usque 二进制文件..."
      case $(uname -m) in
        aarch64) cpu=arm64;;
        x86_64) cpu=amd64;;
        *) red "不支持的架构" && return 1;;
      esac
      local usque_latest=$(curl -sL "https://api.github.com/repos/Diniboy1123/usque/releases/latest" | grep -oP '"tag_name":\s*"v\K[^"]+' | tr -d 'v')
      usque_latest=${usque_latest:-'3.0.1'}
      curl -L -o "$SBFOLDER/usque.zip" -# --retry 2 "https://github.com/Diniboy1123/usque/releases/download/v${usque_latest}/usque_${usque_latest}_linux_${cpu}.zip"
      unzip -o "$SBFOLDER/usque.zip" -d "$SBFOLDER/" usque >/dev/null 2>&1
      mv -f "$SBFOLDER/usque" "/usr/local/bin/usque"
      chmod +x "/usr/local/bin/usque"
      rm -f "$SBFOLDER/usque.zip"
    fi
  }

  ensure_warp_plus() {
    if [ ! -f "$SBFOLDER/warp-plus" ]; then
      green "正在下载 vwarp (warp-plus) 二进制文件..."
      case $(uname -m) in
        aarch64) cpu=arm64;;
        x86_64) cpu=amd64;;
        *) red "不支持的架构" && return 1;;
      esac
      local vwarp_latest=$(curl -sL --max-time 10 "https://api.github.com/repos/voidr3aper-anon/Vwarp/releases/latest" | grep -oP '"tag_name":\s*"\K[^"]+')
      vwarp_latest=${vwarp_latest:-"v2.2.2"}
      curl -L -o "$SBFOLDER/warp-plus.zip" -# --retry 2 "https://github.com/voidr3aper-anon/Vwarp/releases/download/${vwarp_latest}/vwarp_linux-${cpu}.zip"
      unzip -o "$SBFOLDER/warp-plus.zip" -d "$SBFOLDER/warp_plus_temp" >/dev/null 2>&1
      mv -f "$SBFOLDER/warp_plus_temp/vwarp" "$SBFOLDER/warp-plus"
      chmod +x "$SBFOLDER/warp-plus"
      rm -rf "$SBFOLDER/warp-plus.zip" "$SBFOLDER/warp_plus_temp"
    fi
  }

  ensure_gost() {
    if [ ! -e "/usr/local/bin/gost" ]; then
      green "正在下载 Gost 二进制文件..."
      local cpu_gost=""
      case $(uname -m) in
        aarch64) cpu_gost=arm64;;
        x86_64) cpu_gost=amd64;;
        *) red "不支持的架构" && return 1;;
      esac
      local gost_latest=$(curl -sL "https://api.github.com/repos/go-gost/gost/releases/latest" | grep -oP '"tag_name":\s*"\K[^"]+')
      local gost_ver=${gost_latest#v}
      gost_ver=${gost_ver:-'2.11.5'}
      curl -L -o "$SBFOLDER/gost.tar.gz" -# --retry 2 "https://github.com/go-gost/gost/releases/download/v${gost_ver}/gost_${gost_ver}_linux_${cpu_gost}.tar.gz"
      tar -zxf "$SBFOLDER/gost.tar.gz" -C "$SBFOLDER" gost >/dev/null 2>&1
      mv -f "$SBFOLDER/gost" "/usr/local/bin/gost"
      chmod +x "/usr/local/bin/gost"
      rm -f "$SBFOLDER/gost.tar.gz"
    fi
  }

  list_warp_instances() {
    init_warp_instances_db
    
    local has_socks=0
    local has_dns_sni=0
    [[ -s "$WARP_INST_FILE" ]] && has_socks=1
    [[ -s "$DNS_SNI_INST_FILE" ]] && has_dns_sni=1

    echo -e "${blue}----------------------------------------------------------------------------------${plain}"
    if [[ $has_socks -eq 0 && $has_dns_sni -eq 0 ]]; then
      echo -e "${yellow} 暂无运行中的 Socks5 代理实例或分流规则。${plain}"
    else
      local count=1

      if [[ $has_socks -eq 1 ]]; then
        while IFS='|' read -r i_port i_type i_country i_tag i_status; do
          [[ -z "$i_port" ]] && continue
          local type_str="Socks5"
          [[ "$i_type" != "NONE" && -n "$i_type" ]] && type_str="Socks5($i_type)"
          printf " ${green}[%-2d]${plain}  %-16s  %-20s  %-26s  ${green}%s${plain}\n" \
            "$count" "$type_str" "端口: $i_port" "Tag: $i_tag" "已启动"
          ((count++))
        done < "$WARP_INST_FILE"
      fi

      if [[ $has_dns_sni -eq 1 ]]; then
        while IFS='|' read -r r_mode r_port r_target r_domains r_tag r_status r_rule_type; do
          [[ -z "$r_mode" ]] && continue
          local display_type="DNS代理"
          [[ "$r_mode" == "sni" ]] && display_type="SNI反代"
          printf " ${green}[%-2d]${plain}  %-16s  %-20s  %-26s  ${green}%s${plain}\n" \
            "$count" "$display_type" "目标: $r_target" "Tag: $r_tag" "已启动"
          ((count++))
        done < "$DNS_SNI_INST_FILE"
      fi
    fi
    echo -e "${blue}----------------------------------------------------------------------------------${plain}"
  }

  add_new_instance() {
    echo -e "\n${blue}【添加新的出站/分流规则】${plain}"
    yellow "1：本地 WARP VPN  (Usque / WARP-cli)"
    yellow "2：多地区 Psiphon VPN / Psiphon VPN + WARP VPN"
    yellow "3：DNS代理"
    yellow "4：SNI反向代理"
    yellow "0：返回"
    readp "请选择【0-4】：" sub_mode

    local inst_type=""
    local inst_country="local"
    local inst_tag=""

    if [ "$sub_mode" = "1" ]; then
      echo
      blue "请选择本地 WARP 代理方案："
      green "1. Usque (开源轻量客户端，默认，支持 MASQUE 协议)"
      green "2. WARP-cli (官方客户端)"
      readp "请选择【1-2】（默认 1）：" warp_choice
      warp_choice=${warp_choice:-1}
      inst_type="usque"
      [[ "$warp_choice" == "2" ]] && inst_type="warp-cli"

    elif [ "$sub_mode" = "2" ]; then
      echo
      blue "请选择多地区代理方案："
      green "1：Psiphon VPN直连"
      green "2：Psiphon VPN + WARP VPN"
      green "0：返回"
      readp "请选择【0-2】：" cfon_choice

      if [ "$cfon_choice" = "1" ]; then
        inst_type="psiphon"
      elif [ "$cfon_choice" = "2" ]; then
        inst_type="chain"
      else
        return
      fi

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
      readp "输入目标国家/地区代码（如 US、JP、SG，默认 US）：" inst_country
      inst_country=${inst_country:-US}
      inst_country=$(echo "$inst_country" | tr 'a-z' 'A-Z')

    elif [ "$sub_mode" = "3" ]; then
      echo -e "\n${blue}【添加 DNS 代理服务实例】${plain}"
      readp "输入自定义 DNS 服务器 IP (例如 1.2.3.4): " dns_ip
      [[ -z "$dns_ip" ]] && red "IP 不能为空！" && return
      readp "输入 DNS 端口 (默认 53): " dns_port
      dns_port=${dns_port:-53}

      local dns_tag="dns-udp-${dns_ip}-${dns_port}"
      echo "dns|${dns_port}|${dns_ip}:${dns_port}||${dns_tag}|running|domain|" >> "$DNS_SNI_INST_FILE"
      rebuild_singbox_outbounds
      restartsb
      green "DNS 代理服务 [$dns_tag] 已成功创建！请前往【主菜单 5】绑定域名分流规则。"
      sleep 2
      return

    elif [ "$sub_mode" = "4" ]; then
      echo -e "\n${blue}【添加 SNI 反向代理服务实例】${plain}"
      readp "输入分流的反代/解锁 IP (例如 154.xxx.xxx.xxx): " sni_ip
      [[ -z "$sni_ip" ]] && red "IP 不能为空！" && return

      local sni_tag="sni-hosts-${sni_ip}"
      echo "sni|443|${sni_ip}||${sni_tag}|running|domain|" >> "$DNS_SNI_INST_FILE"
      rebuild_singbox_outbounds
      restartsb
      green "SNI 反向代理服务 [$sni_tag] 已成功创建！请前往【主菜单 5】绑定域名分流规则。"
      sleep 2
    else
      return
    fi

    local rec_port=$(find_free_port 40000)
    readp "自定义该实例 Socks5 监听端口（默认推荐 $rec_port）：" inst_port
    inst_port=${inst_port:-$rec_port}

    until [[ -z $(ss -tunlp 2>/dev/null | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$inst_port") ]]; do
      yellow "端口 $inst_port 被占用，请重新输入端口"
      readp "自定义端口:" inst_port
    done

    inst_tag="socks-${inst_type}"
    [[ "$inst_country" != "NONE" ]] && inst_tag="socks-${inst_type}-${inst_country}-${inst_port}" || inst_tag="socks-${inst_type}-${inst_port}"

    v4v6
    local sw46=4
    [[ -z "$v4" ]] && sw46=6

    green "正在启动代理实例 (端口: $inst_port, 类型: $inst_type)..."

    case "$inst_type" in
      usque)
        ensure_usque
        local inst_usque_conf="$SBFOLDER/usque_${inst_port}.json"
        if [ ! -f "$inst_usque_conf" ]; then
          echo "y" | /usr/local/bin/usque register -c "$inst_usque_conf" >/dev/null 2>&1
        fi
        nohup /usr/local/bin/usque socks -c "$inst_usque_conf" -b 127.0.0.1 -p "$inst_port" >/dev/null 2>&1 &
        ;;
      warp-cli)
        if ! command -v warp-cli >/dev/null 2>&1; then
          red "当前未安装 WARP-cli，请先手动安装 warp-cli 后重试！"
          return 1
        fi
        warp-cli mode proxy >/dev/null 2>&1
        warp-cli proxy port "$inst_port" >/dev/null 2>&1
        warp-cli connect >/dev/null 2>&1
        ;;
      psiphon)
        ensure_warp_plus
        nohup "$SBFOLDER/warp-plus" -b "127.0.0.1:$inst_port" --cfon --country "$inst_country" -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1 &
        ;;
      chain)
        ensure_usque
        ensure_warp_plus
        ensure_gost

        local vwarp_p=$(find_free_port 50000)
        local gost_p=$(find_free_port 12345)
        local inst_usque_conf="$SBFOLDER/usque_${inst_port}.json"

        if [ ! -f "$inst_usque_conf" ]; then
          echo "y" | /usr/local/bin/usque register -c "$inst_usque_conf" >/dev/null 2>&1
        fi

        jq --argjson gp "$gost_p" '.endpoint_h2_v4 = "127.0.0.1" | .endpoint_h2_v6 = "::1"' "$inst_usque_conf" > "$inst_usque_conf.tmp" && mv -f "$inst_usque_conf.tmp" "$inst_usque_conf"

        nohup "$SBFOLDER/warp-plus" -b "127.0.0.1:$vwarp_p" --cfon --country "$inst_country" -$sw46 --endpoint 162.159.192.1:2408 >/dev/null 2>&1 &
        sleep 5
        nohup /usr/local/bin/gost -D -L "tcp://127.0.0.1:$gost_p/162.159.198.2:443" -L "tcp://[::1]:$gost_p/162.159.198.2:443" -F "socks5://127.0.0.1:$vwarp_p" >/dev/null 2>&1 &
        sleep 2
        nohup /usr/local/bin/usque socks -c "$inst_usque_conf" -b 127.0.0.1 -p "$inst_port" --http2 --connect-port "$gost_p" >/dev/null 2>&1 &
        ;;
    esac

    green "正在检测实例 IP 连通性，请稍等 15 秒..."
    sleep 15
    local check_ip=$(curl -sm10 --socks5 "127.0.0.1:$inst_port" ifconfig.me 2>/dev/null || curl -sm10 -x socks5h://127.0.0.1:$inst_port ifconfig.me 2>/dev/null)
    if [[ -z "$check_ip" ]]; then
      red "错误：实例启动超时或 IP 获取失败！已被直接清理，不保存该出站记录。"
      local pids=$(ss -tunlp 2>/dev/null | grep -w "$inst_port" | grep -oP 'pid=\K[0-9]+' | sort -u)
      if [[ -n "$pids" ]]; then
        echo "$pids" | xargs kill -9 2>/dev/null
      fi
      rm -f "$SBFOLDER/usque_${inst_port}.json"
      sleep 2
      return 1
    else
      green "实例获取出口 IP 成功：$check_ip"
      echo "${inst_port}|${inst_type}|${inst_country}|${inst_tag}|running" >> "$WARP_INST_FILE"
      rebuild_singbox_outbounds
      restartsb
      green "代理实例 [$inst_tag] 已成功创建并写入 Sing-Box 出站！"
      sleep 2
    fi
  }

  remove_instance() {
    list_warp_instances
    local total_socks=0
    local total_dns_sni=0
    [[ -s "$WARP_INST_FILE" ]] && total_socks=$(grep -c '|' "$WARP_INST_FILE")
    [[ -s "$DNS_SNI_INST_FILE" ]] && total_dns_sni=$(grep -c '|' "$DNS_SNI_INST_FILE")
    local total_count=$((total_socks + total_dns_sni))

    if [[ $total_count -eq 0 ]]; then
      return
    fi

    readp "请输入要删除/停止的实例序号：" del_idx
    [[ -z "$del_idx" ]] && return

    if ! [[ "$del_idx" =~ ^[0-9]+$ ]] || [ "$del_idx" -lt 1 ] || [ "$del_idx" -gt "$total_count" ]; then
      red "无效的序号！"
      return
    fi

    if [ "$del_idx" -le "$total_socks" ]; then
      local target_line=$(sed -n "${del_idx}p" "$WARP_INST_FILE")
      local del_port=$(echo "$target_line" | cut -d'|' -f1)
      local del_tag=$(echo "$target_line" | cut -d'|' -f4)

      green "正在停止端口 $del_port (Tag: $del_tag) 上的代理进程..."
      local pids=$(ss -tunlp 2>/dev/null | grep -w "$del_port" | grep -oP 'pid=\K[0-9]+' | sort -u)
      [[ -n "$pids" ]] && echo "$pids" | xargs kill -9 2>/dev/null
      sed -i "${del_idx}d" "$WARP_INST_FILE"
      rm -f "$SBFOLDER/usque_${del_port}.json"
      jq --arg ob "$del_tag" '.route.rules = [.route.rules[] | select(.outbound != $ob)]' "$SBFOLDER/sb.json" > /tmp/sb.json 2>/dev/null && mv /tmp/sb.json "$SBFOLDER/sb.json"
      green "实例 [$del_tag] 已成功停止并删除！"
    else
      local dns_sni_idx=$((del_idx - total_socks))
      local target_line=$(sed -n "${dns_sni_idx}p" "$DNS_SNI_INST_FILE")
      local del_tag=$(echo "$target_line" | cut -d'|' -f5)
      sed -i "${dns_sni_idx}d" "$DNS_SNI_INST_FILE"
      green "分流规则 [$del_tag] 已成功删除！"
    fi

    rebuild_singbox_outbounds
    restartsb
    sleep 2
  }

  test_outbound_connectivity() {
    local socks_list=()
    local tag_list=()
    local type_list=()
    local count=0

    if [ -s "$WARP_INST_FILE" ]; then
      while IFS='|' read -r i_port i_type i_country i_tag i_status; do
        [ -z "$i_port" ] && continue
        count=$((count + 1))
        socks_list+=("$i_port")
        tag_list+=("$i_tag")
        local t_str="Socks5"
        [[ "$i_type" != "NONE" && -n "$i_type" ]] && t_str="Socks5($i_type)"
        type_list+=("$t_str")
      done < "$WARP_INST_FILE"
    fi

    local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
    local has_warp_out=$(echo "$clean_json" | jq '.endpoints[]? | select(.type == "wireguard") | .tag // empty' 2>/dev/null)
    if [ -n "$has_warp_out" ]; then
      count=$((count + 1))
      socks_list+=("wireguard_warp")
      tag_list+=("warp-out")
      type_list+=("WireGuard出站")
    fi

    if [ $count -eq 0 ]; then
      echo
      yellow "当前暂无已启动的出站代理或 WireGuard 节点可供测试！"
      sleep 2
      return
    fi

    while true; do
      echo
      echo -e "${blue}==================================================================================${plain}"
      echo -e "${blue}【出站连通性测试 (https://www.google.com/generate_204)】${plain}"
      echo
      for ((i=0; i<count; i++)); do
        local idx=$((i + 1))
        local extra=""
        if [ "${socks_list[$i]}" != "wireguard_warp" ]; then
          extra="端口: ${socks_list[$i]}"
        fi
        printf " ${green}[%-2d]${plain}  %-18s  %-18s  Tag: %-26s\n" "$idx" "${type_list[$i]}" "$extra" "${tag_list[$i]}"
      done
      echo -e "${blue}----------------------------------------------------------------------------------${plain}"
      echo -e " ${yellow}[ A]  测试所有出栈 (全测)${plain}"
      echo -e " ${yellow}[ 0]  返回上层${plain}"
      echo -e "${blue}==================================================================================${plain}"
      readp "请输入要测试的出栈编号 [1-${count}] 或 A (全测)，返回输入 0：" t_choice

      if [ "$t_choice" = "0" ] || [ -z "$t_choice" ]; then
        break
      elif [[ "$t_choice" =~ ^[Aa]$ ]]; then
        echo
        green "正在对所有 $count 个出栈进行 204 连通性测试..."
        echo
        for ((i=0; i<count; i++)); do
          local p="${socks_list[$i]}"
          local t="${tag_list[$i]}"
          echo -n -e "测试 [${t}] ... "
          if [ "$p" = "wireguard_warp" ]; then
            local test_res=$(test_warp_204)
            if [[ "$test_res" == *"204"* ]]; then
              green "$test_res"
            else
              red "$test_res"
            fi
          else
            local http_code=$(curl -s4m5 -o /dev/null -w "%{http_code}" --socks5 "127.0.0.1:$p" https://www.google.com/generate_204 2>/dev/null)
            if [ "$http_code" != "204" ]; then
              http_code=$(curl -s6m5 -o /dev/null -w "%{http_code}" --socks5 "127.0.0.1:$p" https://www.google.com/generate_204 2>/dev/null)
            fi
            if [ "$http_code" = "204" ]; then
              green "HTTP 204 (连通成功)"
            else
              red "失败 (HTTP ${http_code:-000} / 无法连通)"
            fi
          fi
        done
        echo
        readp "测试完毕，按回车键继续..." temp_input
      elif [[ "$t_choice" =~ ^[0-9]+$ ]] && [ "$t_choice" -ge 1 ] && [ "$t_choice" -le "$count" ]; then
        local i=$((t_choice - 1))
        local p="${socks_list[$i]}"
        local t="${tag_list[$i]}"
        echo
        echo -n -e "正在测试 [${t}] ... "
        if [ "$p" = "wireguard_warp" ]; then
          local test_res=$(test_warp_204)
          if [[ "$test_res" == *"204"* ]]; then
            green "$test_res"
          else
            red "$test_res"
          fi
        else
          local http_code=$(curl -s4m5 -o /dev/null -w "%{http_code}" --socks5 "127.0.0.1:$p" https://www.google.com/generate_204 2>/dev/null)
          if [ "$http_code" != "204" ]; then
            http_code=$(curl -s6m5 -o /dev/null -w "%{http_code}" --socks5 "127.0.0.1:$p" https://www.google.com/generate_204 2>/dev/null)
          fi
          if [ "$http_code" = "204" ]; then
            green "HTTP 204 (连通成功)"
          else
            red "失败 (HTTP ${http_code:-000} / 无法连通)"
          fi
        fi
        echo
        readp "测试完毕，按回车键继续..." temp_input
      else
        red "无效的选项！"
        sleep 1
      fi
    done
  }

  while true; do
    list_warp_instances
    echo -e "${yellow}1 : 添加新的出栈${plain}"
    echo -e "${yellow}2 : 测试出栈连通性 (204响应)${plain}"
    echo -e "${yellow}3 : 停止并删除指定编号的出栈${plain}"
    echo -e "${yellow}4 : 停止并清空所有出栈${plain}"
    echo -e "${yellow}0 : 返回主菜单${plain}"
    readp "请选择【0-4】：" m_choice
    case "$m_choice" in
      1)
        return_to_main_flag=0
        add_new_instance
        [[ "$return_to_main_flag" == "1" ]] && break
        ;;
      2) test_outbound_connectivity ;;
      3) remove_instance ;;
      4)
        sed -i 'd' "$WARP_INST_FILE"
        sed -i 'd' "$DNS_SNI_INST_FILE"
        ps -ef | grep -E '[s]bwpph|[w]arp-plus|[g]ost|[u]sque' | awk '{print $2}' | xargs kill -9 2>/dev/null
        rm -f "$SBFOLDER"/usque_*.json
        rebuild_singbox_outbounds
        restartsb
        green "已停止并清除所有出站与分流规则！"
        sleep 2
        break
        ;;
      0) break ;;
      *) break ;;
    esac
  done
  sb
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
  sbnh=$(echo "$inscore" | cut -d '.' -f 1,2)
}

upsbcroe() {
  sbactive
  lapre
  [[ $inscore =~ ^[0-9.]+$ ]] && lat="【已安装v$inscore】" || pre="【已安装v$inscore】"
  green "1：升级/切换Sing-box最新正式版 v$latcore  ${bblue}${lat}${plain}"
  green "2：升级/切换Sing-box最新测试版 v$precore  ${bblue}${pre}${plain}"
  green "3：切换Sing-box某个正式版或测试版，需指定版本号 (建议1.11.0及以上版本)"
  green "0：返回上层"
  readp "请选择【0-3】：" menu
  if [ "$menu" = "1" ]; then
    upcore=$(curl -Ls https://github.com/SagerNet/sing-box/releases/latest | grep -oP 'tag/v\K[0-9.]+' | head -n 1)
  elif [ "$menu" = "2" ]; then
    upcore=$(curl -Ls https://github.com/SagerNet/sing-box/releases | grep -oP '/tag/v\K[0-9.]+-[^"]+' | head -n 1)
  elif [ "$menu" = "3" ]; then
    echo
    red "注意: 版本号在 https://github.com/SagerNet/sing-box/tags 可查，且有Downloads字样 (建议1.11.0及以上版本)"
    green "正式版版本号格式：数字.数字.数字 (例：1.11.0)"
    green "测试版版本号格式：数字.数字.数字-alpha或rc或beta.数字 (例：1.13.0-alpha.1)"
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
  curl -sL "https://raw.githubusercontent.com/DuolaD/Sing-Box-DuolaD/main/version" | awk -F "更新内容" '{print $1}' | head -n 1 > "$SBFOLDER/v"
  green "Sing-box安装脚本升级成功" && sleep 5 && sb
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
    for svc in sing-box argo usque gost caddy; do
      rc-service "$svc" stop >/dev/null 2>&1
      rc-update del "$svc" default >/dev/null 2>&1
    done
    rm -rf /etc/init.d/{sing-box,argo,usque,gost,caddy}
  else
    for svc in sing-box argo usque gost caddy; do
      systemctl stop "$svc" >/dev/null 2>&1
      systemctl disable "$svc" >/dev/null 2>&1
    done
    rm -rf /etc/systemd/system/{sing-box.service,argo.service,usque.service,gost.service,caddy.service}
    systemctl daemon-reload >/dev/null 2>&1
  fi
  rm -f /usr/local/bin/usque /usr/local/bin/gost /usr/local/bin/caddy
  
  if [[ -d ~/.acme.sh ]]; then
    ~/.acme.sh/acme.sh --uninstall >/dev/null 2>&1
    rm -rf ~/.acme.sh >/dev/null 2>&1
  fi
  
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json" 2>/dev/null)
  local vm_listen_port=$(echo "$clean_json" | jq -r ' (.inbounds[] | select(.tag == "vmess-ws-sb") | .listen_port) // empty' 2>/dev/null)
  [ -n "$vm_listen_port" ] && ps -ef | grep "[l]ocalhost:$vm_listen_port" | awk '{print $2}' | xargs kill 2>/dev/null
  ps -ef | grep -E '[s]bwpph|[w]arp-plus|[g]ost|[u]sque|[c]loudflared|[c]addy' | awk '{print $2}' | xargs kill -9 2>/dev/null
  if command -v warp-cli >/dev/null 2>&1; then
    warp-cli disconnect >/dev/null 2>&1
    if pidof systemd >/dev/null 2>&1; then
      systemctl stop warp-svc >/dev/null 2>&1
      systemctl disable warp-svc >/dev/null 2>&1
    elif command -v rc-service >/dev/null 2>&1; then
      rc-service warp-svc stop >/dev/null 2>&1
      rc-update del warp-svc default >/dev/null 2>&1
    fi
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
  
  rm -rf "$SBFOLDER" /var/Sing-Box-DuolaD sbyg_update "$SCRIPT_SHORTCUT" /root/geoip.db /root/geosite.db /root/warpapi /root/warpip /root/websbox /root/tcpx.sh
  rm -f /etc/local.d/alpineargo.start /etc/local.d/alpinesub.start /etc/local.d/alpinews5.start /etc/local.d/alpinecaddy.start
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
  result_vl_vm_hy_tu
  allports
  sbymfl
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
  if [[ "$is_self_signed" = "true" ]]; then
    hy2_zs="自签证书"
  else
    hy2_zs="域名证书"
  fi
  # Argo detection
  argoym="未开启"
  local temp_argo_active=false
  local fixed_argo_active=false
  if [[ -n "$port_vm_ws" && -f "$SBFOLDER/argo.log" && -s "$SBFOLDER/argo.log" ]] && \
     ps -ef | grep -v grep | grep -q "cloudflared.*localhost:$port_vm_ws"; then
    temp_argo_active=true
  fi
  if [[ -f "$SBFOLDER/sbargoym.log" && -s "$SBFOLDER/sbargoym.log" ]] && \
     { systemctl is-active --quiet argo 2>/dev/null || rc-service argo status 2>/dev/null | grep -q "started"; }; then
    fixed_argo_active=true
  fi
  if $temp_argo_active || $fixed_argo_active; then
    argoym="已开启"
  fi

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

  init_warp_instances_db
  local has_socks=0
  local has_dns_sni=0
  [[ -s "$WARP_INST_FILE" ]] && has_socks=1
  [[ -s "$DNS_SNI_INST_FILE" ]] && has_dns_sni=1

  if [[ $has_socks -eq 0 && $has_dns_sni -eq 0 ]]; then
    echo -e "已出站通道状态：${yellow}未启动/无代理实例${plain}"
    echo -e "${blue}----------------------------------------------------------------------------------${plain}"
  else
    local total_count=0
    [[ $has_socks -eq 1 ]] && total_count=$((total_count + $(grep -c '|' "$WARP_INST_FILE")))
    [[ $has_dns_sni -eq 1 ]] && total_count=$((total_count + $(grep -c '|' "$DNS_SNI_INST_FILE")))
    echo -e "已出站通道状态：${green}已启动${plain} (共 ${total_count} 个出站通道)"
    echo -e "${blue}----------------------------------------------------------------------------------${plain}"
    local count=1

    if [[ $has_socks -eq 1 ]]; then
      while IFS='|' read -r i_port i_type i_country i_tag i_status; do
        [[ -z "$i_port" ]] && continue
        local type_str="Socks5"
        [[ "$i_type" != "NONE" && -n "$i_type" ]] && type_str="Socks5($i_type)"
        printf " ${green}[%-2d]${plain}  %-16s  %-20s  %-26s  ${green}%s${plain}\n" \
          "$count" "$type_str" "端口: $i_port" "Tag: $i_tag" "已启动"
        ((count++))
      done < "$WARP_INST_FILE"
    fi

    if [[ $has_dns_sni -eq 1 ]]; then
      while IFS='|' read -r r_mode r_port r_target r_domains r_tag r_status r_rule_type; do
        [[ -z "$r_mode" ]] && continue
        local display_type="DNS代理"
        [[ "$r_mode" == "sni" ]] && display_type="SNI反代"
        printf " ${green}[%-2d]${plain}  %-16s  %-20s  %-26s  ${green}%s${plain}\n" \
          "$count" "$display_type" "目标: $r_target" "Tag: $r_tag" "已启动"
        ((count++))
      done < "$DNS_SNI_INST_FILE"
    fi
    echo -e "${blue}----------------------------------------------------------------------------------${plain}"
  fi

  print_protocol_line() {
    local name="$1"
    local port="$2"
    local extra="$3"
    printf "🚀【 ${green}%-13s${plain} 】 端口:${yellow}%-5s${plain}  %s\n" "$name" "$port" "$extra"
  }

  echo -e "Sing-box节点关键信息、已分流域名情况如下："
  if [[ -n "$port_vl_re" ]]; then
    print_protocol_line "VLESS-Reality" "$port_vl_re" "Reality伪装域名: $vl_name"
  fi
  if [[ -n "$port_vl_ws_tls" ]]; then
    print_protocol_line "VLESS-WS-TLS" "$port_vl_ws_tls" "证书形式:$hy2_zs  路径: /${uuid_vl_ws}"
  fi
  if [[ -n "$port_vl_hu_tls" ]]; then
    print_protocol_line "VLESS-HU-TLS" "$port_vl_hu_tls" "证书形式:$hy2_zs  路径: /${uuid_vl_hu}"
  fi
  if [[ -n "$port_vm_ws" ]]; then
    print_protocol_line "VMess-WS" "$port_vm_ws" "不开启 TLS  路径: /${uuid_vm_ws}  Argo状态:$argoym"
  fi
  if [[ -n "$port_vm_ws_tls" ]]; then
    print_protocol_line "VMess-WS-TLS" "$port_vm_ws_tls" "证书形式:$hy2_zs  路径: /${uuid_vm_ws_tls}"
  fi
  if [[ -n "$port_vm_hu_tls" ]]; then
    print_protocol_line "VMess-HU-TLS" "$port_vm_hu_tls" "证书形式:$hy2_zs  路径: /${uuid_vm_hu_tls}"
  fi
  if [[ -n "$port_tr_tls" ]]; then
    print_protocol_line "Trojan-TLS" "$port_tr_tls" "证书形式:$hy2_zs"
  fi
  if [[ -n "$port_tr_ws_tls" ]]; then
    print_protocol_line "Trojan-WS-TLS" "$port_tr_ws_tls" "证书形式:$hy2_zs  路径: /${uuid_tr_ws_tls}"
  fi
  if [[ -n "$port_tr_hu_tls" ]]; then
    print_protocol_line "Trojan-HU-TLS" "$port_tr_hu_tls" "证书形式:$hy2_zs  路径: /${uuid_tr_hu_tls}"
  fi
  if [[ -n "$port_ss" ]]; then
    print_protocol_line "Shadowsocks" "$port_ss" "加密: ${ss_method:-2022-blake3-aes-128-gcm}"
  fi
  if [[ -n "$port_hy2" ]]; then
    print_protocol_line "Hysteria 2" "$port_hy2" "证书形式:$hy2_zs  转发多端口: $hy2zfport"
  fi
  if [[ -n "$port_tu" ]]; then
    print_protocol_line "Tuic-v5" "$port_tu" "证书形式:$hy2_zs  转发多端口: $tu5zfport"
  fi
  if [[ -n "$port_an" ]]; then
    print_protocol_line "Anytls" "$port_an" "证书形式:$hy2_zs"
  fi
  if [[ -n "$port_vm_tcp" ]]; then
    print_protocol_line "VMess-TCP" "$port_vm_tcp" "不开启 TLS"
  fi
  if [[ -n "$port_vm_http" ]]; then
    print_protocol_line "VMess-HTTP" "$port_vm_http" "不开启 TLS (HTTP伪装)"
  fi
  if [[ -n "$port_vm_quic" ]]; then
    print_protocol_line "VMess-QUIC" "$port_vm_quic" "证书形式:$hy2_zs"
  fi
  if [[ -n "$port_vm_h2_tls" ]]; then
    print_protocol_line "VMess-H2-TLS" "$port_vm_h2_tls" "证书形式:$hy2_zs  路径: /${uuid_vm_h2_tls}"
  fi
  if [[ -n "$port_vl_h2_tls" ]]; then
    print_protocol_line "VLESS-H2-TLS" "$port_vl_h2_tls" "证书形式:$hy2_zs  路径: /${uuid_vl_h2}"
  fi
  if [[ -n "$port_tr_h2_tls" ]]; then
    print_protocol_line "Trojan-H2-TLS" "$port_tr_h2_tls" "证书形式:$hy2_zs  路径: /${uuid_tr_h2_tls}"
  fi
  if [[ -n "$port_vl_h2_re" ]]; then
    print_protocol_line "VLESS-H2-Re" "$port_vl_h2_re" "Reality伪装域名: $vl_name  路径: /${uuid_vl_h2_re}"
  fi
  if [[ -n "$port_socks" ]]; then
    print_protocol_line "Socks" "$port_socks" "用户: ${socks_username}"
  fi

  if [ "$argoym" = "已开启" ]; then
    if ps -ef 2>/dev/null | grep -q "[l]ocalhost:$port_vm_ws"; then
      echo -e "Argo临时域名：${yellow}$(grep -a -o -E '[a-zA-Z0-9.-]+\.trycloudflare\.com' "$SBFOLDER/argo.log" 2>/dev/null | head -n 1)${plain}"
    fi
    if ps -ef 2>/dev/null | grep -q '[c]loudflared.*run'; then
      echo -e "Argo固定域名：${yellow}$(cat "$SBFOLDER/sbargoym.log" 2>/dev/null)${plain}"
    fi
  fi

  echo "------------------------------------------------------------------------------------"

  ww4="warp-wireguard-ipv4优先分流域名：$wfl4"
  ww6="warp-wireguard-ipv6优先分流域名：$wfl6"
  l4="VPS本地ipv4优先分流域名：$adfl4"
  l6="VPS本地ipv6优先分流域名：$adfl6"

  ymflzu=("ww4" "ww6" "l4" "l6")
  local all_unset=true
  for ymfl in "${ymflzu[@]}"; do
    if [[ ${!ymfl} != *"未"* ]]; then
      echo -e "${!ymfl}"
      all_unset=false
    fi
  done

  if [ -s "$WARP_INST_FILE" ]; then
    while IFS='|' read -r i_port i_type i_country i_tag i_status; do
      [[ -z "$i_port" || "$i_status" != "running" ]] && continue
      local cur_domain=$(echo "$clean_json" | jq -r --arg ob "$i_tag" "[ .route.rules[] | select(.outbound == \$ob) | $extract_dom_jq ] | flatten | unique | join(\" \")" 2>/dev/null)
      local cur_geo=$(echo "$clean_json" | jq -r --arg ob "$i_tag" "[ .route.rules[] | select(.outbound == \$ob) | $extract_geo_jq ] | flatten | unique | join(\" \")" 2>/dev/null)
      local cur_rule=""
      [[ -n "$cur_domain" ]] && cur_rule="$cur_domain"
      if [[ -n "$cur_geo" ]]; then
        [[ -n "$cur_rule" ]] && cur_rule="$cur_rule $cur_geo" || cur_rule="$cur_geo"
      fi
      if [[ -n "$cur_rule" ]]; then
        echo -e "动态 [Socks5代理] 通道 [${i_tag}] 分流域名：${yellow}已分流：$cur_rule${plain}"
        all_unset=false
      fi
    done < "$WARP_INST_FILE"
  fi

  if [ -s "$DNS_SNI_INST_FILE" ]; then
    while IFS='|' read -r r_mode r_port r_target r_domains r_tag r_status r_rule_type; do
      [[ -z "$r_mode" || "$r_status" != "running" ]] && continue
      r_rule_type=${r_rule_type:-"domain"}
      local cur_rule=$(echo "$r_domains" | tr ',' ' ')
      if [[ -n "$cur_rule" ]]; then
        local kind_desc="DNS代理"
        [[ "$r_mode" == "sni" ]] && kind_desc="SNI反代"
        echo -e "动态 [$kind_desc] 通道 [${r_tag}] 分流域名：${yellow}已分流：$cur_rule${plain}"
        all_unset=false
      fi
    done < "$DNS_SNI_INST_FILE"
  fi

  if $all_unset; then
    echo -e "未设置域名分流"
  fi
}

# --- Main Entry and Interface ---
instsllsingbox() {
  if [[ -f "$SBFOLDER/sb.json" ]]; then
    yellow "Sing-box 已安装，切勿重复安装！" && sleep 2 && sb
    return
  fi
  detect_system
  install_dependencies
  tun_check
  openyn
  inssb
  
  # Initialize flags for selected protocol combinations
  use_vl_re=false        # 1: VLESS-Reality
  use_vl_ws_tls=false    # 2: VLESS-WS-TLS
  use_vl_hu_tls=false    # 3: VLESS-HTTPUpgrade-TLS
  use_vm_ws=false        # 4: VMess-WS
  use_vm_ws_tls=false    # 5: VMess-WS-TLS
  use_vm_hu_tls=false    # 6: VMess-HTTPUpgrade-TLS
  use_tr_tls=false       # 7: Trojan-TLS
  use_tr_ws_tls=false    # 8: Trojan-WS-TLS
  use_tr_hu_tls=false    # 9: Trojan-HTTPUpgrade-TLS
  use_ss=false           # 10: Shadowsocks
  use_hy2=false          # 11: Hysteria 2
  use_tu=false           # 12: Tuic-v5
  use_an=false           # 13: AnyTLS
  use_vm_tcp=false       # 14: VMess-TCP
  use_vm_http=false      # 15: VMess-HTTP
  use_vm_quic=false      # 16: VMess-QUIC
  use_vm_h2_tls=false    # 17: VMess-H2-TLS
  use_vl_h2_tls=false    # 18: VLESS-H2-TLS
  use_tr_h2_tls=false    # 19: Trojan-H2-TLS
  use_vl_h2_re=false     # 20: VLESS-HTTP2-REALITY
  use_socks=false        # 21: Socks

  echo
  green "请选择需要安装的协议组合 (回车默认安装 1 7 18 19，或输入数字并用空格分隔，如 1 17 18)"
  green "--- VLESS 组合 ---"
  yellow " 1：VLESS-Reality (Vision + TCP)"
  yellow " 2：VLESS-WS-TLS (VLESS over WebSocket + TLS)"
  yellow " 3：VLESS-HTTPUpgrade-TLS (VLESS over HTTPUpgrade + TLS)"
  yellow " 4：VLESS-H2-TLS (VLESS over HTTP/2 + TLS)"
  yellow " 5：VLESS-HTTP2-REALITY (VLESS over HTTP/2 + REALITY)"
  green "--- VMess 组合 ---"
  yellow " 6：VMess-WS (VMess over WebSocket，不启用 TLS)"
  yellow " 7：VMess-WS-TLS (VMess over WebSocket + TLS)"
  yellow " 8：VMess-HTTPUpgrade-TLS (VMess over HTTPUpgrade + TLS)"
  yellow " 9：VMess-TCP (VMess over TCP，不启用 TLS)"
  yellow "10：VMess-HTTP (VMess over HTTP，不启用 TLS)"
  yellow "11：VMess-QUIC (VMess over QUIC，启用 TLS)"
  yellow "12：VMess-H2-TLS (VMess over HTTP/2 + TLS)"
  green "--- Trojan 组合 ---"
  yellow "13：Trojan-TLS (Trojan over TCP + TLS)"
  yellow "14：Trojan-WS-TLS (Trojan over WebSocket + TLS)"
  yellow "15：Trojan-HTTPUpgrade-TLS (Trojan over HTTPUpgrade + TLS)"
  yellow "16：Trojan-H2-TLS (Trojan over HTTP/2 + TLS)"
  green "--- 其他经典/高速协议 ---"
  yellow "17：Shadowsocks (Shadowsocks 多种加密)"
  yellow "18：Hysteria 2 (QUIC/UDP)"
  yellow "19：Tuic-v5 (QUIC/UDP)"
  yellow "20：AnyTLS"
  yellow "21：Socks (Socks5 代理服务)"
  readp "请选择【1-21】：" select_proto
  if [[ -z "$select_proto" ]]; then
    use_vl_re=true
    use_vm_ws_tls=true
    use_hy2=true
    use_tu=true
  else
    read -r -a proto_arr <<< "$select_proto"
    for item in "${proto_arr[@]}"; do
      item=$(echo "$item" | xargs)
      case "$item" in
        1) use_vl_re=true ;;
        2) use_vl_ws_tls=true ;;
        3) use_vl_hu_tls=true ;;
        4) use_vl_h2_tls=true ;;
        5) use_vl_h2_re=true ;;
        6) use_vm_ws=true ;;
        7) use_vm_ws_tls=true ;;
        8) use_vm_hu_tls=true ;;
        9) use_vm_tcp=true ;;
        10) use_vm_http=true ;;
        11) use_vm_quic=true ;;
        12) use_vm_h2_tls=true ;;
        13) use_tr_tls=true ;;
        14) use_tr_ws_tls=true ;;
        15) use_tr_hu_tls=true ;;
        16) use_tr_h2_tls=true ;;
        17) use_ss=true ;;
        18) use_hy2=true ;;
        19) use_tu=true ;;
        20) use_an=true ;;
        21) use_socks=true ;;
      esac
    done
  fi

  # Fallback if nothing was selected
  if [[ "$use_vl_re" = "false" && "$use_vl_ws_tls" = "false" && "$use_vl_hu_tls" = "false" && \
        "$use_vm_ws" = "false" && "$use_vm_ws_tls" = "false" && "$use_vm_hu_tls" = "false" && \
        "$use_tr_tls" = "false" && "$use_tr_ws_tls" = "false" && "$use_tr_hu_tls" = "false" && \
        "$use_ss" = "false" && "$use_hy2" = "false" && "$use_tu" = "false" && "$use_an" = "false" && \
        "$use_vm_tcp" = "false" && "$use_vm_http" = "false" && "$use_vm_quic" = "false" && \
        "$use_vm_h2_tls" = "false" && "$use_vl_h2_tls" = "false" && "$use_tr_h2_tls" = "false" && \
        "$use_vl_h2_re" = "false" && "$use_socks" = "false" ]]; then
    yellow "未选择任何协议，默认启用 VLESS-Reality 和 Hysteria 2"
    use_vl_re=true
    use_hy2=true
  fi

  if [[ "$use_ss" = "true" ]]; then
    echo
    green "请选择 Shadowsocks 加密方法："
    yellow "1：2022-blake3-aes-128-gcm (默认)"
    yellow "2：2022-blake3-aes-256-gcm"
    yellow "3：2022-blake3-chacha20-poly1305"
    yellow "4：aes-128-gcm"
    yellow "5：aes-256-gcm"
    yellow "6：chacha20-ietf-poly1305"
    yellow "7：xchacha20-ietf-poly1305"
    readp "请选择【1-7】：" ss_method_choice
    case "$ss_method_choice" in
      2) ss_method="2022-blake3-aes-256-gcm" ;;
      3) ss_method="2022-blake3-chacha20-poly1305" ;;
      4) ss_method="aes-128-gcm" ;;
      5) ss_method="aes-256-gcm" ;;
      6) ss_method="chacha20-ietf-poly1305" ;;
      7) ss_method="xchacha20-ietf-poly1305" ;;
      *) ss_method="2022-blake3-aes-128-gcm" ;;
    esac
    
    if [[ "$ss_method" == *"256"* || "$ss_method" == *"chacha20"* ]]; then
      ss_password=$("$SBFOLDER/sing-box" generate rand 32 --base64)
    else
      ss_password=$("$SBFOLDER/sing-box" generate rand 16 --base64)
    fi
  fi

  # Check if Reality, WS, HTTPUpgrade, or H2 transport is chosen
  local need_caddy_check=false
  if [[ "$use_vl_re" = "true" || "$use_vl_h2_re" = "true" || \
        "$use_vl_ws_tls" = "true" || "$use_vl_hu_tls" = "true" || "$use_vl_h2_tls" = "true" || \
        "$use_vm_ws" = "true" || "$use_vm_ws_tls" = "true" || "$use_vm_hu_tls" = "true" || "$use_vm_h2_tls" = "true" || \
        "$use_tr_ws_tls" = "true" || "$use_tr_hu_tls" = "true" || "$use_tr_h2_tls" = "true" ]]; then
    need_caddy_check=true
  fi

  use_caddy=false
  cert_type="self"
  ym_domain=""
  
  if $need_caddy_check; then
    local need_tls_caddy=false
    if [[ "$use_vl_ws_tls" = "true" || "$use_vl_hu_tls" = "true" || "$use_vl_h2_tls" = "true" || \
          "$use_vm_ws_tls" = "true" || "$use_vm_hu_tls" = "true" || "$use_vm_h2_tls" = "true" || \
          "$use_tr_ws_tls" = "true" || "$use_tr_hu_tls" = "true" || "$use_tr_h2_tls" = "true" ]]; then
      need_tls_caddy=true
    fi

    local port_443_in_use=false
    if ss -tunlp | grep -q -E ":443\b"; then
      port_443_in_use=true
    fi

    if $port_443_in_use; then
      echo
      yellow "警告：检测到端口 443 已被占用。"
      green "是否选择不使用 443 标准端口，转而直连 Sing-Box？"
      yellow "1：是，不使用 443 标准端口，转而直连 Sing-Box (回车默认)"
      yellow "2：否，回到协议选择界面"
      readp "请选择【1-2】：" caddy_choice
      if [[ "$caddy_choice" = "2" ]]; then
        instsllsingbox
        return
      else
        use_caddy=false
      fi
    else
      if $need_tls_caddy; then
        use_caddy=true
      fi
    fi
    
    if [[ "$use_caddy" == "true" ]]; then
      local cur_self_dom=$(get_self_domain)
      echo
      green "请选择 SSL 证书类型："
      yellow "1：自签证书 ($cur_self_dom) (回车默认)"
      yellow "2：纯 IP 证书 (由 Let's Encrypt 签发，需确保 VPS 80 端口开放且未被防火墙阻断)"
      yellow "3：域名证书 (自动 ACME 申请，自备已解析的域名)"
      readp "请选择【1-3】：" cert_menu
      case "$cert_menu" in
        2)
          cert_type="ip"
          select_ip_cert_mode
          ;;
        3)
          cert_type="domain"
          while true; do
            readp "请输入解析至当前 VPS 的域名：" ym_domain
            if [[ -z "$ym_domain" ]]; then
              red "域名不能为空，请重新输入！"
            else
              local resolved_ip=$(dig +short "$ym_domain" 2>/dev/null || nslookup "$ym_domain" 2>/dev/null | awk '/Address:/ {print $2}' | tail -n 1)
              if [[ -z "$resolved_ip" ]]; then
                resolved_ip=$(ping -c 1 -W 2 "$ym_domain" 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
              fi
              local server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null || curl -s4 ip.sb)
              if [[ -z "$resolved_ip" || "$resolved_ip" != "$server_ip" ]]; then
                red "检测到域名 $ym_domain 未解析到当前 VPS 外部 IP $server_ip (解析到的 IP 是: ${resolved_ip:-无})。"
                yellow "请先确保域名解析生效，或者输入 y 忽略并强制继续："
                readp "忽略并继续？[y/N]：" force_dns
                if [[ "$force_dns" =~ ^[Yy]$ ]]; then
                  break
                fi
              else
                blue "域名解析检测通过！"
                break
              fi
            fi
          done
          mkdir -p /var/Sing-Box-DuolaD
          echo "$ym_domain" > /var/Sing-Box-DuolaD/domain.log
          ;;
        *)
          cert_type="self"
          readp "请输入自签证书伪装域名 (回车默认使用 $cur_self_dom)：" custom_self_dom
          local self_dom=${custom_self_dom:-$cur_self_dom}
          mkdir -p /var/Sing-Box-DuolaD
          echo "$self_dom" > /var/Sing-Box-DuolaD/self_domain.log
          ;;
      esac
    fi
  fi

  if [[ "$use_vl_re" = "true" || "$use_vl_h2_re" = "true" ]]; then
    # Reality public/private keys
    reality_keys=$("$SBFOLDER/sing-box" generate reality-keypair)
    private_key=$(echo "$reality_keys" | awk '/PrivateKey/{print $NF}' | tr -d '"')
    public_key=$(echo "$reality_keys" | awk '/PublicKey/{print $NF}' | tr -d '"')
    echo "$private_key" > "$SBFOLDER/private.key"
    echo "$public_key" > "$SBFOLDER/public.key"
    short_id=$(openssl rand -hex 8)
  fi
  
  if [[ "$use_vl_ws_tls" = "true" || "$use_vl_hu_tls" = "true" || \
        "$use_vm_ws_tls" = "true" || "$use_vm_hu_tls" = "true" || \
        "$use_tr_tls" = "true" || "$use_tr_ws_tls" = "true" || "$use_tr_hu_tls" = "true" || \
        "$use_hy2" = "true" || "$use_tu" = "true" || "$use_an" = "true" || \
        "$use_vm_quic" = "true" || "$use_vm_h2_tls" = "true" || \
        "$use_vl_h2_tls" = "true" || "$use_tr_h2_tls" = "true" ]]; then
    if [[ "$use_caddy" == "true" ]]; then
      setup_caddy_cert
    else
      inscertificate
    fi
  fi
  insport
  
  pvk="g9I2sgUH6OCbIBTehkEfVEnuvInHYZvPOFhWchMLSc4="
  v6="2606:4700:110:860e:738f:b37:f15:d38d"
  res="[33,217,129]"
  
  detect_network_settings
  inssbjsonser
  sbservice
  caddyservice
  curl -sL "https://raw.githubusercontent.com/DuolaD/Sing-Box-DuolaD/main/version" | awk -F "更新内容" '{print $1}' | head -n 1 > "$SBFOLDER/v"
  lnsb
  cronsb
  
  wgcfgo
  sbshare "install"
  
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
  green "12. 管理 Cloudflare WARP"
  green "13. 管理出栈设置"
  green "14. 更换IP刷新本地IP、调整IPV4/IPV6配置输出"
  white "----------------------------------------------------------------------------------"
  green " 0. 退出脚本"
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  
  if [ -f "$SBFOLDER/v" ]; then
    insV=$(cat "$SBFOLDER/v" 2>/dev/null)
    latestV=$(curl -sL https://raw.githubusercontent.com/DuolaD/Sing-Box-DuolaD/main/version | awk -F "更新内容" '{print $1}' | head -n 1)
    if [ "$insV" = "$latestV" ]; then
      echo -e "当前 Sing-box 脚本最新版：${bblue}${insV}${plain} (已安装)"
    else
      echo -e "当前 Sing-box 脚本版本号：${bblue}${insV}${plain}"
      echo -e "检测到最新 Sing-box 脚本版本号：${yellow}${latestV}${plain} (可选择7进行更新)"
      echo -e "${yellow}$(curl -sL https://raw.githubusercontent.com/DuolaD/Sing-Box-DuolaD/main/version)${plain}"
    fi
  else
    latestV=$(curl -sL https://raw.githubusercontent.com/DuolaD/Sing-Box-DuolaD/main/version | awk -F "更新内容" '{print $1}' | head -n 1)
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
  
  if [ -f "$SBFOLDER/sb.json" ]; then
    local v4_6=""
    rpip=$(strip_json_comments "$SBFOLDER/sb.json" | jq -r '
      [
        (.route.rules[]? | select(.action == "resolve" and .strategy != null) | .strategy),
        (.route.rules[]? | select(.strategy != null) | .strategy),
        (.outbounds[]? | select(.domain_strategy != null) | .domain_strategy),
        (.dns.strategy? // empty)
      ] | map(select(. != null and . != "")) | first // empty
    ' 2>/dev/null)
    if [[ $rpip = 'prefer_ipv6' ]]; then
      v4_6="IPV6优先出站($showv6)"
    elif [[ $rpip = 'prefer_ipv4' ]]; then
      v4_6="IPV4优先出站($showv4)"
    elif [[ $rpip = 'ipv4_only' ]]; then
      v4_6="仅IPV4出站($showv4)"
    elif [[ $rpip = 'ipv6_only' ]]; then
      v4_6="仅IPV6出站($showv6)"
    else
      v4_6="默认/未设置"
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
  readp "请输入数字【0-14】:" Input
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
    12 ) cfwarp ;;
    13 ) inswarpplus ;;
    14 ) wgcfgo && sbshare ;;
     * ) exit ;;
  esac
}

# Start the script TUI
sb
