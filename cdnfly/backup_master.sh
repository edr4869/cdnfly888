#!/bin/bash -x

#判断系统版本
check_sys(){
    local checkType=$1
    local value=$2

    local release=''
    local systemPackage=''
    local packageSupport=''

    if [[ "$release" == "" ]] || [[ "$systemPackage" == "" ]] || [[ "$packageSupport" == "" ]];then

        if [[ -f /etc/redhat-release ]];then
            release="centos"
            systemPackage="yum"
            packageSupport=true

        elif cat /etc/issue | grep -q -E -i "debian";then
            release="debian"
            systemPackage="apt"
            packageSupport=true

        elif cat /etc/issue | grep -q -E -i "ubuntu";then
            release="ubuntu"
            systemPackage="apt"
            packageSupport=true

        elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat";then
            release="centos"
            systemPackage="yum"
            packageSupport=true

        elif cat /proc/version | grep -q -E -i "debian";then
            release="debian"
            systemPackage="apt"
            packageSupport=true

        elif cat /proc/version | grep -q -E -i "ubuntu";then
            release="ubuntu"
            systemPackage="apt"
            packageSupport=true

        elif cat /proc/version | grep -q -E -i "centos|red hat|redhat";then
            release="centos"
            systemPackage="yum"
            packageSupport=true

        else
            release="other"
            systemPackage="other"
            packageSupport=false
        fi
    fi

    echo -e "release=$release\nsystemPackage=$systemPackage\npackageSupport=$packageSupport\n" > /tmp/ezhttp_sys_check_result

    if [[ $checkType == "sysRelease" ]]; then
        if [ "$value" == "$release" ];then
            return 0
        else
            return 1
        fi

    elif [[ $checkType == "packageManager" ]]; then
        if [ "$value" == "$systemPackage" ];then
            return 0
        else
            return 1
        fi

    elif [[ $checkType == "packageSupport" ]]; then
        if $packageSupport;then
            return 0
        else
            return 1
        fi
    fi
}

# 关闭健康检查
eval `grep "MYSQL_PASS" /opt/cdnfly/master/conf/config.py`
mysql -uroot -p$MYSQL_PASS cdn  -e 'update config set value="0" where name="node_health_check"'
mysql -uroot -p$MYSQL_PASS cdn  -e 'update config set value="0" where name="record-repair-enable"'

# 停止elasticsearch
#service elasticsearch stop

# 停止主控程序
supervisorctl stop all

# 启动mysql
if check_sys sysRelease ubuntu;then
    systemctl start mysql
elif check_sys sysRelease centos;then
    systemctl start mariadb
fi

# 备份mysql
mysqldump -uroot -p$MYSQL_PASS cdn | gzip > /root/cdn.sql.gz

# 停止mysql
if check_sys sysRelease ubuntu;then
    systemctl stop mysql
elif check_sys sysRelease centos;then
    systemctl stop mariadb
fi

# 备份elasticsearch
#cd /var/lib/
#tar cf elasticsearch.tar elasticsearch
#mv elasticsearch.tar /root/
