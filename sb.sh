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
SCRIPT_URL="https://raw.githubusercontent.com/DuolaD/sing-box/main/sb.sh"
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
generate_self_signed_cert() {
  local target_key="$1"
  local target_cert="$2"
  local domain="www.bing.com"
  
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
  ymzs() {
    ym_vl_re=apple.com
    echo
    blue "Vless-reality的SNI域名默认为 apple.com"
    tlsyn=true
    ym_domain=$(cat /root/ygkkkca/ca.log 2>/dev/null)
    certificatec='/root/ygkkkca/cert.crt'
    certificatep='/root/ygkkkca/private.key'
  }
  
  zqzs() {
    ym_vl_re=apple.com
    echo
    blue "Vless-reality的SNI域名默认为 apple.com"
    tlsyn=false
    ym_domain=www.bing.com
    certificatec="$SBFOLDER/cert.pem"
    certificatep="$SBFOLDER/private.key"
  }
  
  red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  green "二、生成并设置相关证书"
  echo
  blue "自动生成bing自签证书中……" && sleep 2
  generate_self_signed_cert "$SBFOLDER/private.key" "$SBFOLDER/cert.pem"
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
    yellow "1:: 否！继续使用自签的证书 (回车默认)"
    yellow "2:: 是！使用Acme-yg脚本申请Acme证书 (支持常规80端口模式与Dns API模式)"
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
    local cur_pvk=$(echo "$clean_js" | jq -r '((.outbounds[] | select(.type == "wireguard") | .private_key) // (.endpoints[] | select(.type == "wireguard") | .private_key) // empty)' 2>/dev/null | head -n 1)
    [[ -n "$cur_pvk" ]] && pvk="$cur_pvk"
    local cur_v6=$(echo "$clean_js" | jq -r '((.outbounds[] | select(.type == "wireguard") | .local_address[1]) // (.endpoints[] | select(.type == "wireguard") | .address[1]) // empty)' 2>/dev/null | cut -d/ -f1 | head -n 1)
    [[ -n "$cur_v6" ]] && v6="$cur_v6"
    local cur_res=$(echo "$clean_js" | jq -c '((.outbounds[] | select(.type == "wireguard") | .reserved) // (.endpoints[] | select(.type == "wireguard") | .peers[0].reserved) // empty)' 2>/dev/null | head -n 1)
    [[ -n "$cur_res" ]] && res="$cur_res"
    local cur_endip=$(echo "$clean_js" | jq -r '((.outbounds[] | select(.type == "wireguard") | .server) // (.endpoints[] | select(.type == "wireguard") | .peers[0].address) // empty)' 2>/dev/null | head -n 1)
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
    local cur_cert=$(echo "$clean_js" | jq -r '(.inbounds[] | select(.tls.certificate_path != null) | .tls.certificate_path) // empty' 2>/dev/null | head -n 1)
    [[ -n "$cur_cert" ]] && certificatec="$cur_cert"
    local cur_key=$(echo "$clean_js" | jq -r '(.inbounds[] | select(.tls.key_path != null) | .tls.key_path) // empty' 2>/dev/null | head -n 1)
    [[ -n "$cur_key" ]] && certificatep="$cur_key"
    local cur_ym=$(echo "$clean_js" | jq -r '(.inbounds[] | select(.tls.server_name != null and .tls.reality == null) | .tls.server_name) // empty' 2>/dev/null | head -n 1)
    [[ -n "$cur_ym" ]] && ym_domain="$cur_ym"
    local cur_vl_ym=$(echo "$clean_js" | jq -r '(.inbounds[] | select(.tls.reality != null) | .tls.server_name) // empty' 2>/dev/null | head -n 1)
    [[ -n "$cur_vl_ym" ]] && ym_vl_re="$cur_vl_ym"
    
    local cur_priv=$(echo "$clean_js" | jq -r '(.inbounds[] | select(.tls.reality != null) | .tls.reality.private_key) // empty' 2>/dev/null | head -n 1)
    [[ -n "$cur_priv" ]] && private_key="$cur_priv"
    local cur_pub=$(cat "$SBFOLDER/public.key" 2>/dev/null)
    [[ -n "$cur_pub" ]] && public_key="$cur_pub"
    local cur_sid=$(echo "$clean_js" | jq -r '(.inbounds[] | select(.tls.reality != null) | .tls.reality.short_id[0]) // empty' 2>/dev/null | head -n 1)
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
    if [[ -f "/root/ygkkkca/ca.log" && -f "/root/ygkkkca/cert.crt" ]]; then
      certificatec="/root/ygkkkca/cert.crt"
      certificatep="/root/ygkkkca/private.key"
      ym_domain=$(cat /root/ygkkkca/ca.log 2>/dev/null)
    elif [[ -f "$SBFOLDER/cert.pem" ]]; then
      certificatec="$SBFOLDER/cert.pem"
      certificatep="$SBFOLDER/private.key"
      ym_domain="www.bing.com"
    else
      certificatec="/etc/s-box/cert.pem"
      certificatep="/etc/s-box/private.key"
      ym_domain="www.bing.com"
    fi
  fi

  : ${ym_domain:="www.bing.com"}
  : ${ym_vl_re:="apple.com"}
  : ${certificatec:="/etc/s-box/cert.pem"}
  : ${certificatep:="/etc/s-box/private.key"}

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

  # Base 1.10 json
  local config_json_10='{
    "log": {
      "disabled": false,
      "level": "info",
      "timestamp": true
    },
    "inbounds": [],
    "outbounds": [
      {
        "type": "direct",
        "tag": "direct",
        "domain_strategy": "'"${ipv}"'"
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
        "server": "'"${endip}"'",
        "server_port": 2408,
        "local_address": [
          "172.16.0.2/32",
          "'"${v6}/128"'"
        ],
        "private_key": "'"${pvk}"'",
        "peer_public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
        "reserved": '"${res}"'
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
          "domain_suffix": ["yg_kkk"]
        },
        {
          "outbound": "warp-IPv6-out",
          "domain_suffix": ["yg_kkk"]
        },
        {
          "outbound": "socks-IPv4-out",
          "domain_suffix": ["yg_kkk"]
        },
        {
          "outbound": "socks-IPv6-out",
          "domain_suffix": ["yg_kkk"]
        },
        {
          "outbound": "vps-outbound-v4",
          "domain_suffix": ["yg_kkk"]
        },
        {
          "outbound": "vps-outbound-v6",
          "domain_suffix": ["yg_kkk"]
        },
        {
          "outbound": "direct",
          "network": "udp,tcp"
        }
      ]
    }
  }'

  # Base 1.11 json
  local config_json_11='{
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

  # Dynamically add selected inbounds to both templates
  if [[ "$use_vl_re" == "true" ]]; then
    config_json_10=$(echo "$config_json_10" | jq --argjson inb "$vl_re_inb" '.inbounds += [$inb]')
    config_json_11=$(echo "$config_json_11" | jq --argjson inb "$vl_re_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_vl_ws_tls" == "true" ]]; then
    config_json_10=$(echo "$config_json_10" | jq --argjson inb "$vl_ws_tls_inb" '.inbounds += [$inb]')
    config_json_11=$(echo "$config_json_11" | jq --argjson inb "$vl_ws_tls_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_vl_hu_tls" == "true" ]]; then
    config_json_10=$(echo "$config_json_10" | jq --argjson inb "$vl_hu_tls_inb" '.inbounds += [$inb]')
    config_json_11=$(echo "$config_json_11" | jq --argjson inb "$vl_hu_tls_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_vm_ws" == "true" ]]; then
    config_json_10=$(echo "$config_json_10" | jq --argjson inb "$vm_ws_inb" '.inbounds += [$inb]')
    config_json_11=$(echo "$config_json_11" | jq --argjson inb "$vm_ws_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_vm_ws_tls" == "true" ]]; then
    config_json_10=$(echo "$config_json_10" | jq --argjson inb "$vm_ws_tls_inb" '.inbounds += [$inb]')
    config_json_11=$(echo "$config_json_11" | jq --argjson inb "$vm_ws_tls_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_vm_hu_tls" == "true" ]]; then
    config_json_10=$(echo "$config_json_10" | jq --argjson inb "$vm_hu_tls_inb" '.inbounds += [$inb]')
    config_json_11=$(echo "$config_json_11" | jq --argjson inb "$vm_hu_tls_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_tr_tls" == "true" ]]; then
    config_json_10=$(echo "$config_json_10" | jq --argjson inb "$tr_tls_inb" '.inbounds += [$inb]')
    config_json_11=$(echo "$config_json_11" | jq --argjson inb "$tr_tls_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_tr_ws_tls" == "true" ]]; then
    config_json_10=$(echo "$config_json_10" | jq --argjson inb "$tr_ws_tls_inb" '.inbounds += [$inb]')
    config_json_11=$(echo "$config_json_11" | jq --argjson inb "$tr_ws_tls_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_tr_hu_tls" == "true" ]]; then
    config_json_10=$(echo "$config_json_10" | jq --argjson inb "$tr_hu_tls_inb" '.inbounds += [$inb]')
    config_json_11=$(echo "$config_json_11" | jq --argjson inb "$tr_hu_tls_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_ss" == "true" ]]; then
    config_json_10=$(echo "$config_json_10" | jq --argjson inb "$ss_inb" '.inbounds += [$inb]')
    config_json_11=$(echo "$config_json_11" | jq --argjson inb "$ss_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_hy2" == "true" ]]; then
    config_json_10=$(echo "$config_json_10" | jq --argjson inb "$hy2_inb" '.inbounds += [$inb]')
    config_json_11=$(echo "$config_json_11" | jq --argjson inb "$hy2_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_tu" == "true" ]]; then
    config_json_10=$(echo "$config_json_10" | jq --argjson inb "$tu_inb" '.inbounds += [$inb]')
    config_json_11=$(echo "$config_json_11" | jq --argjson inb "$tu_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_an" == "true" ]]; then
    config_json_10=$(echo "$config_json_10" | jq --argjson inb "$an_inb" '.inbounds += [$inb]')
    config_json_11=$(echo "$config_json_11" | jq --argjson inb "$an_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_vm_tcp" == "true" ]]; then
    config_json_10=$(echo "$config_json_10" | jq --argjson inb "$vm_tcp_inb" '.inbounds += [$inb]')
    config_json_11=$(echo "$config_json_11" | jq --argjson inb "$vm_tcp_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_vm_http" == "true" ]]; then
    config_json_10=$(echo "$config_json_10" | jq --argjson inb "$vm_http_inb" '.inbounds += [$inb]')
    config_json_11=$(echo "$config_json_11" | jq --argjson inb "$vm_http_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_vm_quic" == "true" ]]; then
    config_json_10=$(echo "$config_json_10" | jq --argjson inb "$vm_quic_inb" '.inbounds += [$inb]')
    config_json_11=$(echo "$config_json_11" | jq --argjson inb "$vm_quic_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_vm_h2_tls" == "true" ]]; then
    config_json_10=$(echo "$config_json_10" | jq --argjson inb "$vm_h2_tls_inb" '.inbounds += [$inb]')
    config_json_11=$(echo "$config_json_11" | jq --argjson inb "$vm_h2_tls_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_vl_h2_tls" == "true" ]]; then
    config_json_10=$(echo "$config_json_10" | jq --argjson inb "$vl_h2_tls_inb" '.inbounds += [$inb]')
    config_json_11=$(echo "$config_json_11" | jq --argjson inb "$vl_h2_tls_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_tr_h2_tls" == "true" ]]; then
    config_json_10=$(echo "$config_json_10" | jq --argjson inb "$tr_h2_tls_inb" '.inbounds += [$inb]')
    config_json_11=$(echo "$config_json_11" | jq --argjson inb "$tr_h2_tls_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_vl_h2_re" == "true" ]]; then
    config_json_10=$(echo "$config_json_10" | jq --argjson inb "$vl_h2_re_inb" '.inbounds += [$inb]')
    config_json_11=$(echo "$config_json_11" | jq --argjson inb "$vl_h2_re_inb" '.inbounds += [$inb]')
  fi
  if [[ "$use_socks" == "true" ]]; then
    config_json_10=$(echo "$config_json_10" | jq --argjson inb "$socks_inb" '.inbounds += [$inb]')
    config_json_11=$(echo "$config_json_11" | jq --argjson inb "$socks_inb" '.inbounds += [$inb]')
  fi

  echo "$config_json_10" > "$SBFOLDER/sb10.json"
  echo "$config_json_11" > "$SBFOLDER/sb11.json"

  if [[ "$sbnh" == "1.10" ]]; then
    cp "$SBFOLDER/sb10.json" "$SBFOLDER/sb.json"
  else
    cp "$SBFOLDER/sb11.json" "$SBFOLDER/sb.json"
  fi
  sync_configs_from_sb_json
}

# --- Caddy Helper Functions ---
write_caddyfile() {
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
  
  local port_vl_ws=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vless-ws-tls-sb") | .listen_port // empty' 2>/dev/null | head -n 1)
  local port_vl_hu=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vless-hu-tls-sb") | .listen_port // empty' 2>/dev/null | head -n 1)
  local port_vl_h2=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vless-h2-tls-sb") | .listen_port // empty' 2>/dev/null | head -n 1)
  local port_vm_ws_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vmess-ws-tls-sb") | .listen_port // empty' 2>/dev/null | head -n 1)
  local port_vm_hu_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vmess-hu-tls-sb") | .listen_port // empty' 2>/dev/null | head -n 1)
  local port_vm_h2_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vmess-h2-tls-sb") | .listen_port // empty' 2>/dev/null | head -n 1)
  local port_tr_ws_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "trojan-ws-tls-sb") | .listen_port // empty' 2>/dev/null | head -n 1)
  local port_tr_hu_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "trojan-hu-tls-sb") | .listen_port // empty' 2>/dev/null | head -n 1)
  local port_tr_h2_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "trojan-h2-tls-sb") | .listen_port // empty' 2>/dev/null | head -n 1)

  local path_vl_ws=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vless-ws-tls-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  local path_vl_hu=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vless-hu-tls-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  local path_vl_h2=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vless-h2-tls-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  local path_vm_ws_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vmess-ws-tls-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  local path_vm_hu_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vmess-hu-tls-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  local path_vm_h2_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "vmess-h2-tls-sb") | .users[0].uuid // empty' 2>/dev/null | head -n 1)
  local path_tr_ws_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "trojan-ws-tls-sb") | .users[0].password // empty' 2>/dev/null | head -n 1)
  local path_tr_hu_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "trojan-hu-tls-sb") | .users[0].password // empty' 2>/dev/null | head -n 1)
  local path_tr_h2_tls=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "trojan-h2-tls-sb") | .users[0].password // empty' 2>/dev/null | head -n 1)

  local cert_type=$(cat /etc/s-box/cert_type.log 2>/dev/null || echo "self")
  local server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null || curl -s4 ip.sb)
  local ym_domain=$(cat /root/ygkkkca/ca.log 2>/dev/null)
  
  local site_addr=":443"
  local tls_directive=""
  local global_options="admin off"
  
  if [[ "$cert_type" == "domain" && -n "$ym_domain" ]]; then
    site_addr="$ym_domain:443"
  elif [[ "$cert_type" == "ip" && -n "$server_ip" ]]; then
    site_addr="$server_ip:443"
    tls_directive="tls /etc/s-box/cert.pem /etc/s-box/private.key"
    global_options="admin off
  auto_https off"
  else
    site_addr=":443"
    tls_directive="tls /etc/s-box/cert.pem /etc/s-box/private.key"
    global_options="admin off
  auto_https off"
  fi

  mkdir -p /etc/caddy
  cat > /etc/caddy/Caddyfile <<EOF
{
  $global_options
}

$site_addr {
  $tls_directive
EOF

  if [[ -n "$port_vl_ws" && -n "$path_vl_ws" ]]; then
    echo "  reverse_proxy /$path_vl_ws 127.0.0.1:$port_vl_ws" >> /etc/caddy/Caddyfile
  fi
  if [[ -n "$port_vl_hu" && -n "$path_vl_hu" ]]; then
    echo "  reverse_proxy /$path_vl_hu 127.0.0.1:$port_vl_hu" >> /etc/caddy/Caddyfile
  fi
  if [[ -n "$port_vm_ws_tls" && -n "$path_vm_ws_tls" ]]; then
    echo "  reverse_proxy /$path_vm_ws_tls 127.0.0.1:$port_vm_ws_tls" >> /etc/caddy/Caddyfile
  fi
  if [[ -n "$port_vm_hu_tls" && -n "$path_vm_hu_tls" ]]; then
    echo "  reverse_proxy /$path_vm_hu_tls 127.0.0.1:$port_vm_hu_tls" >> /etc/caddy/Caddyfile
  fi
  if [[ -n "$port_tr_ws_tls" && -n "$path_tr_ws_tls" ]]; then
    echo "  reverse_proxy /$path_tr_ws_tls 127.0.0.1:$port_tr_ws_tls" >> /etc/caddy/Caddyfile
  fi
  if [[ -n "$port_tr_hu_tls" && -n "$path_tr_hu_tls" ]]; then
    echo "  reverse_proxy /$path_tr_hu_tls 127.0.0.1:$port_tr_hu_tls" >> /etc/caddy/Caddyfile
  fi

  if [[ -n "$port_vl_h2" && -n "$path_vl_h2" ]]; then
    cat >> /etc/caddy/Caddyfile <<EOF
  reverse_proxy /$path_vl_h2 https://127.0.0.1:$port_vl_h2 {
    transport http {
      tls_insecure_skip_verify
    }
  }
EOF
  fi
  if [[ -n "$port_vm_h2_tls" && -n "$path_vm_h2_tls" ]]; then
    cat >> /etc/caddy/Caddyfile <<EOF
  reverse_proxy /$path_vm_h2_tls https://127.0.0.1:$port_vm_h2_tls {
    transport http {
      tls_insecure_skip_verify
    }
  }
EOF
  fi
  if [[ -n "$port_tr_h2_tls" && -n "$path_tr_h2_tls" ]]; then
    cat >> /etc/caddy/Caddyfile <<EOF
  reverse_proxy /$path_tr_h2_tls https://127.0.0.1:$port_tr_h2_tls {
    transport http {
      tls_insecure_skip_verify
    }
  }
EOF
  fi

  echo "}" >> /etc/caddy/Caddyfile
}

setup_caddy_cert() {
  echo "$cert_type" > /etc/s-box/cert_type.log
  mkdir -p /etc/s-box
  
  if [[ "$cert_type" == "self" ]]; then
    blue "正在生成 Caddy 自签证书..."
    generate_self_signed_cert /etc/s-box/private.key /etc/s-box/cert.pem
    cp -f /etc/s-box/private.key "$SBFOLDER/private.key" 2>/dev/null
    cp -f /etc/s-box/cert.pem "$SBFOLDER/cert.pem" 2>/dev/null
    cp -f /etc/s-box/ca.pem "$SBFOLDER/ca.pem" 2>/dev/null
    is_self_signed=true
    tls_sni="www.bing.com"
    ym_domain="www.bing.com"
    certificatec="/etc/s-box/cert.pem"
    certificatep="/etc/s-box/private.key"
  elif [[ "$cert_type" == "ip" ]]; then
    local server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null || curl -s4 ip.sb)
    blue "正在使用 acme.sh 申请 IP 证书 ($server_ip)..."
    
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
      blue "正在安装 acme.sh..."
      curl -s https://get.acme.sh | sh >/dev/null 2>&1
    fi
    
    if ss -tunlp | grep -q -E ":80\b"; then
      yellow "警告：检测到 80 端口已被占用，临时停止冲突服务..."
      systemctl stop nginx caddy apache2 2>/dev/null
    fi
    
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force > /dev/null 2>&1
    ~/.acme.sh/acme.sh --register-account -m "caddy_singbox@gmail.com" > /dev/null 2>&1
    
    ~/.acme.sh/acme.sh --issue \
        -d "$server_ip" \
        --standalone \
        --server letsencrypt \
        --certificate-profile shortlived \
        --days 6 \
        --httpport 80 \
        --force
        
    if [[ $? -eq 0 ]]; then
      ~/.acme.sh/acme.sh --installcert --force -d "$server_ip" \
          --key-file "/etc/s-box/private.key" \
          --fullchain-file "/etc/s-box/cert.pem"
      chmod 600 /etc/s-box/private.key
      chmod 644 /etc/s-box/cert.pem
      cp -f /etc/s-box/private.key "$SBFOLDER/private.key" 2>/dev/null
      cp -f /etc/s-box/cert.pem "$SBFOLDER/cert.pem" 2>/dev/null
      blue "IP 证书申请并安装成功！"
      is_self_signed=false
      tls_sni="$server_ip"
      ym_domain="$server_ip"
      certificatec="/etc/s-box/cert.pem"
      certificatep="/etc/s-box/private.key"
    else
      red "IP 证书申请失败！回退使用自签证书。"
      cert_type="self"
      setup_caddy_cert
    fi
  elif [[ "$cert_type" == "domain" ]]; then
    blue "域名证书将由 Caddy 自动申请与续期。"
    is_self_signed=false
    tls_sni="$ym_domain"
    generate_self_signed_cert /etc/s-box/private.key /etc/s-box/cert.pem
    cp -f /etc/s-box/private.key "$SBFOLDER/private.key" 2>/dev/null
    cp -f /etc/s-box/cert.pem "$SBFOLDER/cert.pem" 2>/dev/null
    cp -f /etc/s-box/ca.pem "$SBFOLDER/ca.pem" 2>/dev/null
    certificatec="/etc/s-box/cert.pem"
    certificatep="/etc/s-box/private.key"
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
command="/etc/s-box/sing-box"
command_args="run -c /etc/s-box/config.json -C /etc/s-box/conf/"
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
ExecStart=/etc/s-box/sing-box run -c /etc/s-box/config.json -C /etc/s-box/conf/
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
      local combined_json=$(cat "$SBFOLDER/config.json" | sed 's://.*::g')
      if [ -d "$SBFOLDER/conf" ]; then
        for f in "$SBFOLDER/conf"/*.json; do
          if [ -f "$f" ]; then
            local f_json=$(cat "$f" | sed 's://.*::g')
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
    sed 's://.*::g' "$file"
  else
    echo "{}"
  fi
}

sync_configs_from_sb_json() {
  if [ -f "$SBFOLDER/sb.json" ]; then
    local clean_json=$(sed 's://.*::g' "$SBFOLDER/sb.json")
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
  if [[ -f /root/ygkkkca/cert.crt && -f /root/ygkkkca/private.key && -s /root/ygkkkca/cert.crt && -s /root/ygkkkca/private.key ]]; then
    ym=$(bash ~/.acme.sh/acme.sh --list 2>/dev/null | tail -1 | awk '{print $1}')
    [ -n "$ym" ] && echo "$ym" > /root/ygkkkca/ca.log
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
  short_id=$(echo "$clean_json" | jq -r '(.inbounds[] | select(.tag == "vless-reality-sb" or .tag == "vless-h2-reality-sb") | .tls.reality.short_id[0]) // empty' 2>/dev/null | head -n 1)
  
  # Shadowsocks credentials
  ss_password=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "shadowsocks-sb") | .password // empty' 2>/dev/null | head -n 1)
  ss_method=$(echo "$clean_json" | jq -r '.inbounds[] | select(.tag == "shadowsocks-sb") | .method // empty' 2>/dev/null | head -n 1)

  # Check certificate mode
  ym=$(cat /root/ygkkkca/ca.log 2>/dev/null)
  local cert_key_path=$(echo "$clean_json" | jq -r '(.inbounds[] | select(.tls.key_path != null) | .tls.key_path) // empty' 2>/dev/null | head -n 1)
  if [[ "$cert_key_path" = "$SBFOLDER/private.key" || "$cert_key_path" = "/etc/s-box/private.key" ]]; then
    is_self_signed=true
    tls_sni="www.bing.com"
  else
    is_self_signed=false
    tls_sni=$ym
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
    hy2_name="www.bing.com"
    sb_hy2_ip=$server_ip
    cl_hy2_ip=$server_ipcl
    ins_hy2=1
    hy2_ins=false
    
    tu5_name="www.bing.com"
    sb_tu5_ip=$server_ip
    cl_tu5_ip=$server_ipcl
    ins=1
    tu5_ins=true

    an_name="www.bing.com"
    sb_an_ip=$server_ip
    cl_an_ip=$server_ipcl
    ins_an=1
    an_ins=true
  else
    hy2_name=$ym
    sb_hy2_ip=$ym
    cl_hy2_ip=$ym
    ins_hy2=0
    hy2_ins=false
    
    tu5_name=$ym
    sb_tu5_ip=$ym
    cl_tu5_ip=$ym
    ins=0
    tu5_ins=false

    an_name=$ym
    sb_an_ip=$ym
    cl_an_ip=$ym
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
    local cert_type=$(cat /etc/s-box/cert_type.log 2>/dev/null || echo "self")
    if [[ "$cert_type" == "domain" && -n "$tls_sni" ]]; then
      s_ip_ws="$tls_sni"
      s_ip_hu="$tls_sni"
    fi
  fi

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
      vl_link="vless://$uuid_vl_re@$server_ip:$port_vl_re?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$vl_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#vl-reality-$hostname"
      echo "$vl_link" > "$SBFOLDER/vl_reality.txt"
      red "🚀【 vless-reality-vision 】节点信息如下：" && sleep 2
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
      local vl_ws_link="vless://$uuid_vl_ws@$s_ip_ws:$p_vl_ws?encryption=none&security=tls&sni=$tls_sni&type=ws&path=%2F${uuid_vl_ws}&${vl_tls_params}#vl-ws-tls-$hostname"
      echo "$vl_ws_link" > "$SBFOLDER/vl_ws_tls.txt"
      red "🚀【 vless-ws-tls 】节点信息如下：" && sleep 2
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
      local vl_hu_link="vless://$uuid_vl_hu@$s_ip_hu:$p_vl_hu?encryption=none&security=tls&sni=$tls_sni&type=httpupgrade&path=%2F${uuid_vl_hu}&${vl_tls_params}#vl-hu-tls-$hostname"
      echo "$vl_hu_link" > "$SBFOLDER/vl_hu_tls.txt"
      red "🚀【 vless-hu-tls 】节点信息如下：" && sleep 2
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
    local cert_type=$(cat /etc/s-box/cert_type.log 2>/dev/null || echo "self")
    if [[ "$cert_type" == "domain" && -n "$tls_sni" ]]; then
      s_ipcl_ws="$tls_sni"
      s_ipcl_hu="$tls_sni"
    fi
  fi

  if [[ -n "$port_vm_ws" ]]; then
    local port_active=false
    if [[ -f "$SBFOLDER/argo.log" && -s "$SBFOLDER/argo.log" ]] && \
       ps -ef | grep -v grep | grep -q "cloudflared.*localhost:$port_vm_ws"; then
      port_active=true
    fi
    
    if $port_active; then
      echo
      white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
      red "🚀【 vmess-ws(tls)+Argo 】临时节点信息如下 (可选择3-8-3，自定义CDN优选地址)：" && sleep 2
      echo
      echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
      local argo_domain=$(grep -a -o -E '[a-zA-Z0-9.-]+\.trycloudflare\.com' "$SBFOLDER/argo.log" 2>/dev/null | head -n 1)
      local vm_argo_temp_link="vmess://$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argo_domain'","id":"'$uuid_vm_ws'","net":"ws","path":"'$uuid_vm_ws'","port":"443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argo_domain'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)"
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
      red "🚀【 vmess-ws(tls)+Argo 】固定节点信息如下 (可选择3-8-3，自定义CDN优选地址)：" && sleep 2
      echo
      echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
      local vm_argo_fixed_link="vmess://$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argogd'","id":"'$uuid_vm_ws'","net":"ws","path":"'$uuid_vm_ws'","port":"443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argogd'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)"
      echo -e "${yellow}$vm_argo_fixed_link${plain}"
      echo
      echo "$vm_argo_fixed_link" > "$SBFOLDER/vm_ws_argogd.txt"
      print_qr "$vm_argo_fixed_link"
    fi
    
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    if [[ -f "$SBFOLDER/cfvmadd_local.txt" ]]; then
      local vm_ws_link="vmess://$(echo '{"add":"'$vmadd_local'","aid":"0","host":"'$tls_sni'","id":"'$uuid_vm_ws'","net":"ws","path":"'$uuid_vm_ws'","port":"'$port_vm_ws'","ps":"'vm-ws-$hostname'","tls":"","type":"none","v":"2"}' | base64 -w 0)"
      echo "$vm_ws_link" > "$SBFOLDER/vm_ws.txt"
      red "🚀【 vmess-ws 】节点信息如下 (已启用自定义优选地址)：" && sleep 2
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
      local vm_ws_link="vmess://$(echo '{"add":"'$server_ipcl'","aid":"0","host":"'$tls_sni'","id":"'$uuid_vm_ws'","net":"ws","path":"'$uuid_vm_ws'","port":"'$port_vm_ws'","ps":"'vm-ws-$hostname'","tls":"","type":"none","v":"2"}' | base64 -w 0)"
      echo "$vm_ws_link" > "$SBFOLDER/vm_ws.txt"
      red "🚀【 vmess-ws 】节点信息如下 (建议选择3-8-1，设置为CDN优选节点)：" && sleep 2
      echo -e "${yellow}$vm_ws_link${plain}\n"
      print_qr "$vm_ws_link"
    fi
  fi

  if [[ -n "$port_vm_ws_tls" ]]; then
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    if [[ -f "$SBFOLDER/cfvmadd_local.txt" ]]; then
      red "🚀【 vmess-ws-tls 】节点信息如下 (已启用自定义优选地址)：" && sleep 2
      local vm_ws_tls_link="vmess://$(echo '{"add":"'$vmadd_local'","aid":"0","host":"'$tls_sni'","id":"'$uuid_vm_ws_tls'","net":"ws","path":"'$uuid_vm_ws_tls'","port":"'$p_vm_ws_tls'","ps":"'vm-ws-tls-$hostname'","tls":"tls","sni":"'$tls_sni'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)"
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
      red "🚀【 vmess-ws-tls 】节点信息如下 (建议选择3-8-1，设置为CDN优选节点)：" && sleep 2
      local vm_ws_tls_link="vmess://$(echo '{"add":"'$s_ipcl_ws'","aid":"0","host":"'$tls_sni'","id":"'$uuid_vm_ws_tls'","net":"ws","path":"'$uuid_vm_ws_tls'","port":"'$p_vm_ws_tls'","ps":"'vm-ws-tls-$hostname'","tls":"tls","sni":"'$tls_sni'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)"
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
      local vm_hu_tls_link="vmess://$(echo '{"add":"'$s_ipcl_hu'","aid":"0","host":"'$tls_sni'","id":"'$uuid_vm_hu_tls'","net":"httpupgrade","path":"'$uuid_vm_hu_tls'","port":"'$p_vm_hu_tls'","ps":"'vm-hu-tls-$hostname'","tls":"tls","sni":"'$tls_sni'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)"
      echo "$vm_hu_tls_link" > "$SBFOLDER/vm_hu_tls.txt"
      red "🚀【 vmess-hu-tls 】节点信息如下 (建议选择3-8-1，设置为CDN优选节点)：" && sleep 2
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
    hy2_params="insecure=0&sni=www.bing.com&pinnedPeerCertSha256=$SHA256&alpn=h3"
  else
    hy2_params="sni=$hy2_name&insecure=0&alpn=h3"
  fi
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
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
    hy2_link="hysteria2://$uuid_hy2@$sb_hy2_ip:$port_hy2?$hy2_params$hyps#hy2-$hostname"
    echo "$hy2_link" > "$SBFOLDER/hy2.txt"
    red "🚀【 Hysteria-2 】节点信息如下：" && sleep 2
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
    tu5_params="sni=www.bing.com&insecure=0&allowInsecure=0&allow_insecure=0&pinnedPeerCertSha256=$SHA256&alpn=h3"
  else
    tu5_params="sni=$tu5_name&insecure=0&allowInsecure=0&allow_insecure=0&alpn=h3"
  fi
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
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
    tu_link="tuic://$uuid_tu:$uuid_tu@$sb_tu5_ip:$port_tu?$tu5_params#tuic5-$hostname"
    echo "$tu_link" > "$SBFOLDER/tuic5.txt"
    red "🚀【 Tuic-v5 】节点信息如下：" && sleep 2
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
    an_params="sni=www.bing.com&allowInsecure=0&insecure=0&pinnedPeerCertSha256=$SHA256"
  fi
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
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
    an_link="anytls://$uuid_an@$sb_an_ip:$port_an?$an_params#anytls-$hostname"
    echo "$an_link" > "$SBFOLDER/an.txt"
    red "🚀【 Anytls】节点信息如下：" && sleep 2
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
    local cert_type=$(cat /etc/s-box/cert_type.log 2>/dev/null || echo "self")
    if [[ "$cert_type" == "domain" && -n "$tls_sni" ]]; then
      s_ip_ws="$tls_sni"
      s_ip_hu="$tls_sni"
    fi
  fi

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
      local tr_link="trojan://$uuid_tr_tls@$server_ip:$port_tr_tls?security=tls&sni=$tls_sni&${tr_tls_params}#tr-tls-$hostname"
      echo "$tr_link" > "$SBFOLDER/tr_tls.txt"
      red "🚀【 Trojan-TLS 】节点信息如下：" && sleep 2
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
      local tr_ws_link="trojan://$uuid_tr_ws_tls@$s_ip_ws:$p_tr_ws_tls?security=tls&sni=$tls_sni&type=ws&path=%2F${uuid_tr_ws_tls}&${tr_tls_params}#tr-ws-tls-$hostname"
      echo "$tr_ws_link" > "$SBFOLDER/tr_ws_tls.txt"
      red "🚀【 Trojan-WS-TLS 】节点信息如下：" && sleep 2
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
      local tr_hu_link="trojan://$uuid_tr_hu_tls@$s_ip_hu:$p_tr_hu_tls?security=tls&sni=$tls_sni&type=httpupgrade&path=%2F${uuid_tr_hu_tls}&${tr_tls_params}#tr-hu-tls-$hostname"
      echo "$tr_hu_link" > "$SBFOLDER/tr_hu_tls.txt"
      red "🚀【 Trojan-HTTPUpgrade-TLS 】节点信息如下：" && sleep 2
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
    local ss_link="ss://$b64_cred@$server_ip:$port_ss#ss-$hostname"
    echo "$ss_link" > "$SBFOLDER/ss.txt"
    red "🚀【 Shadowsocks 】节点信息如下：" && sleep 2
    echo -e "${yellow}$ss_link${plain}\n"
    print_qr "$ss_link"
  fi
}

resvmess_tcp() {
  [[ -z "$port_vm_tcp" ]] && return 0
  echo
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
  local vm_tcp_link="vmess://$(echo '{"add":"'$server_ip'","aid":"0","host":"","id":"'$uuid_vm_tcp'","net":"tcp","path":"","port":"'$port_vm_tcp'","ps":"vm-tcp-'$hostname'","tls":"","sni":"","type":"none","v":"2"}' | base64 -w 0)"
  echo "$vm_tcp_link" > "$SBFOLDER/vm_tcp.txt"
  red "🚀【 VMess-TCP 】节点信息如下：" && sleep 2
  echo -e "${yellow}$vm_tcp_link${plain}\n"
  print_qr "$vm_tcp_link"
}

resvmess_http() {
  [[ -z "$port_vm_http" ]] && return 0
  echo
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
  local vm_http_link="vmess://$(echo '{"add":"'$server_ip'","aid":"0","host":"","id":"'$uuid_vm_http'","net":"tcp","path":"","port":"'$port_vm_http'","ps":"vm-http-'$hostname'","tls":"","sni":"","type":"http","v":"2"}' | base64 -w 0)"
  echo "$vm_http_link" > "$SBFOLDER/vm_http.txt"
  red "🚀【 VMess-HTTP 】节点信息如下：" && sleep 2
  echo -e "${yellow}$vm_http_link${plain}\n"
  print_qr "$vm_http_link"
}

resvmess_quic() {
  [[ -z "$port_vm_quic" ]] && return 0
  echo
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
  local vm_quic_link="vmess://$(echo '{"add":"'$server_ip'","aid":"0","host":"","id":"'$uuid_vm_quic'","net":"quic","path":"","port":"'$port_vm_quic'","ps":"vm-quic-'$hostname'","tls":"tls","sni":"'$tls_sni'","alpn":"h3","type":"none","v":"2"}' | base64 -w 0)"
  echo "$vm_quic_link" > "$SBFOLDER/vm_quic.txt"
  red "🚀【 VMess-QUIC 】节点信息如下：" && sleep 2
  echo -e "${yellow}$vm_quic_link${plain}\n"
  print_qr "$vm_quic_link"
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
  if $caddy_active; then
    p_vm_h2="443"
    local cert_type=$(cat /etc/s-box/cert_type.log 2>/dev/null || echo "self")
    if [[ "$cert_type" == "domain" && -n "$ym_domain" ]]; then
      s_ip_h2="$ym_domain"
    fi
  fi

  local vm_h2_link="vmess://$(echo '{"add":"'$s_ip_h2'","aid":"0","host":"'$ym_domain'","id":"'$uuid_vm_h2_tls'","net":"h2","path":"'$uuid_vm_h2_tls'","port":"'$p_vm_h2'","ps":"vm-h2-tls-'$hostname'","tls":"tls","sni":"'$ym_domain'","type":"none","v":"2"}' | base64 -w 0)"
  echo "$vm_h2_link" > "$SBFOLDER/vm_h2_tls.txt"
  red "🚀【 VMess-H2-TLS 】节点信息如下：" && sleep 2
  echo -e "${yellow}$vm_h2_link${plain}\n"
  print_qr "$vm_h2_link"
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
  if $caddy_active; then
    p_vl_h2="443"
    local cert_type=$(cat /etc/s-box/cert_type.log 2>/dev/null || echo "self")
    if [[ "$cert_type" == "domain" && -n "$ym_domain" ]]; then
      s_ip_h2="$ym_domain"
    fi
  fi

  local vl_h2_link="vless://$uuid_vl_h2@$s_ip_h2:$p_vl_h2?encryption=none&security=tls&sni=$ym_domain&type=h2&host=$ym_domain&path=%2F${uuid_vl_h2}&${vl_tls_params}#vl-h2-tls-$hostname"
  echo "$vl_h2_link" > "$SBFOLDER/vl_h2_tls.txt"
  red "🚀【 VLESS-H2-TLS 】节点信息如下：" && sleep 2
  echo -e "${yellow}$vl_h2_link${plain}\n"
  print_qr "$vl_h2_link"
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
  if $caddy_active; then
    p_tr_h2="443"
    local cert_type=$(cat /etc/s-box/cert_type.log 2>/dev/null || echo "self")
    if [[ "$cert_type" == "domain" && -n "$ym_domain" ]]; then
      s_ip_h2="$ym_domain"
    fi
  fi

  local tr_h2_link="trojan://$uuid_tr_h2_tls@$s_ip_h2:$p_tr_h2?security=tls&sni=$ym_domain&type=h2&host=$ym_domain&path=%2F${uuid_tr_h2_tls}#tr-h2-tls-$hostname"
  echo "$tr_h2_link" > "$SBFOLDER/tr_h2_tls.txt"
  red "🚀【 Trojan-H2-TLS 】节点信息如下：" && sleep 2
  echo -e "${yellow}$tr_h2_link${plain}\n"
  print_qr "$tr_h2_link"
}

resvless_h2_re() {
  [[ -z "$port_vl_h2_re" ]] && return 0
  echo
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
  local vl_h2_re_link="vless://$uuid_vl_h2_re@$server_ip:$port_vl_h2_re?encryption=none&security=reality&sni=$vl_name&fp=chrome&pbk=$public_key&sid=$short_id&type=h2&path=%2F${uuid_vl_h2_re}#vl-h2-reality-$hostname"
  echo "$vl_h2_re_link" > "$SBFOLDER/vl_h2_reality.txt"
  red "🚀【 VLESS-HTTP2-REALITY 】节点信息如下：" && sleep 2
  echo -e "${yellow}$vl_h2_re_link${plain}\n"
  print_qr "$vl_h2_re_link"
}

ressocks() {
  [[ -z "$port_socks" ]] && return 0
  echo
  white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  server_ip=$(cat "$SBFOLDER/server_ip.log" 2>/dev/null)
  local socks_link="socks://$socks_username:$socks_password@$server_ip:$port_socks#socks-$hostname"
  echo "$socks_link" > "$SBFOLDER/socks.txt"
  red "🚀【 Socks5 】代理信息如下：" && sleep 2
  echo -e "${yellow}$socks_link${plain}\n"
  green "客户端地址：$server_ip"
  green "客户端端口：$port_socks"
  green "客户端用户名：$socks_username"
  green "客户端密码：$socks_password"
  echo
  print_qr "$socks_link"
}

sb_client() {
  # This builds the complete client configurations for SFA/SFI/SFW and Clash Meta (Mihomo)
  # dynamically utilizing jq, reducing 1000+ lines of duplicate templates.

  local cert_content=""
  if [[ -f "$SBFOLDER/ca.pem" ]]; then
    cert_content=$(cat "$SBFOLDER/ca.pem")
  elif [[ -f "$SBFOLDER/cert.pem" ]]; then
    cert_content=$(cat "$SBFOLDER/cert.pem")
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
    
    local cert_type=$(cat /etc/s-box/cert_type.log 2>/dev/null || echo "self")
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

  # Build outbounds list dynamically
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
      if [[ "$is_self_signed" == "false" && -n "$ym_domain" && "$ym_domain" != "www.bing.com" ]]; then
        if ! [[ "$ym_domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
          is_domain=true
        fi
      fi
      if $is_domain; then
        echo "single|$ym_domain"
      elif [[ "$server_ipcl" = "dual" ]]; then
        echo "v4|$v4_addr v6|[$v6_addr]"
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
      local suffix=""
      [[ "$server_ipcl" = "dual" ]] && suffix="-${s_type^^}"
      
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
      local suffix=""
      [[ "$server_ipcl" = "dual" ]] && suffix="-${s_type^^}"
      
      local vl_ws_extra=$(jq -n --arg uuid "$uuid_vl_ws" --arg sni "$tls_sni" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{uuid: $uuid, transport: {type: "ws", path: $uuid}, tls: ({enabled: true, server_name: $sni, insecure: false, utls: {enabled: true, fingerprint: "chrome"}} + (if $is_self and ($cert | length) > 0 then {certificate: [$cert]} else {} end))}')
      add_sb_outbound "vless-ws-tls${suffix}" "vless" "$s_addr" "$cl_p_vl_ws" "$vl_ws_extra"
      
      local cl_vl_ws_opts="  uuid: $uuid_vl_ws
  network: ws
  tls: true
  servername: $tls_sni
$cl_tls_caddy
  ws-opts:
    path: \"/${uuid_vl_ws}\"
    headers:
      Host: $tls_sni"
      add_clash_proxy "vless-ws-tls${suffix}" "vless" "$s_addr" "$cl_p_vl_ws" "$cl_vl_ws_opts"
    done
  fi

  # 3. VLESS HTTPUpgrade TLS
  if [[ -n "$port_vl_hu_tls" ]]; then
    local servers_list=$(resolve_servers "$cl_p_vl_hu" "$cl_s_vl_hu")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local suffix=""
      [[ "$server_ipcl" = "dual" ]] && suffix="-${s_type^^}"
      
      local vl_hu_extra=$(jq -n --arg uuid "$uuid_vl_hu" --arg sni "$tls_sni" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{uuid: $uuid, transport: {type: "httpupgrade", path: $uuid}, tls: ({enabled: true, server_name: $sni, insecure: false, utls: {enabled: true, fingerprint: "chrome"}} + (if $is_self and ($cert | length) > 0 then {certificate: [$cert]} else {} end))}')
      add_sb_outbound "vless-hu-tls${suffix}" "vless" "$s_addr" "$cl_p_vl_hu" "$vl_hu_extra"
      
      local cl_vl_hu_opts="  uuid: $uuid_vl_hu
  network: httpupgrade
  tls: true
  servername: $tls_sni
$cl_tls_caddy
  httpupgrade-opts:
    path: \"/${uuid_vl_hu}\"
    headers:
      Host: $tls_sni"
      add_clash_proxy "vless-hu-tls${suffix}" "vless" "$s_addr" "$cl_p_vl_hu" "$cl_vl_hu_opts"
    done
  fi

  # 4. VMess WS (No TLS)
  if [[ -n "$port_vm_ws" ]]; then
    local servers_list=$(resolve_servers "$port_vm_ws" "$tls_sni")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local suffix=""
      [[ "$server_ipcl" = "dual" ]] && suffix="-${s_type^^}"
      
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
      local suffix=""
      [[ "$server_ipcl" = "dual" ]] && suffix="-${s_type^^}"
      
      local vm_ws_tls_extra=$(jq -n --arg uuid "$uuid_vm_ws_tls" --arg sni "$tls_sni" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{uuid: $uuid, security: "auto", packet_encoding: "packetaddr", transport: {type: "ws", path: $uuid}, tls: ({enabled: true, server_name: $sni, insecure: false, utls: {enabled: true, fingerprint: "chrome"}} + (if $is_self and ($cert | length) > 0 then {certificate: [$cert]} else {} end))}')
      add_sb_outbound "vmess-ws-tls${suffix}" "vmess" "$s_addr" "$cl_p_vm_ws" "$vm_ws_tls_extra"
      
      local cl_vm_ws_tls_opts="  uuid: $uuid_vm_ws_tls
  alterId: 0
  cipher: auto
  network: ws
  tls: true
  servername: $tls_sni
$cl_tls_caddy
  ws-opts:
    path: \"/${uuid_vm_ws_tls}\"
    headers:
      Host: $tls_sni"
      add_clash_proxy "vmess-ws-tls${suffix}" "vmess" "$s_addr" "$cl_p_vm_ws" "$cl_vm_ws_tls_opts"
    done
  fi

  # 6. VMess HTTPUpgrade TLS
  # 6. VMess HTTPUpgrade TLS
  if [[ -n "$port_vm_hu_tls" ]]; then
    local servers_list=$(resolve_servers "$cl_p_vm_hu" "$cl_s_vm_hu")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local suffix=""
      [[ "$server_ipcl" = "dual" ]] && suffix="-${s_type^^}"
      
      local vm_hu_tls_extra=$(jq -n --arg uuid "$uuid_vm_hu_tls" --arg sni "$tls_sni" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{uuid: $uuid, security: "auto", packet_encoding: "packetaddr", transport: {type: "httpupgrade", path: $uuid}, tls: ({enabled: true, server_name: $sni, insecure: false, utls: {enabled: true, fingerprint: "chrome"}} + (if $is_self and ($cert | length) > 0 then {certificate: [$cert]} else {} end))}')
      add_sb_outbound "vmess-hu-tls${suffix}" "vmess" "$s_addr" "$cl_p_vm_hu" "$vm_hu_tls_extra"
      
      local cl_vm_hu_tls_opts="  uuid: $uuid_vm_hu_tls
  alterId: 0
  cipher: auto
  network: httpupgrade
  tls: true
  servername: $tls_sni
$cl_tls_caddy
  httpupgrade-opts:
    path: \"/${uuid_vm_hu_tls}\"
    headers:
      Host: $tls_sni"
      add_clash_proxy "vmess-hu-tls${suffix}" "vmess" "$s_addr" "$cl_p_vm_hu" "$cl_vm_hu_tls_opts"
    done
  fi

  # 7. Trojan TLS
  if [[ -n "$port_tr_tls" ]]; then
    local servers_list=$(resolve_servers "$port_tr_tls" "$tls_sni")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local suffix=""
      [[ "$server_ipcl" = "dual" ]] && suffix="-${s_type^^}"
      
      local tr_tls_extra=$(jq -n --arg uuid "$uuid_tr_tls" --arg sni "$tls_sni" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{password: $uuid, tls: ({enabled: true, server_name: $sni, insecure: false, utls: {enabled: true, fingerprint: "chrome"}} + (if $is_self and ($cert | length) > 0 then {certificate: [$cert]} else {} end))}')
      add_sb_outbound "trojan-tls${suffix}" "trojan" "$s_addr" "$port_tr_tls" "$tr_tls_extra"
      
      local cl_tr_tls_opts="  password: $uuid_tr_tls
  network: tcp
  tls: true
  servername: $tls_sni
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
      local suffix=""
      [[ "$server_ipcl" = "dual" ]] && suffix="-${s_type^^}"
      
      local tr_ws_extra=$(jq -n --arg uuid "$uuid_tr_ws_tls" --arg sni "$tls_sni" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{password: $uuid, transport: {type: "ws", path: $uuid}, tls: ({enabled: true, server_name: $sni, insecure: false, utls: {enabled: true, fingerprint: "chrome"}} + (if $is_self and ($cert | length) > 0 then {certificate: [$cert]} else {} end))}')
      add_sb_outbound "trojan-ws-tls${suffix}" "trojan" "$s_addr" "$cl_p_tr_ws" "$tr_ws_extra"
      
      local cl_tr_ws_opts="  password: $uuid_tr_ws_tls
  network: ws
  tls: true
  servername: $tls_sni
$cl_tls_caddy
  ws-opts:
    path: \"/${uuid_tr_ws_tls}\"
    headers:
      Host: $tls_sni"
      add_clash_proxy "trojan-ws-tls${suffix}" "trojan" "$s_addr" "$cl_p_tr_ws" "$cl_tr_ws_opts"
    done
  fi

  # 9. Trojan HTTPUpgrade TLS
  if [[ -n "$port_tr_hu_tls" ]]; then
    local servers_list=$(resolve_servers "$cl_p_tr_hu" "$cl_s_tr_hu")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local suffix=""
      [[ "$server_ipcl" = "dual" ]] && suffix="-${s_type^^}"
      
      local tr_hu_extra=$(jq -n --arg uuid "$uuid_tr_hu_tls" --arg sni "$tls_sni" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{password: $uuid, transport: {type: "httpupgrade", path: $uuid}, tls: ({enabled: true, server_name: $sni, insecure: false, utls: {enabled: true, fingerprint: "chrome"}} + (if $is_self and ($cert | length) > 0 then {certificate: [$cert]} else {} end))}')
      add_sb_outbound "trojan-hu-tls${suffix}" "trojan" "$s_addr" "$cl_p_tr_hu" "$tr_hu_extra"
      
      local cl_tr_hu_opts="  password: $uuid_tr_hu_tls
  network: httpupgrade
  tls: true
  servername: $tls_sni
$cl_tls_caddy
  httpupgrade-opts:
    path: \"/${uuid_tr_hu_tls}\"
    headers:
      Host: $tls_sni"
      add_clash_proxy "trojan-hu-tls${suffix}" "trojan" "$s_addr" "$cl_p_tr_hu" "$cl_tr_hu_opts"
    done
  fi

  # 10. Shadowsocks (SS-2022)
  if [[ -n "$port_ss" ]]; then
    local servers_list=$(resolve_servers "$port_ss" "$server_ipcl")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local suffix=""
      [[ "$server_ipcl" = "dual" ]] && suffix="-${s_type^^}"
      
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
      local suffix=""
      [[ "$server_ipcl" = "dual" ]] && suffix="-${s_type^^}"
      
      local ports_array="[]"
      [[ -n "$sbhy2pt" ]] && ports_array="[$sbhy2pt]"
      
      local hy2_tls_obj=$(jq -n --arg name "$hy2_name" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{enabled: true, server_name: $name, insecure: false, alpn: ["h3"]} + (if $is_self and ($cert | length) > 0 then { certificate: [$cert] } else {} end)')
      local hy2_extra=$(jq -n --arg password "$uuid_hy2" --argjson tls "$hy2_tls_obj" --argjson extra_ports "$ports_array" \
        '{password: $password, tls: $tls} + (if ($extra_ports | length) > 0 then { server_ports: $extra_ports } else {} end)')
      add_sb_outbound "hysteria2${suffix}" "hysteria2" "$s_addr" "$port_hy2" "$hy2_extra"
      
      local cl_hy2_opts="  password: $uuid_hy2
  alpn:
    - h3
  sni: $hy2_name
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
      local suffix=""
      [[ "$server_ipcl" = "dual" ]] && suffix="-${s_type^^}"
      
      local tu5_tls_obj=$(jq -n --arg name "$tu5_name" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
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
  sni: $tu5_name
$cl_tls_common"
      add_clash_proxy "tuic5${suffix}" "tuic" "$s_addr" "$port_tu" "$cl_tu_opts"
    done
  fi

  # 13. AnyTLS
  if [[ "$sbnh" != "1.10" ]] && [[ -n "$port_an" ]]; then
    local servers_list=$(resolve_servers "$port_an" "$sb_an_ip")
    for s_info in $servers_list; do
      local s_type=$(echo "$s_info" | cut -d'|' -f1)
      local s_addr=$(echo "$s_info" | cut -d'|' -f2)
      local suffix=""
      [[ "$server_ipcl" = "dual" ]] && suffix="-${s_type^^}"
      
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
      local suffix=""
      [[ "$server_ipcl" = "dual" ]] && suffix="-${s_type^^}"
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
      local suffix=""
      [[ "$server_ipcl" = "dual" ]] && suffix="-${s_type^^}"
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
      local suffix=""
      [[ "$server_ipcl" = "dual" ]] && suffix="-${s_type^^}"
      local vm_quic_extra=$(jq -n --arg uuid "$uuid_vm_quic" --arg sni "$tls_sni" --argjson is_self "$is_self_signed" --arg cert "$cert_content" \
        '{uuid: $uuid, security: "auto", packet_encoding: "packetaddr", transport: {type: "quic"}, tls: ({enabled: true, server_name: $sni, insecure: false, alpn: ["h3"]} + (if $is_self and ($cert | length) > 0 then {certificate: [$cert]} else {} end))}')
      add_sb_outbound "vmess-quic${suffix}" "vmess" "$s_addr" "$port_vm_quic" "$vm_quic_extra"
      local cl_vm_quic_opts="  uuid: $uuid_vm_quic
  alterId: 0
  cipher: auto
  network: quic
  tls: true
  servername: $tls_sni
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
      local suffix=""
      [[ "$server_ipcl" = "dual" ]] && suffix="-${s_type^^}"
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
      local suffix=""
      [[ "$server_ipcl" = "dual" ]] && suffix="-${s_type^^}"
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
      local suffix=""
      [[ "$server_ipcl" = "dual" ]] && suffix="-${s_type^^}"
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
      local suffix=""
      [[ "$server_ipcl" = "dual" ]] && suffix="-${s_type^^}"
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
  if [[ "$sbnh" != "1.10" ]]; then
    resan
  fi
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
  local vm_no_tls=$(echo "$clean_json" | jq -r '(.inbounds[] | select(.tag == "vmess-ws-sb") | .listen_port) // empty')
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
  local vm_listen_port=$(echo "$clean_json" | jq -r '(.inbounds[] | select(.tag == "vmess-ws-sb") | .listen_port) // empty')
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
      [ -f "$file" ] && jq --arg tag "$tag" --argjson p "$new_port" '(.inbounds[] | select(.tag == $tag)).listen_port = $p' "$file" > /tmp/tmp.json && mv /tmp/tmp.json "$file"
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
  if [[ "$sbnh" != "1.10" ]] && [[ -n "$port_an" ]]; then
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
      if [[ "$sbnh" != "1.10" ]] && [[ -n "$port_an" ]]; then
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

  oldvmpath=$(echo "$clean_json" | jq -r '(.inbounds[] | select(.tag == "vmess-ws-sb") | .transport.path) // empty')
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
          jq --arg p "$vmpath" '(.inbounds[] | select(.tag == "vmess-ws-sb")).transport.path = $p' "$file" > /tmp/tmp.json && mv /tmp/tmp.json "$file"
        fi
      done
      restartsb && sbshare > /dev/null 2>&1
    fi
    blue "已确认Vmess-WS的path路径：$(strip_json_comments "$SBFOLDER/sb.json" | jq -r '(.inbounds[] | select(.tag == "vmess-ws-sb") | .transport.path) // empty')"
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
  result_vl_vm_hy_tu
  local clean_json=$(strip_json_comments "$SBFOLDER/sb.json")
  [ -f /root/ygkkkca/ca.log ] && ymzs="$green已申请域名证书：$(cat /root/ygkkkca/ca.log 2>/dev/null)$plain" || ymzs="$yellow未申请域名证书，无法切换$plain"
  
  # Check current certificate mode
  local cur_key=$(echo "$clean_json" | jq -r '(.inbounds[] | select(.tls.key_path != null) | .tls.key_path) // empty' | head -n 1)
  if [ "$cur_key" = "$SBFOLDER/private.key" ] || [ "$cur_key" = "/etc/s-box/private.key" ]; then
    cert_mode="自签证书"
    switch_hint="切换为域名证书"
  else
    cert_mode="域名证书"
    switch_hint="切换为自签证书"
  fi

  echo
  green "证书及域名管理与协议增删："
  echo
  [[ -n "$port_vl_re" ]] && green "1：更换 VLESS-Reality 伪装域名 (当前为 $vl_name)"
  green "2：切换所有协议的证书类型 (当前为: ${yellow}$cert_mode${plain}，将 $switch_hint)"
  green "3：新增协议"
  green "4：删除协议"
  green "0：返回上层"
  readp "请选择【0-4】：" menu
  
  if [ "$menu" = "1" ]; then
    if [[ -z "$port_vl_re" ]]; then
      red "VLESS-Reality协议未安装！" && sleep 2 && changeym
      return
    fi
    readp "请输入新的 VLESS-Reality 伪装域名 (回车使用 apple.com)：" ym_menu
    ym_vl_re=${ym_menu:-apple.com}
    for file in $SBFILES; do
      if [ -f "$file" ]; then
        jq --arg ym "$ym_vl_re" \
           '(.inbounds[] | select(.tag == "vless-reality-sb")) |= (.tls.server_name = $ym | .tls.reality.handshake.server = $ym)' \
           "$file" > /tmp/tmp.json && mv /tmp/tmp.json "$file"
      fi
    done
    restartsb && sbshare > /dev/null 2>&1
    blue "VLESS-Reality 伪装域名更换完毕，已变更为: $ym_vl_re"
    sleep 2 && changeym
  elif [ "$menu" = "2" ]; then
    if [ ! -f /root/ygkkkca/ca.log ] && [ "$cert_mode" = "自签证书" ]; then
      red "未申请域名证书，无法切换！" && sleep 2 && changeym
      return
    fi
    local next_cert="/etc/s-box/cert.pem"
    local next_key="/etc/s-box/private.key"
    if [ "$cert_mode" = "自签证书" ]; then
      next_cert="/root/ygkkkca/cert.crt"
      next_key="/root/ygkkkca/private.key"
    fi
    for file in $SBFILES; do
      if [ -f "$file" ]; then
        jq --arg cert "$next_cert" --arg key "$next_key" \
           '(.. | select(objects and .tls? != null) | .tls | select(.key_path != null)) |= (.certificate_path = $cert | .key_path = $key)' \
           "$file" > /tmp/tmp.json && mv /tmp/tmp.json "$file"
      fi
    done
    restartsb && sbshare > /dev/null 2>&1
    if [ "$cert_mode" = "自签证书" ]; then
      blue "证书模式已成功切换为：域名证书"
    else
      blue "证书模式已成功切换为：自签证书"
    fi
    sleep 2 && changeym
  elif [ "$menu" = "3" ]; then
    add_protocol
    changeym
  elif [ "$menu" = "4" ]; then
    delete_protocol
    changeym
  else
    sb
  fi
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
  green "请选择要新增的协议（只允许选择 [未安装] 状态的协议）："
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
  if [[ "$sbnh" != "1.10" ]]; then
    [[ -f "$SBFOLDER/conf/anytls-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
    yellow "20：AnyTLS $state"
  fi
  [[ -f "$SBFOLDER/conf/socks-sb.json" ]] && state="${green}[已安装]${plain}" || state="${yellow}[未安装]${plain}"
  yellow "21：Socks (Socks5 代理服务) $state"
  echo " 0：返回上层"
  readp "请选择【0-21】：" choice
  if [[ "$choice" -eq 0 ]] || [[ -z "$choice" ]]; then
    return
  fi

  local sel_idx=""
  case "$choice" in
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
    20) [[ "$sbnh" != "1.10" ]] && sel_idx=19 || { red "选择无效！" && sleep 2 && add_protocol; return; } ;;
    21) sel_idx=20 ;;
    *) red "选择无效！" && sleep 2 && add_protocol; return ;;
  esac

  local sel_name="${proto_names[$sel_idx]}"
  local sel_tag="${proto_tags[$sel_idx]}"
  local sel_var="${proto_vars[$sel_idx]}"

  if [[ -f "$SBFOLDER/conf/${sel_tag}.json" ]]; then
    red "协议 ${sel_name} 已经安装过，无需重复添加！"
    sleep 2 && add_protocol
    return
  fi

  blue "您选择新增的协议是：$sel_name"

  # 2. Get port for new protocol
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
  readp "\n请设置 ${sel_name} 的端口 (回车自动分配可用端口)：" custom_p
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

  # 4. Check SSL / Caddy installation requirements
  local need_tls=false
  local need_caddy=false

  if [[ "$sel_var" == "vl_ws_tls" || "$sel_var" == "vl_hu_tls" || "$sel_var" == "vl_h2_tls" || \
        "$sel_var" == "vm_ws_tls" || "$sel_var" == "vm_hu_tls" || "$sel_var" == "vm_h2_tls" || \
        "$sel_var" == "tr_ws_tls" || "$sel_var" == "tr_hu_tls" || "$sel_var" == "tr_h2_tls" ]]; then
    need_tls=true
    need_caddy=true
  elif [[ "$sel_var" == "tr_tls" || "$sel_var" == "hy2" || "$sel_var" == "tu" || "$sel_var" == "an" ]]; then
    need_tls=true
  fi

  local has_tls=false
  if [[ -f "/etc/s-box/cert.pem" || -f "/root/ygkkkca/cert.crt" ]]; then
    has_tls=true
  fi

  local caddy_installed=false
  if [[ -f /usr/local/bin/caddy ]]; then
    caddy_installed=true
  fi

  if $need_tls && ! $has_tls; then
    blue "\n新增的协议需要配置 SSL 证书。"
    if $need_caddy; then
      use_caddy="true"
      cert_type_prompt() {
        green "请选择 SSL 证书申请方式："
        yellow "1：自签证书 (Bing.com)"
        yellow "2：纯 IP 证书 (自动申请 Let's Encrypt 证书，需开放 80 端口)"
        yellow "3：域名证书 (需要您将域名解析到 VPS，Caddy 会自动申请与续期)"
        readp "请选择【1-3】：" cert_menu
        case "$cert_menu" in
          1) cert_type="self" ;;
          2) cert_type="ip" ;;
          3)
            cert_type="domain"
            readp "请输入解析到该 VPS 的域名：" menu
            if [[ -z "$menu" ]]; then
              red "域名不能为空！" && cert_type_prompt
              return
            fi
            ym_domain="$menu"
            tls_sni="$menu"
            echo "$ym_domain" > /root/ygkkkca/ca.log
            ;;
          *) red "输入错误，请重新选择！" && cert_type_prompt ;;
        esac
      }
      cert_type_prompt
      setup_caddy_cert
      caddyservice
    else
      use_caddy="false"
      inscertificate
    fi
  elif $need_caddy && ! $caddy_installed; then
    blue "\n检测到新增协议需要使用 443 Caddy 反代，但当前未安装 Caddy。正在安装配置 Caddy..."
    use_caddy="true"
    if [[ -f /root/ygkkkca/ca.log ]]; then
      cert_type="domain"
      ym_domain=$(cat /root/ygkkkca/ca.log)
      tls_sni="$ym_domain"
    elif [[ -f /etc/s-box/cert_type.log ]]; then
      cert_type=$(cat /etc/s-box/cert_type.log)
    else
      cert_type="self"
    fi
    setup_caddy_cert
    caddyservice
  fi

  # 5. Enable the protocol variable and rebuild configuration
  eval "use_${sel_var}=true"
  
  inssbjsonser
  restartsb
  
  sbshare > /dev/null 2>&1
  
  blue "\n协议 $sel_name 已成功新增并启动！"
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

  if [[ ${#active_names[@]} -eq 1 ]]; then
    red "当前只剩一个协议正在运行 (${active_names[0]})。必须保留至少一个协议运行！"
    yellow "如需彻底清除，请退出并使用主菜单2进行删除卸载。"
    sleep 3
    return
  fi

  echo
  green "请选择要删除的协议："
  for ((i=0; i<${#active_names[@]}; i++)); do
    echo -e "$((i+1))：${active_names[$i]}"
  done
  echo "0：返回上层"
  readp "请选择【0-${#active_names[@]}】：" choice
  if [[ "$choice" -eq 0 ]] || [[ -z "$choice" ]]; then
    return
  fi

  if [[ "$choice" -lt 1 || "$choice" -gt ${#active_names[@]} ]]; then
    red "选择无效！" && sleep 2 && delete_protocol
    return
  fi

  local sel_idx=$((choice-1))
  local sel_name="${active_names[$sel_idx]}"
  local sel_tag="${active_tags[$sel_idx]}"
  local sel_var="${active_vars[$sel_idx]}"

  blue "您选择删除的协议是：$sel_name"
  readp "确认删除该协议吗？[y/N] (默认不删除)：" confirm_del
  if [[ ! "$confirm_del" =~ ^[Yy]$ ]]; then
    return
  fi

  local caddy_active=false
  if systemctl is-active --quiet caddy 2>/dev/null || rc-service caddy status 2>/dev/null | grep -q "started"; then
    caddy_active=true
  fi

  local remaining_vars=()
  local var_item
  for var_item in "${active_vars[@]}"; do
    [[ "$var_item" != "$sel_var" ]] && remaining_vars+=("$var_item")
  done

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
      rm -f /etc/s-box/cert.pem /etc/s-box/private.key /etc/s-box/ca.pem
      rm -f "$SBFOLDER/cert.pem" "$SBFOLDER/private.key" "$SBFOLDER/ca.pem"
      rm -f /etc/s-box/cert_type.log
      if [[ -f /root/ygkkkca/ca.log ]]; then
        rm -rf /root/ygkkkca
      fi
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

  rm -f "$SBFOLDER/conf/${sel_tag}.json"
  
  for ((i=0; i<${#proto_names[@]}; i++)); do
    local tag_check="${proto_tags[$i]}"
    local var_check="${proto_vars[$i]}"
    if [[ -f "$SBFOLDER/conf/${tag_check}.json" ]]; then
      eval "use_${var_check}=true"
    else
      eval "use_${var_check}=false"
    fi
  done

  inssbjsonser
  restartsb

  sbshare > /dev/null 2>&1

  blue "\n协议 $sel_name 已成功删除！"
  sleep 2
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
  if [[ "$sbnh" == "1.10" ]]; then
    wd4=$(echo "$clean_json" | jq -r '(.route.rules[] | select(.outbound == "warp-IPv4-out") | .domain_suffix // []) | join(" ")' 2>/dev/null)
    args_wg4=$(echo "$clean_json" | jq -r '(.route.rules[] | select(.outbound == "warp-IPv4-out") | .geosite // []) | join(" ")' 2>/dev/null)
    
    wd6=$(echo "$clean_json" | jq -r '(.route.rules[] | select(.outbound == "warp-IPv6-out") | .domain_suffix // []) | join(" ")' 2>/dev/null)
    args_wg6=$(echo "$clean_json" | jq -r '(.route.rules[] | select(.outbound == "warp-IPv6-out") | .geosite // []) | join(" ")' 2>/dev/null)
    
    sd4=$(echo "$clean_json" | jq -r '(.route.rules[] | select(.outbound == "socks-IPv4-out") | .domain_suffix // []) | join(" ")' 2>/dev/null)
    sg4=$(echo "$clean_json" | jq -r '(.route.rules[] | select(.outbound == "socks-IPv4-out") | .geosite // []) | join(" ")' 2>/dev/null)
    
    sd6=$(echo "$clean_json" | jq -r '(.route.rules[] | select(.outbound == "socks-IPv6-out") | .domain_suffix // []) | join(" ")' 2>/dev/null)
    sg6=$(echo "$clean_json" | jq -r '(.route.rules[] | select(.outbound == "socks-IPv6-out") | .geosite // []) | join(" ")' 2>/dev/null)
    
    ad4=$(echo "$clean_json" | jq -r '(.route.rules[] | select(.outbound == "vps-outbound-v4") | .domain_suffix // []) | join(" ")' 2>/dev/null)
    ag4=$(echo "$clean_json" | jq -r '(.route.rules[] | select(.outbound == "vps-outbound-v4") | .geosite // []) | join(" ")' 2>/dev/null)
    
    ad6=$(echo "$clean_json" | jq -r '(.route.rules[] | select(.outbound == "vps-outbound-v6") | .domain_suffix // []) | join(" ")' 2>/dev/null)
    ag6=$(echo "$clean_json" | jq -r '(.route.rules[] | select(.outbound == "vps-outbound-v6") | .geosite // []) | join(" ")' 2>/dev/null)
  else
    wd4=""
    args_wg4=""
    
    wd6=$(echo "$clean_json" | jq -r '(.route.rules[] | select(.outbound == "warp-out") | .domain_suffix // []) | join(" ")' 2>/dev/null)
    args_wg6=""
    
    sd4=$(echo "$clean_json" | jq -r '(.route.rules[] | select(.outbound == "socks-out") | .domain_suffix // []) | join(" ")' 2>/dev/null)
    sg4=""
    
    sd6=""
    sg6=""
    
    ad4=$(echo "$clean_json" | jq -r '(.route.rules[] | select(.strategy == "prefer_ipv4") | .domain_suffix // []) | join(" ")' 2>/dev/null)
    ag4=""
    
    ad6=$(echo "$clean_json" | jq -r '(.route.rules[] | select(.strategy == "prefer_ipv6") | .domain_suffix // []) | join(" ")' 2>/dev/null)
    ag6=""
  fi

  if [[ "$wd4" == "yg_kkk" && ("$args_wg4" == "yg_kkk" || -z "$args_wg4") ]]; then
    wfl4="${yellow}【warp出站IPV4可用】未分流${plain}"
  else
    [[ "$wd4" != "yg_kkk" ]] && swd4="$wd4 "
    [[ "$args_wg4" != "yg_kkk" ]] && swg4=$args_wg4
    wfl4="${yellow}【warp出站IPV4可用】已分流：$swd4$swg4${plain} "
  fi
  
  if [[ "$wd6" == "yg_kkk" && ("$args_wg6" == "yg_kkk" || -z "$args_wg6") ]]; then
    wfl6="${yellow}【warp出站IPV6自测】未分流${plain}"
  else
    [[ "$wd6" != "yg_kkk" ]] && swd6="$wd6 "
    [[ "$args_wg6" != "yg_kkk" ]] && swg6=$args_wg6
    wfl6="${yellow}【warp出站IPV6自测】已分流：$swd6$swg6${plain} "
  fi
  
  if [[ "$sd4" == "yg_kkk" && ("$sg4" == "yg_kkk" || -z "$sg4") ]]; then
    sfl4="${yellow}【$warp_s4_ip】未分流${plain}"
  else
    [[ "$sd4" != "yg_kkk" ]] && ssd4="$sd4 "
    [[ "$sg4" != "yg_kkk" ]] && ssg4=$sg4
    sfl4="${yellow}【$warp_s4_ip】已分流：$ssd4$ssg4${plain} "
  fi
  
  if [[ "$sd6" == "yg_kkk" && ("$sg6" == "yg_kkk" || -z "$sg6") ]]; then
    sfl6="${yellow}【$warp_s6_ip】未分流${plain}"
  else
    [[ "$sd6" != "yg_kkk" ]] && ssd6="$sd6 "
    [[ "$sg6" != "yg_kkk" ]] && ssg6=$sg6
    sfl6="${yellow}【$warp_s6_ip】已分流：$ssd6$ssg6${plain} "
  fi
  
  if [[ ("$ad4" == "yg_kkk" || -z "$ad4") && ("$ag4" == "yg_kkk" || -z "$ag4") ]]; then
    adfl4="${yellow}【$vps_ipv4】未分流${plain}" 
  else
    [[ "$ad4" != "yg_kkk" ]] && sad4="$ad4 "
    [[ "$ag4" != "yg_kkk" ]] && sag4=$ag4
    adfl4="${yellow}【$vps_ipv4】已分流：$sad4$sag4${plain} "
  fi
  
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
  curl -sL "https://raw.githubusercontent.com/DuolaD/sing-box/main/version" | awk -F "更新内容" '{print $1}' | head -n 1 > "$SBFOLDER/v"
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
  local vm_listen_port=$(echo "$clean_json" | jq -r '(.inbounds[] | select(.tag == "vmess-ws-sb") | .listen_port) // empty' 2>/dev/null)
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
  
  rm -rf "$SBFOLDER" sbyg_update "$SCRIPT_SHORTCUT" /root/geoip.db /root/geosite.db /root/warpapi /root/warpip /root/websbox /root/ygkkkca /root/tcpx.sh
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
  if [[ "$sbnh" != "1.10" && -n "$port_an" ]]; then
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
  ws4="warp-socks5-ipv4优先分流域名：$sfl4"
  ws6="warp-socks5-ipv6优先分流域名：$sfl6"
  l4="VPS本地ipv4优先分流域名：$adfl4"
  l6="VPS本地ipv6优先分流域名：$adfl6"

  [[ "$sbnh" == "1.10" ]] && ymflzu=("ww4" "ww6" "ws4" "ws6" "l4" "l6") || ymflzu=("ww6" "ws4" "l4" "l6")
  local all_unset=true
  for ymfl in "${ymflzu[@]}"; do
    if [[ ${!ymfl} != *"未"* ]]; then
      echo -e "${!ymfl}"
      all_unset=false
    fi
  done

  if $all_unset; then
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
  if [[ "$sbnh" != "1.10" ]]; then
    yellow "20：AnyTLS"
  fi
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
        20) [[ "$sbnh" != "1.10" ]] && use_an=true ;;
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
      echo
      green "请选择 SSL 证书类型："
      yellow "1：自签证书 (www.bing.com) (回车默认)"
      yellow "2：纯 IP 证书 (由 Let's Encrypt 签发，仅当 80 端口可用时使用)"
      yellow "3：域名证书 (自动 ACME 申请，自备已解析的域名)"
      readp "请选择【1-3】：" cert_menu
      case "$cert_menu" in
        2)
          cert_type="ip"
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
          mkdir -p /root/ygkkkca
          echo "$ym_domain" > /root/ygkkkca/ca.log
          ;;
        *)
          cert_type="self"
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
  curl -sL "https://raw.githubusercontent.com/DuolaD/sing-box/main/version" | awk -F "更新内容" '{print $1}' | head -n 1 > "$SBFOLDER/v"
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
  if [ -f "$SBFOLDER/sb.json" ]; then
    [ ! -f "$SBFOLDER/sb10.json" ] && cp "$SBFOLDER/sb.json" "$SBFOLDER/sb10.json"
    [ ! -f "$SBFOLDER/sb11.json" ] && cp "$SBFOLDER/sb.json" "$SBFOLDER/sb11.json"
  fi
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
    latestV=$(curl -sL https://raw.githubusercontent.com/DuolaD/sing-box/main/version | awk -F "更新内容" '{print $1}' | head -n 1)
    if [ "$insV" = "$latestV" ]; then
      echo -e "当前 Sing-box 脚本最新版：${bblue}${insV}${plain} (已安装)"
    else
      echo -e "当前 Sing-box 脚本版本号：${bblue}${insV}${plain}"
      echo -e "检测到最新 Sing-box 脚本版本号：${yellow}${latestV}${plain} (可选择7进行更新)"
      echo -e "${yellow}$(curl -sL https://raw.githubusercontent.com/DuolaD/sing-box/main/version)${plain}"
    fi
  else
    latestV=$(curl -sL https://raw.githubusercontent.com/DuolaD/sing-box/main/version | awk -F "更新内容" '{print $1}' | head -n 1)
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
