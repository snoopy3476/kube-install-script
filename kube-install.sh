#!/bin/sh

###################### [Kubernetes Install Script] #######################
#                                                                        #
#   Kubernetes Install Script for RHEL/Debian derivatives                #
#                             - by Kim Hwiwon (kim.hwiwon@outlook.com)   #
#                                                                        #
#   - Description                                                        #
#     Script to install kubernetes in clean-install Linux                #
#     (Target: Red Hat derivatives, Debian derivatives)                  #
#     (Tested on: Rocky Linux 9, Ubuntu 22.04)                           #
#                                                                        #
#   - Usage                                                              #
#     $ ./kube-install.sh master                                         #
#     $ ./kube-install.sh worker [kubeadm-join-args]                     #
#                                                                        #
#       * [kubeadm-join-args]: Arguments of cmdline for 'kubeadm join'   #
#         e.g.) $ [master-ip]:6443 --token [token] \                     #
#                --discovery-token-ca-cert-hash sha256:[discovery-token] #
#                                                                        #
#                                                                        #
#   - This script do the followings:                                     #
#     1. Disable system swap                                             #
#     2. Install prerequisites and related kernel modules, configures    #
#     3. Remove kubernetes and containerd, and reinstall                 #
#     4. Mark kubernetes as no-auto-update                               #
#     5. Initialize k8s node according to the given args                 #
#                                                                        #
#                                                                        #
#   - All error log is written in "install.log"                          #
#     (Remove on install succeeded)                                      #
#     Check it if error occurs.                                          #
#                                                                        #
#                                                                        #
##########################################################################



################################## env ###################################

# do not switch to permissive mode on selinux if set, on RHEL family.
NO_PERMISSIVE_SELINUX=${NO_PERMISSIVE_SELINUX:-}




################################# config #################################

# log file path
LOGFILE=install.log




################################## func ##################################

# terminal outputs

print_noti() {
  printf " \e[1;34m- %s\e[0m" "$1"
  [ -n "$2" ] && printf "\n"
}

print_warn() {
  printf " \e[1;37m\e[41m[WARNING]\e[0m %s" "$1"
  [ -n "$2" ] && printf "\n"
}

print_work() {
  printf " \e[1;34m- %s\e[0m" "$1"
}

print_result_pass() {
  printf " \e[1;32m>> Passed \e[0m\n"
}

print_result_err_and_exit() {
  printf " \e[1;31m>> \e[1;37m\e[41mFAILED!\e[0m\e[1;31m \e[0m\n"
  printf " * Check the log file '%s' for details *\n" "$LOGFILE"
  printf "   ex) $ less -r '%s'\n" "$LOGFILE"
  exit 1
}

print_usage() {
  printf "usage: \n"
  printf "  - Master node:   %s master\n" "$0"
  printf "  - Worker node:   %s worker [kubeadm-join-args]\n" "$0"
  printf "\n"
}




# package install/remove
pkg_install() {
  if command -v yum
  then
    sudo yum install -y ${PKG_HOLD:+"--disableexcludes=$PKG_HOLD"} "$@" || return 1
  elif command -v apt-get
  then
    sudo apt-get install -y "$@" || return 2
    [ -n "$PKG_HOLD" ] && sudo apt-mark hold "$@"
  else
    printf "No package manager found: run this script on redhat-based or debian-based linux\n"
    return 3
  fi

  return 0
}
pkg_remove() {
  if command -v yum
  then
    sudo yum remove -y "$@" || return 1
    sudo yum autoremove -y || return 1
  elif command -v apt-get
  then
    sudo apt-get purge -y ${PKG_HOLD:+"--allow-change-held-packages"} "$@" || return 2
    sudo apt-get autoremove --purge -y || return 2
  else
    printf "No package manager found: run this script on redhat-based or debian-based linux\n"
    return 3
  fi

  return 0
}


# set swap to off
install_swapoff() {
  printf "function install_swapoff()\n"

  
  # swap off for current boot
  sudo swapoff -a || return 255

  # mask systemd swap units
  sudo systemctl mask swap.target | return 255

  return 0
}


# install prerequisites
install_reqpkgs() {
  printf "function install_reqpkgs()\n"

  if command -v apt-get
  then
    sudo apt-get update
    pkg_install apt-transport-https ca-certificates curl gnupg lsb-release \
      || return 255
  fi
  
  
  if command -v yum
  then
    pkg_remove containerd.io runc
    pkg_install yum-utils || return 255
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo \
      || return 255
    command -v containerd && return 255
    pkg_install containerd.io runc || return 255
  elif command -v apt-get
  then
    sudo apt-get update
    pkg_remove containerd runc
    command -v containerd && return 255
    pkg_install containerd runc || return 255
  fi

  
  sudo rm /etc/containerd/config.toml
  sudo mkdir -p /etc/containerd/
  containerd config default | sudo tee /etc/containerd/config.toml || return 255
  sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
  sudo systemctl enable containerd || return 255
  sudo systemctl restart containerd || return 255

  
  return 0
}


# install kubernetes
install_k8s() {
  printf "function install_k8s()\n"


  # selinux config
  if command -v yum
  then
    if [ -z "$NO_PERMISSIVE_SELINUX" ]
    then
      sudo setenforce 0
      sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
    fi
  fi
  

  # add repo
  if command -v yum
  then

    echo "
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
" | sudo tee /etc/yum.repos.d/kubernetes.repo
    
  elif command -v apt-get
  then
    
    sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
    echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

    sudo apt-get update
  fi
  
  
  # prerequisite configs
  sudo modprobe overlay
  sudo modprobe br_netfilter
  echo "
br_netfilter
overlay
" | sudo tee /etc/modules-load.d/kube-conf.sh > /dev/null
  echo "
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
" | sudo tee /etc/sysctl.d/99-kube-conf.conf
  sudo sysctl --system


  # install k8s
  sudo kubeadm reset -f
  pkg_remove kubelet kubeadm kubectl
  sudo rm -rf /etc/cni/net.d /var/lib/etcd
  PKG_HOLD=kubernetes pkg_install kubelet kubeadm kubectl || return 255
  sudo systemctl enable kubelet
  sudo systemctl restart kubelet

  return 0
}


# initialize k8s master node
init_k8s_master() {
  printf "function init_k8s_master()\n"

  # init kubeadm
  sudo kubeadm init --pod-network-cidr=10.244.0.0/16 || return 255
  mkdir -p "$HOME/.kube"
  sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config" || return 255
  sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config" || return 255

  # install calico
  sudo systemctl restart containerd
  sudo systemctl restart kubelet
  retry_count=0
  while true
  do
    retry_count=$((retry_count + 1))
    if [ "$retry_count" -gt 15 ] # after 15 * 20 secs, set as failed
    then
      return 255
    fi

    sleep 20 # wait for k8s initialize
    curl https://docs.projectcalico.org/manifests/calico.yaml | \
      kubectl apply -f- \
      && break
  done

  # port for control plane
  if command -v yum
  then
    sudo firewall-cmd --zone=public --permanent \
         --add-port=6443/tcp \
         --add-port=2379-2380/tcp \
         --add-port=10250/tcp \
         --add-port=10259/tcp \
         --add-port=10257/tcp \
         --add-port=30000-32767/tcp \
         --add-port=179/tcp \
      || return 255
    sudo firewall-cmd --reload || return 255
  fi

  return 0
}


# initialize k8s worker node
init_k8s_worker() {
  printf "function init_k8s_worker()\n"

  # join kubeadm
  sudo kubeadm join "$@" || return 255

  # port for worker node
  if command -v yum
  then
    sudo firewall-cmd --zone=public --permanent \
         --add-port=10250/tcp \
         --add-port=30000-32767/tcp \
         --add-port=179/tcp \
      || return 255
    sudo firewall-cmd --reload || return 255
  fi

  return 0
}









################################## main ##################################



##### check sudo & args, init vars #####

if ! { { [ "$1" = "master" ] && [ $# -eq 1 ] ; } || { [ "$1" = "worker" ] && [ $# -eq 6 ] ; } ; }
then
  print_usage
  exit 1
fi
sudo true || exit 1

rm -rf "$LOGFILE" 2> /dev/null # remove prev logfile if exists



##### confirm installation #####
print_noti "Kubernetes Install Script for Ubuntu" 0
print_warn "This script is for use in clean-install OS!" 0
print_warn "It will RESETS all data for k8s and containerd if already installed, or REMOVES some config data." 0


while
  print_noti "Continue? [y/n]: "
  read -r CONTINUE
  [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ] \
  && [ "$CONTINUE" != "n" ] && [ "$CONTINUE" != "N" ]
do
  print_warn "Type 'y' or 'n'" 0
done

if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]
then
  print_noti "Installation canceled" 0
  exit 0
fi



##### swap off #####
print_work "Turning swap off..."
install_swapoff >> "$LOGFILE" 2>&1
ERR_CODE=$?
[ "$ERR_CODE" = 255 ] && print_result_err_and_exit
print_result_pass
[ "$ERR_CODE" = 1 ] && \
  print_warn "Found multiple 'grub.cfg' in '/boot/efi/EFI'!" 0 && \
  print_warn "You should run a command 'sudo grub2-mkconfig -o \$PATH_TO_GRUB_CFG' manually to the 'grub.cfg' of your OS inside '/boot/efi/EFI'." 0



##### prepare required packages #####
print_work "Installing required packages..."
install_reqpkgs >> "$LOGFILE" 2>&1 || print_result_err_and_exit
print_result_pass



##### k8s installation #####
print_work "Installing k8s..."
install_k8s >> "$LOGFILE" 2>&1 || print_result_err_and_exit
print_result_pass



##### node init #####

# master node
if [ "$1" = "master" ]
then
  print_work "Initializing k8s as a master node..."
  init_k8s_master >> "$LOGFILE" 2>&1 || print_result_err_and_exit
  print_result_pass

  print_noti "Use the command:" 0
  grep --color=never -A1 "^kubeadm join" "$LOGFILE" | sed 's/^kubeadm join /.\/kube-install.sh worker /g'
  print_noti "... to join this master node on other worker nodes." 0

# worker node
elif [ "$1" = "worker" ]
then
  print_work "Initializing k8s as a worker node..."
  shift
  init_k8s_worker "$@" >> "$LOGFILE" 2>&1 || print_result_err_and_exit
  print_result_pass

fi



##### check installation info #####

# k8s
print_noti "Kubernetes installation info below" 0
kubeadm version
kubelet --version
kubectl version 2>/dev/null

print_noti "Installing k8s finished!" 0
print_warn "You may need to reboot computer, to make installed k8s work properly" 0
rm -f "$LOGFILE" 2> /dev/null
