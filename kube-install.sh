#!/bin/sh

###################### [Kubernetes Install Script] #######################
#                                                                        #
#   Kubernetes Install Script for Ubuntu                                 #
#                                  - by hwkim (snoopy3476@outlook.com)   #
#                                                                        #
#                                                                        #
#   - Usage                                                              #
#     $ ./kube-install.sh master                                         #
#     $ ./kube-install.sh worker [master-ip] [token] [discovery-token]   #
#                                                                        #
#       * [master-ip]: IP address for the master node                    #
#                                                                        #
#       * [token]: Token of k8s master node                              #
#           - Get existing token by (on master node):                    #
#               $ kubeadm token list                                     #
#           - Create new token by (on master node):                      #
#               $ kubeadm token create                                   #
#                                                                        #
#       * [discovery-token]: Discovery token of k8s master node          #
#           - Get discovery token by (on master node):                   #
#               $ openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt |  #
#                 openssl rsa -pubin -outform der 2>/dev/null |          #
#                 openssl dgst -sha256 -hex | sed 's/^.* //'             #
#                                                                        #
#                                                                        #
#   - This script do the followings:                                     #
#     1. Disable system swap                                             #
#     2. Install prerequisites                                           #
#     3. (if "$INSTALL_DOCKER" == true) Remove docker if installed       #
#     4. (if "$INSTALL_DOCKER" == true) Install docker                   #
#     5. Install kubernetes, mark as no-auto-update                      #
#     6. Reset kubernetes if installed                                   #
#     7. Initialize k8s node according to the given args                 #
#                                                                        #
#                                                                        #
#   - All error log is written in "$LOGFILE". Check if error occurs.     #
#                                                                        #
#                                                                        #
##########################################################################


################################# config #################################

# log file path
LOGFILE=install.log

# whether to (re)install docker or not (true/false, default false)
# You can override this when execute by something like:
#     ex1:bash-like)  $ INSTALL_DOCKER=true ./kube-install.sh ...
#     ex2:common-ver) $ export INSTALL_DOCKER=true
#                       ./kube-install.sh ...
INSTALL_DOCKER_DEFAULT=false





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
	printf "  - Worker node:   %s worker [master-ip] [token] [discovery-token]\n" "$0"
	printf
}




# set swap to off
install_swapoff() {
	printf "function install_swapoff()\n"

	# apply to current boot
	sudo swapoff -a || return 255
	# apply after reboot
	sudo sed -e 's/\(.*swap\)/#\1/' -i /etc/fstab || return 255

	return 0
}


# install prerequisites
install_reqpkgs() {
	printf "function install_reqpkgs()\n"

	sudo apt-get update || return 255
	sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release \
		|| return 255

	return 0
}


# install docker
install_docker() {
	printf "function install_docker()\n"

	# remove previous docker
	sudo apt-get remove -y docker docker-engine docker.io containerd runc

	# install repo config
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
		sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
		|| return 255
	echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
		sudo tee /etc/apt/sources.list.d/docker.list > /dev/null \
		|| return 255

	# install docker
	sudo apt-get update || return 255
	sudo apt-get install -y docker-ce docker-ce-cli containerd.io || return 255

	sudo rm /etc/containerd/config.toml
	sudo systemctl restart containerd

	return 0
}


# install kubernetes
install_k8s() {
	printf "function install_k8s()\n"

	# install repo config
	curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - \
		|| return 255
	echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | \
		sudo tee /etc/apt/sources.list.d/kubernetes.list \
		|| return 255

	# install k8s
	sudo apt-get update || return 255
	sudo apt-get install -y --allow-change-held-packages kubelet kubeadm kubectl || return 255

	# prevent k8s auto-upgrade
	sudo apt-mark hold kubelet kubeadm kubectl || return 255

	return 0
}


# initialize k8s master node
init_k8s_master() {
	printf "function init_k8s_master()\n"

	# reset previous k8s
	sudo kubeadm reset -f

	# init kubeadm
	sudo kubeadm init --pod-network-cidr=10.244.0.0/16 || return 255
	mkdir -p "$HOME/.kube"
	sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config" || return 255
	sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config" || return 255

	# install calico
	curl https://docs.projectcalico.org/manifests/calico.yaml | \
		kubectl apply -f- \
		|| return 255

	return 0
}


# initialize k8s worker node
init_k8s_worker() {
	printf "function init_k8s_worker()\n"

	# reset previous k8s
	sudo kubeadm reset -f

	# join kubeadm
	sudo kubeadm join "$1:6443" --token "$2" --discovery-token-ca-cert-hash "sha256:$3" \
		|| return 255

	return 0
}









################################## main ##################################



##### check sudo & args, init vars #####

if ! { { [ "$1" = "master" ] && [ $# -eq 1 ] ; } || { [ "$1" = "worker" ] && [ $# -eq 4 ] ; } ; }
then
	print_usage
	exit 1
fi
sudo true || exit 1

rm -rf "$LOGFILE" 2> /dev/null # remove prev logfile if exists

# if INSTALL_DOCKER is defined by user when execute, use the given value
if [ -z "$INSTALL_DOCKER" ]
then
	INSTALL_DOCKER="$INSTALL_DOCKER_DEFAULT"
fi



##### confirm installation #####
print_noti "Kubernetes Install Script for Ubuntu" 0
if [ "$INSTALL_DOCKER" = "true" ]
then
	print_warn "This process resets both docker and k8s, if already installed." 0
else
	print_warn "This process resets k8s, if already installed." 0
fi

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
install_swapoff >> "$LOGFILE" 2>&1 || print_result_err_and_exit
print_result_pass



##### prepare required packages #####
print_work "Installing required packages..."
install_reqpkgs >> "$LOGFILE" 2>&1 || print_result_err_and_exit
print_result_pass



##### docker installation #####
if [ "$INSTALL_DOCKER" = "true" ]
then
	print_work "Installing docker..."
	install_docker >> "$LOGFILE" 2>&1 || print_result_err_and_exit
	print_result_pass
fi



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

# worker node
elif [ "$1" = "worker" ]
then
	print_work "Initializing k8s as a worker node... (master ip: $2, token: $3, discovery-token: $4)"
	init_k8s_worker "$2" "$3" "$4" >> "$LOGFILE" 2>&1 || print_result_err_and_exit
	print_result_pass

fi



##### check installation info #####

# docker
if [ "$INSTALL_DOCKER" = "true" ]
then
	print_noti "Docker installation info below" 0
	sudo docker run hello-world
fi

# k8s
print_noti "Kubernetes installation info below" 0
kubeadm version
kubelet --version
kubectl version

print_noti "Installing k8s finished!" 0
