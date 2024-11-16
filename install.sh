#!/bin/bash

# Função para gerar senhas aleatórias
random() {
  tr </dev/urandom -dc A-Za-z0-9 | head -c5
  echo
}

# Função para gerar um IP IPv6 aleatório
array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
  ip64() {
    echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
  }
  echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# Função para instalar o 3proxy
install_3proxy() {
  echo "Instalando 3proxy..."
  URL="https://raw.githubusercontent.com/tungtruong20xx/multi_proxy_ipv6/main/3proxy-3proxy-0.9.4.tar.gz"
  wget -qO- $URL | bsdtar -xvf-
  cd 3proxy-3proxy-0.9.4
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

# Função para gerar o arquivo de proxy para o usuário
gen_proxy_file_for_user() {
  cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

# Função para fazer o upload do arquivo de proxy
upload_proxy() {
  local PASS=$(random)
  zip --password $PASS proxy.zip proxy.txt
  JSON=$(curl -sF "file=@proxy.zip" https://file.io)
  URL=$(echo "$JSON" | jq --raw-output '.link')

  echo "Proxy pronto! Formato IP:PORTA:LOGIN:SENHA"
  echo "Baixe o arquivo zip no link: ${URL}"
  echo "Senha: ${PASS}"
}

# Função para gerar os dados de proxy
gen_data() {
  seq $FIRST_PORT $LAST_PORT | while read port; do
    echo "//$IP4/$port/$(gen64 $IP6)"
  done
}

# Função para gerar as regras do iptables
gen_iptables() {
  cat <<EOF
    $(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA})
EOF
}

# Função para gerar as configurações de rede (ifconfig)
gen_ifconfig() {
  cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

# Instalar dependências
echo "Instalando pacotes necessários..."
yum -y install gcc net-tools bsdtar zip jq >/dev/null

# Instalar o 3proxy
install_3proxy

# Definir diretórios e variáveis
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR && cd $WORKDIR

# Obter o IP externo e IP6
IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "IP interno = ${IP4}. Subnet externa para IP6 = ${IP6}"

# Perguntar ao usuário quantos proxies ele deseja criar
echo "Quantos proxies você quer criar? (Exemplo: 500)"
read COUNT

FIRST_PORT=10000
LAST_PORT=$(($FIRST_PORT + $COUNT))

# Gerar dados, iptables e ifconfig
gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x ${WORKDIR}/boot_*.sh /etc/rc.local

# Gerar configuração do 3proxy
gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

# Adicionar no rc.local para executar na inicialização
cat >>/etc/rc.local <<EOF
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 10048
service 3proxy start
EOF

# Executar rc.local para inicializar
bash /etc/rc.local

# Gerar o arquivo de proxy e fazer upload
gen_proxy_file_for_user
upload_proxy
