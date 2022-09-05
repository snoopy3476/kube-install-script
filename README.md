# Kubernetes Install Script for Linux server
- A simple script for installing and configuring kubernetes
  on clean-install Linux server automatically
- Targeted for: _RHEL_ derivatives, _Debian_ derivatives
- Tested on: `Rocky Linux 9`, `Ubuntu 22.04`
- Author: kim.hwiwon@outlook.com

## Usage

- Install master node:
  `$ ./kube-install.sh master`

- Install worker node:
  `$ ./kube-install.sh worker [kubeadm-join-args]`
  - `[kubeadm-join-args]`: Arguments of cmdline for 'kubeadm join'
    - e.g.) `$ [master-ip]:6443 --token [token]
            --discovery-token-ca-cert-hash sha256:[discovery-token]`

- You may need to reboot computer after install, to make installed k8s work properly.

- This script set SELinux to PERMISSIVE MODE by default.  
  To keep SELinux in enforced mode, set `NO_PERMISSIVE_SELINUX` like:  
  `$ NO_PERMISSIVE_SELINUX=true ./kube-install.sh ...`

## Script details

### Job list of this script
 1. Disable system swap (mask systemd swap.target)
 2. Install prerequisites and related kernel modules, configures
 3. Remove kubernetes and containerd, and reinstall
 4. Mark kubernetes as no-auto-update
 5. Initialize k8s node according to the given args
 
### Error log
- All error log is written in `install.log` (removed on install succeeded).  
  Check the file if any error occurs.

### Warning
- You might be able to use this script on non-clean-install Linux without any problem,
  but as the script assume the system status as "clean",
  some problem might exist after applying this on Linux which has been used for other purposes.
