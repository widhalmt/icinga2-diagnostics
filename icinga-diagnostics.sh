#!/bin/bash

if [ "$(id -u)" != "0" ]; then
  echo "Not running as root. Not all checks might be successful"
  RUNASROOT=false
else
  echo "Running as root"
  RUNASROOT=true
fi

if [ $(which systemctl 2>/dev/null) ]
then
  SYSTEMD=true
fi

function check_service {
  if [ "${SYSTEMD}" = "true" ]
  then
    systemctl is-active $1
  else
    service $1 status > /dev/null && echo "active" || echo "inactive"
  fi
}

function doc_icinga2 {
  echo ""
  echo "Packages:"
  if [ "${OS}" = "REDHAT" ]
  then
    for i in $(rpm -qa | grep icinga); do (rpm -qi $i | grep ^Name | cut -d: -f2); (rpm -qi $i | grep Version); (if [ "$(rpm -qi $i | grep ^Signature | cut -d, -f3 | awk '{print $3}')" == "c6e319c334410682" ]; then echo "Signed with Icinga key"; else echo "Not signed with Icinga Key, might be original anyway"; fi) ; done
  else
    echo "Can not query packages on ${OS}"
  fi

  # rpm -q --queryformat '%|DSAHEADER?{%{DSAHEADER:pgpsig}}:{%|RSAHEADER?{%{RSAHEADER:pgpsig}}:{%|SIGGPG?{%{SIGGPG:pgpsig}}:{%|SIGPGP?{%{SIGPGP:pgpsig}}:{(none)}|}|}|}|\n\' icinga2

  echo ""
  echo "Features:"
  icinga2 feature list

  echo ""
  echo "Zones and Endpoints:"
  for i in $(icinga2 object list --type zone | grep ^Object | cut -d\' -f2) ; do (echo $i ); (icinga2 object list --type Zone --name $i | grep -e 'endpoints =' -e 'parent =' -e 'global =' | grep -v -e '= null' -e '= false' -e '= ""') done

  echo ""
  echo "Check intervals:"
  icinga2 object list --type Host | grep check_interval | sort | uniq -c | sort -rn
  icinga2 object list --type Service | grep check_interval | sort | uniq -c | sort -rn

}

function doc_icingaweb2 {

  echo ""
  echo "Packages:"
  ${QUERYPACKAGE} icingaweb2
  ${QUERYPACKAGE} php
  if [ "${OS}" = "REDHAT" ]
  then
    ${QUERYPACKAGE} httpd
  else
    echo "Can not query webserver package on ${OS}"
  fi

  echo ""
  echo "Icinga Web 2 Modules:"
  # Add options for modules in other directories
  icingacli module list
  for i in $(icingacli module list | grep -v ^MODULE | awk '{print $1}'); do if [ -d /usr/share/icingaweb2/modules/$i/.git ]; then echo "$i via git - $(cd /usr/share/icingaweb2/modules/$i && git log -1 --format=\"%H\")" ; else echo "$i via release archive/package";  fi ; done

  echo ""
  echo "Icinga Web 2 commandtransport configuration:"
  cat /etc/icingaweb2/modules/monitoring/commandtransports.ini

}

function doc_firewall {
  echo -n "Firewall: "

  if [ "$1" == "f" ]
  then  
    if [ "${RUNASROOT}" = "true" ]
    then
      iptables -nvL
    else
      echo "# Can not read firewall configuration without root permissions #"
    fi
  else
    if [ "${SYSTEMD}" = "true" ]
    then
      check_service firewalld
    else
      check_service iptables
    fi
  fi 
}

echo ""
echo "## OS ##"
echo ""
echo -n "OS Version: "

if [ -n "$(cat /etc/redhat-release)" ]
then
  QUERYPACKAGE="rpm -q"
  OS="REDHAT"
  cat /etc/redhat-release
else
  lsb_release -irs
fi


echo -n "Hypervisor: "


VIRT=$(bash virt-what 2>/dev/null)

if [ -z ${VIRT} ]
then
  echo "Running on hardware or unknown hypervisor"
else
  if [ "$(echo ${VIRT} | head -1)" = "xen" ]
  then
    if [ "$(echo ${VIRT} | tail -1)" = "xen-dom0" ]
    then
      VIRTUAL=false
    else
      VIRTUAL=true
      HYPERVISOR="Xen"
    fi
  else
    VIRTUAL=false
  fi

  if [ "${VIRTUAL}" ]
  then
    echo "Running on Hardware or unknown Hypervisor"
  else
    echo "Running virtually on a ${HYPERVISOR} hypervisor"
  fi
fi

#dmidecode | grep -i vmware
#lspci | grep -i vmware
#grep -q ^flags.*\ hypervisor\ /proc/cpuinfo && echo "This machine is a VM"

echo -n "CPU cores: "

cat /proc/cpuinfo | grep ^processor | wc -l

echo -n "RAM: "

free -h | grep ^Mem | awk '{print $2}'


if [ "${OS}" = "REDHAT" ]
then
  echo -n "SELinux: "
  getenforce
fi

## troubleshooting SELinux for Icinga 2
#semodule -l | grep -e icinga2 -e nagios -e apache
#ps -eZ | grep icinga2
#semanage port -l | grep icinga2
#getsebool -a | grep icinga2
#audit2allow -li /var/log/audit/audit.log

doc_firewall

echo ""
echo "# Icinga 2 #"
echo ""
${QUERYPACKAGE} icinga2 > /dev/null
if [ $? -eq 0 ]
then
  doc_icinga2
else
  echo "Icinga 2 is not installed"
fi

echo ""
echo "# Icinga Web 2 #"
echo ""
${QUERYPACKAGE} icingaweb2 > /dev/null
if [ $? -eq 0 ]
then
  doc_icingaweb2
else
  echo "Icinga Web 2 is not installed"
fi


