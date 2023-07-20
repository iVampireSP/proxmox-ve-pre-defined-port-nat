#!/bin/bash

if [[ $# -lt 3 ]]; then
    echo "参数错误！请提供正确的网卡名称、网络段、起始端口和每个主机号的端口数量，本机 IP。如果需要测试模式，请在最后加上 test_mode 参数。"
    echo "示例：sudo bash $0 eth0 192.168.0.0/24 21000 10"
    exit 1
fi

# 解析网络段、起始端口和每个主机号的端口数量
subnet=$2
startPort=$3
portPerHost=$4
device=$1

# 检测网络段是否 CIDR
if [[ $subnet != *"/"* ]]; then
    echo "网络段必须是 CIDR 格式！"
    exit 1
fi  


# 验证起始端口和每个主机号的端口数量大于等于0
if [[ $startPort -lt 0 || $portPerHost -lt 0 ]]; then
    echo "起始端口和每个主机号的端口数量必须大于等于0！"
    exit 1
fi


# 传递的参数：IP地址和起始端口号
ip=$2
echo "CIDR 是 ${ip}。"

iptables -t nat -A POSTROUTING -s ${ip} -o ${device} -j MASQUERADE

# 去除 ip 的主机号和网段
ip=${ip%.*}

# portPerHost + 1
portPerHost=$((portPerHost + 1))

# 清除旧的iptables规则
iptables -t nat -F
iptables -t nat -X
iptables -t nat -Z
iptables -F
iptables -X
iptables -Z

# 设置默认策略
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# 启用IP转发
echo 1 > /proc/sys/net/ipv4/ip_forward

# 计算每个主机号的端口范围
function calculatePortRanges() {
    hostNumber=$1

    startPortNumber=$((startPort + (hostNumber * portPerHost)))
    endPortNumber=$((startPortNumber + portPerHost - 1))

    echo "IP地址 ${ip}.${hostNumber} 对应的端口范围是 ${startPortNumber} 到 ${endPortNumber}。"
}

# 创建新的iptables规则
function createPortForwardingRule() {
    set -x

    hostNumber=$1

    startPortNumber=$((startPort + (hostNumber * portPerHost)))
    endPortNumber=$((startPortNumber + portPerHost - 1))

    echo "IP ${ip}.${hostNumber} 的 SSH 端口是 ${startPortNumber}。"
    # SSH端口转发
    # iptables -t nat -A PREROUTING -p tcp --dport 22 -j DNAT --to-destination ${ip}.${hostNumber}:${startPortNumber}
    # iptables -t nat -A POSTROUTING -p tcp -d ${ip}.${hostNumber} --dport ${startPortNumber} -j SNAT --to-source ${ip}
    iptables -t nat -A PREROUTING -i ${device} -p tcp --dport ${startPortNumber} -j DNAT --to ${ip}.${hostNumber}:22
    iptables -t nat -A PREROUTING -i ${device} -p udp --dport ${startPortNumber} -j DNAT --to ${ip}.${hostNumber}:22

    # RDP端口转发
    echo "IP ${ip}.${hostNumber} 的 RDP 端口是 $((startPortNumber + 1))。"
    # iptables -t nat -A PREROUTING -p tcp --dport 3389 -j DNAT --to-destination ${ip}.${hostNumber}:$((startPortNumber + 1))
    # iptables -t nat -A POSTROUTING -p tcp -d ${ip}.${hostNumber} --dport $((startPortNumber + 1)) -j SNAT --to-source ${ip}
    iptables -t nat -A PREROUTING -i ${device} -p tcp --dport $((startPortNumber + 1)) -j DNAT --to ${ip}.${hostNumber}:3389
    iptables -t nat -A PREROUTING -i ${device} -p udp --dport $((startPortNumber + 1)) -j DNAT --to ${ip}.${hostNumber}:3389

    # 实际端口范围转发
    # iptables -t nat -A PREROUTING -p tcp --dport $((startPortNumber + 2)):$endPortNumber -j DNAT --to-destination ${ip}.${hostNumber}:$((startPortNumber + 2))
    # iptables -t nat -A POSTROUTING -p tcp -d ${ip}.${hostNumber} --dport $((startPortNumber + 2)) -j SNAT --to-source ${ip}
    # iptables -t nat -A PREROUTING -i ${device} -p all -d ${ip}.${hostNumber} --dport 10000:10999 -j DNAT --to 172.22.161.170:10000-10999

    startPortNumber=$((startPortNumber + 2))
    echo "起始端口号是 ${startPortNumber}。"
    endPortNumber=$((endPortNumber))
    echo "结束端口号是 ${endPortNumber}。"

    # 实际端口范围转发
    for ((portNumber = startPortNumber; portNumber <= endPortNumber; portNumber++)); do
        echo "IP ${ip}.${hostNumber} 的端口是 ${portNumber}。"
        iptables -t nat -A PREROUTING -i ${device} -p tcp --dport ${portNumber} -j DNAT --to ${ip}.${hostNumber}:${portNumber}
        iptables -t nat -A PREROUTING -i ${device} -p udp --dport ${portNumber} -j DNAT --to ${ip}.${hostNumber}:${portNumber}
    done
    
    set +x

}

# 循环遍历主机号
for hostNumber in $(seq 1 254); do
    if [ "$5" == "test_mode" ]; then
        calculatePortRanges $hostNumber
    else
        createPortForwardingRule $hostNumber
    fi
done

# 保存iptables规则
iptables-save > /etc/iptables.rules
