# Kubernetes Install Script for Ubuntu
- A simple script for installing kubernetes on Ubuntu
- Tested on Ubuntu 20.04
- Author: snoopy3476@outlook.com

## Usage
- Install master node:
  `$ ./kube-install.sh master`
- Install worker node:
  `$ ./kube-install.sh worker [master-ip] [token] [discovery-token]`
  - [master-ip]: IP address for the master node
  - [token]: Token of k8s master node
    - Get existing token by (on master node):
      `$ kubeadm token list`
    - Create new token by (on master node):
      `$ kubeadm token create`
  - [discovery-token]: Discovery token of k8s master node
    - Get discovery token by (on master node):
      `$ openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt |
         openssl rsa -pubin -outform der 2>/dev/null |
         openssl dgst -sha256 -hex | sed 's/^.* //'`
- If you also want to install docker, define `$INSTALL_DOCKER` to `true` by something like:
  `$ INSTALL_DOCKER=true ./kube-install.sh ...`

## Script details

### Job list of this script
 1. Disable system swap
 2. Install prerequisites packages
 3. (if "$INSTALL_DOCKER" == true) Remove docker if installed
 4. (if "$INSTALL_DOCKER" == true) Install docker
 5. Install kubernetes, mark as no-auto-update
 6. Reset kubernetes if installed
 7. Initialize k8s node according to the given args
 
### Error log
- All error log is written in "$LOGFILE". Check the file if any error occurs.
