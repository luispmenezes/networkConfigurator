#!/bin/bash

if [ `whoami` != root ]; then
	echo -e '\033[31mSuper user privilages required!\033[0m' 
	exit $?;
fi

if ! which ip route &> /dev/null ;then
	echo -e '\033[31mIp Route is not installed!!\033[0m'
    exit $?;
fi

ETH_TRGT_W="200"
WLA_TRGT_W="50"
LCL_TRGT_W="5"

ETH=$(ip -o link show | awk '{print substr($2, 1, length($2)-1)}' | sed -n 2p)
WLA=$(ip -o link show | awk '{print substr($2, 1, length($2)-1)}' | sed -n 3p)

ETH_W=$(ip route | awk '$1=="default" {print $5, $9}' | awk -v iface="$ETH" '$1==iface {print $2}')
WLA_W=$(ip route | awk '$1=="default" {print $5, $9}' | awk -v iface="$WLA" '$1==iface {print $2}')

ETH_GW=$( ip route | awk '$1=="default" {print $3,$5}' | awk -v iface="$ETH" '$2==iface {print $1}')
WLA_GW=$( ip route | awk '$1=="default" {print $3,$5}' | awk -v iface="$WLA" '$2==iface {print $1}')

if [ -z "$ETH_GW" ] || [ -z "$WLA_GW" ];then
	echo -e '\033[31mNo default Gateways found!!\033[0m'
	read  -n 1 -p "Set Default Gateways?(y/n)" setGW
	if [ "$setGW" = "y" ];then
		read  -n 1 -p "Use default values?(y/n)" autoConf
		if [ "$autoConf" = "y" ];then
			if [ -z "$ETH_GW" ]; then
				ETH="10.112.82.254"
			fi
			if [ -z "$WLA_GW" ]; then
				ETH="192.168.1.254"
			fi
		else
			if [ -z "$ETH_GW" ]; then
				read  -n 1 -p "Gateway for $ETH" ETH_GW
			fi
			if [ -z "$WLA_GW" ]; then
				read  -n 1 -p "Gateway for $WLA" WLA_GW
			fi
		fi
	else
		exit $?;
	fi  
fi

echo "Gateways->
	$ETH: $ETH_GW   metric $ETH_W 
	$WLA: $WLA_GW   metric $WLA_W"

if [ "$1" = "--revert" ]; then
	echo "Reseting configurations..."
	ip route del 10.0.0.0/8 via $ETH_GW
	ip route del 172.16.0.0/12 via $ETH_GW
	ip route del 192.168.0.0/16 via $ETH_GW

    if [ -z "${http_proxy}" ]; then
    	echo "Setting proxy environment variables..."
    	echo 'http_proxy="http://194.65.37.122:80"' >> /etc/environment 
        echo 'https_proxy="http://194.65.37.122:80"' >> /etc/environment
		echo 'ftp_proxy="http://194.65.37.122:80"' >> /etc/environment
		echo 'no_proxy="localhost,127.0.0.1,.ptin.corppt.com,10.112.97.170,10.112.85.38,ept.telecom.pt,http://asmill01"' >> /etc/environment 
    	source /etc/environment
    	for env in $( cat /etc/environment )
    	do
    		if [[ ${env:0:1} != '#' ]]; then
    			export $(echo $env | sed -e 's/"//g')
    		fi
    	done
    fi
    	
	if wget -q --spider maven.ptin.corppt.com/webapp/ && wget -q --spider google; then
		echo  -e '\033[32mDe-Configuration is OK\033[0m'
	else
		echo  -e '\033[31mDe-Configuration is not OK :(\033[0m'
	fi  

	exit $?;
fi 

if [ -z "$ETH_W" ] || [ -z "$WLA_W" ] || [ "$ETH_W" -lt "$WLA_W" ]; then
	echo "Changing default routes..."
	ip route del default via $ETH_GW
	ip route del default via $WLA_GW
	ip route add default via $ETH_GW dev $ETH proto dhcp metric $ETH_TRGT_W
	ip route add default via $WLA_GW dev $WLA proto dhcp metric $WLA_TRGT_W
fi

echo "Setting local routes..."

if ! ip route | grep -q "10.0.0.0/8 via $ETH_GW dev $ETH metric $LCL_TRGT_W"; then
	echo '	Adding route for Class A'
	ip route add 10.0.0.0/8 via $ETH_GW dev $ETH metric $LCL_TRGT_W	
fi

if ! ip route | grep -q " 172.16.0.0/12 via $ETH_GW dev $ETH metric $LCL_TRGT_W"; then
	echo '	Adding route for Class B'
	ip route add 172.16.0.0/12 via $ETH_GW dev $ETH metric $LCL_TRGT_W	
fi

if ! ip route | grep -q "192.168.0.0/16 via $ETH_GW dev $ETH metric $LCL_TRGT_W"; then
	echo '	Adding route for Class C'
	ip route add 192.168.0.0/16 via $ETH_GW dev $ETH metric $LCL_TRGT_W	
fi

echo "Setting DNS..."
DNS_FILE='/etc/resolv.conf'
if [ -f /etc/resolvconf/resolv.conf.d/head ]; then
	DNS_FILE='/etc/resolvconf/resolv.conf.d/head'
fi

echo 'nameserver 10.112.15.3
nameserver 10.112.15.6
nameserver 1.1.1.1
nameserver 1.0.0.1' > $DNS_FILE

if [ -f /etc/dhcpcd.conf ]; then
	echo "inteface $ETH
	metric $ETH_TRGT_W

	interface $WLA
	metric $WLA_TRGT_W" > /etc/dhcpcd.conf
fi

if [ ! -z "${http_proxy}" ]; then
	echo "Setting proxy environment variables..."
	sed -i "$(($(wc -l < /etc/environment) - 3)),\$d" /etc/environment
	source /etc/environment
	unset http_proxy
	unset https_proxy
	unset ftp_proxy
	unset no_proxy
fi	

grep -q -F '10.112.15.17    asmill01' /etc/hosts || echo '10.112.15.17    asmill01' >> /etc/hosts

echo 'Testing Configuration...'

if wget -q --spider twitter.com && wget -q --spider maven.ptin.corppt.com/webapp/; then
	echo  -e '	\033[32mConfiguration is OK\033[0m'
else
	echo  -e '	\033[31mConfiguration is not OK :(\033[0m'
fi  