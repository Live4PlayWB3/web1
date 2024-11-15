#!/bin/bash
set -euo pipefail

# Cores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Funções melhoradas
random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c8
    echo
}

array=({0..9} {a..f})

gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

install_required_packages() {
    echo -e "${BLUE}Instalando pacotes necessários...${NC}"
    dnf update -y
    dnf install gcc net-tools bsdtar zip make wget curl iptables-services -y
}

install_3proxy() {
    echo -e "${BLUE}Instalando 3proxy...${NC}"
    URL="https://raw.githubusercontent.com/quayvlog/quayvlog/main/3proxy-3proxy-0.8.6.tar.gz"
    wget -qO- $URL | bsdtar -xvf- || exit 1
    cd 3proxy-3proxy-0.8.6 || exit 1
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cp ./scripts/rc.d/proxy.sh /etc/init.d/3proxy
    chmod +x /etc/init.d/3proxy
    systemctl daemon-reload
    cd $WORKDIR
}

# Configurações principais
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR

# Verificação de IPv6
check_ipv6() {
    sysctl -w net.ipv6.conf.all.disable_ipv6=0
    sysctl -w net.ipv6.conf.default.disable_ipv6=0
}

# Instalação principal
main_install() {
    install_required_packages
    install_3proxy
    check_ipv6

    IP4=$(curl -4 -s icanhazip.com)
    IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

    echo -e "${GREEN}IP4: ${IP4}${NC}"
    echo -e "${GREEN}IP6: ${IP6}${NC}"

    read -p "Quantos proxies deseja criar (1-1000)? " COUNT
    [[ ! $COUNT =~ ^[0-9]+$ ]] || [ $COUNT -lt 1 ] || [ $COUNT -gt 1000 ] && {
        echo "Por favor digite um número entre 1 e 1000"
        exit 1
    }

    FIRST_PORT=10000
    LAST_PORT=$(($FIRST_PORT + $COUNT))

    # Gera configurações
    gen_data >$WORKDIR/data.txt
    gen_iptables >$WORKDIR/boot_iptables.sh
    gen_ifconfig >$WORKDIR/boot_ifconfig.sh
    chmod +x ${WORKDIR}/boot_*.sh

    # Configura 3proxy
    gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg
    chmod 777 /usr/local/etc/3proxy/3proxy.cfg
    mkdir -p /var/log/3proxy

    # Desativa firewall
    systemctl stop firewalld
    systemctl disable firewalld

    # Inicia serviços
    bash ${WORKDIR}/boot_iptables.sh
    bash ${WORKDIR}/boot_ifconfig.sh
    systemctl enable 3proxy
    systemctl start 3proxy

    # Gera arquivo de proxies
    gen_proxy_file_for_user
    upload_proxy
}

# Executa instalação
main_install
