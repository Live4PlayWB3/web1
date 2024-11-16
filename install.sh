#!/bin/bash

# Função para gerar senha aleatória
random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

# Array de caracteres para geração de IPs IPv6
array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)

# Função para gerar IPs no formato IPv6
gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# Função para instalar o 3proxy
install_3proxy() {
    echo "Instalando o 3proxy..."
    URL="https://github.com/3proxy/3proxy/releases/download/0.9.4/3proxy-0.9.4.tar.gz"
    wget -qO- $URL | bsdtar -xvf-
    cd 3proxy-0.9.4
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cp ./scripts/rc.d/proxy.sh /etc/init.d/3proxy
    chmod +x /etc/init.d/3proxy
    chkconfig 3proxy on
    cd $WORKDIR
}

# Função para gerar o arquivo de configuração do 3proxy
gen_3proxy() {
    cat <<EOF
daemon
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth strong

users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' ${WORKDATA})

$(awk -F "/" '{print "auth strong\n" \
"allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

# Função para gerar o arquivo de proxies para o usuário
gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

# Função para fazer upload do arquivo de proxies
upload_proxy() {
    local PASS=$(random)
    zip --password $PASS proxy.zip proxy.txt
    URL=$(curl -s --upload-file proxy.zip https://bashupload.com/proxy.zip)

    echo "Proxy está pronto! Formato IP:PORT:LOGIN:PASS"
    echo "Baixe o arquivo zip de: ${URL}"
    echo "Senha: ${PASS}"
}

# Função para gerar os dados de proxy
gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 $IP6)"
    done
}

# Função para gerar as regras de iptables
gen_iptables() {
    cat <<EOF
    $(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA}) 
EOF
}

# Função para gerar os comandos de ifconfig
gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

# Verificação de permissões e execução do script como root
if [ "$(id -u)" -ne 0 ]; then
    echo "Este script precisa ser executado como root ou com sudo."
    exit 1
fi

# Instalando pacotes necessários
echo "Instalando pacotes necessários..."
yum -y install gcc net-tools bsdtar zip wget curl >/dev/null

# Definir diretórios de trabalho
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"

# Criação do diretório de trabalho
mkdir -p $WORKDIR && cd $WORKDIR

# Obter IPs internos e externos
IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "IP interno = ${IP4}. Subnet externa para IPv6 = ${IP6}"

# Perguntar ao usuário quantos proxies deseja criar
echo "Quantos proxies você deseja criar? Exemplo 500"
read COUNT

FIRST_PORT=10000
LAST_PORT=$(($FIRST_PORT + $COUNT))

# Gerar dados de proxy e configurações
gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x ${WORKDIR}/boot_*.sh /etc/rc.local

# Gerar configuração do 3proxy
gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

# Adicionar comandos ao rc.local para iniciar o 3proxy automaticamente
cat >>/etc/rc.local <<EOF
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 10048
service 3proxy start
EOF

# Rodar as configurações no rc.local
bash /etc/rc.local

# Gerar e fazer upload do arquivo de proxies
gen_proxy_file_for_user
upload_proxy
