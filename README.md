# DevStack Networking ― Quick‑Start Guide

These notes walk students through wiring a DevStack VM in **VirtualBox** so that

* the host (your laptop),
* the DevStack VM, **and**
* every OpenStack guest VM

all have Internet access **and** you can reach guests via floating‑IPs.

---
## 0  Prerequisites
| Item | Example | Notes |
|------|---------|-------|
| Host OS | Windows / macOS / Linux | Any OS that runs VirtualBox ≥ 7.0 |
| DevStack VM | Ubuntu 22.04 LTS (server) | 2 vCPU / 8 GB RAM / 80 GB disk |
| VirtualBox | 2 × NICs | **Adapter 1 = NAT**, **Adapter 2 = Host‑only** |

---
## 1.  VirtualBox network topology

![VirtualBox network topology](network.png)

*The Host‑only link is visible only to your laptop & the DevStack VM, keeping
things simple and secure.*

---
## 2.  Prepare the Host‑only network (do once)
1. _VirtualBox ▶ **File ▸ Preferences ▸ Network**_
2. Add **vboxnet0**:
   * IPv4 = `192.168.56.0/24`
   * **Disable** the DHCP server (DevStack will be DHCP later).

---
## 3.  Configure the VM NICs
| Adapter | Setting | Details |
|---------|---------|---------|
| **1** | NAT | leave defaults (gives Internet) |
| **2** | Host‑only Adapter → *vboxnet0* | carries floating‑IPs |

---
## 4.  Static IP inside the VM (Netplan)
Edit `/etc/netplan/10-enp0s8-static.yaml`:
```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s8:
      dhcp4: false
      addresses: [192.168.56.10/24]
      nameservers:
        addresses: [8.8.8.8,8.8.4.4]
```

Then apply the changes:
```bash
sudo netplan apply
```
---
## 5.  `local.conf` for DevStack

Create `/opt/stack/devstack/local.conf` with the following content:

(find the file in this repo: [local.conf](local.conf))

```bash
[[local|localrc]]

# Host IP Configuration
HOST_IP=192.168.56.10
SERVICE_HOST=$HOST_IP

# Credentials
ADMIN_PASSWORD=stackpass
DATABASE_PASSWORD=$ADMIN_PASSWORD
RABBIT_PASSWORD=$ADMIN_PASSWORD
SERVICE_PASSWORD=$ADMIN_PASSWORD

# Network Configuration
PUBLIC_INTERFACE=enp0s8
FLOATING_RANGE=192.168.56.0/24
PUBLIC_NETWORK_GATEWAY=192.168.56.1
Q_FLOATING_ALLOCATION_POOL=start=192.168.56.100,end=192.168.56.199
FIXED_RANGE=10.0.0.0/24
Q_USE_PROVIDERNET_FOR_PUBLIC=True
OVS_BRIDGE_MAPPINGS=public:br-ex
PUBLIC_BRIDGE=br-ex

# Enable Core Services
enable_service key n-api n-cond n-cpu n-sch n-novnc
enable_service glance
enable_service cinder c-api c-vol c-sch
enable_service horizon
enable_service neutron q-svc q-ovn-metadata-agent
enable_service placement-api
enable_service etcd
enable_service keystone

# Enable Telemetry Services
enable_plugin ceilometer https://opendev.org/openstack/ceilometer.git master
enable_service ceilometer-acompute ceilometer-acentral ceilometer-api ceilometer-collector

# Enable Billing Services
..............
```

## 6. Run DevStack
```bash
cd /opt/stack/devstack
./stack.sh
```


## 7. Post‑install checks

```bash
# IP sits on br-ex
ip a show br-ex | grep 192.168.56.10

# Neutron API alive
curl -s http://127.0.0.1:9696/ | head

# Horizon redirect
curl -I http://192.168.56.10/ | grep Location   # /auth/login/
```

## 8. Common pitfalls & fixes

| Symptom                         | Cause                        | Fix                                                                                 |
| ------------------------------- | ---------------------------- | ----------------------------------------------------------------------------------- |
| **SSH drop during stack**       | IP moved from enp0s8 → br‑ex | Use console                                   |
| 404 at `/dashboard`             | `horizon.conf` not enabled   | `sudo a2ensite horizon.conf && sudo systemctl restart apache2`                      |
| Connection refused to port 9696 | `neutron-server` dead        | `./rejoin-stack.sh` or `sudo systemctl restart devstack@q-svc`                      |


## 9.  Workflow

1. Boot VM & log in (stack/stack).

2. `cd ~/devstack && ./rejoin-stack.sh` – ensures all services are running.

3. Browse to http://192.168.56.10/ → login (`admin / stack`).

4. Create private network, router to public.

5. Launch instance, allocate floating‑IP (192.168.56.100+).

6. From laptop: `ssh ubuntu@<floating‑IP>`


# 10. After Seting Up your first project
### 10.1 Verify Initial Setup

Ensure public and private networks exist.

```bash
# Check OpenStack services
openstack network list
openstack subnet list
```


### 10.2 Configure Open vSwitch (OVS)

#### A. Clean Up Existing Bridges
```bash
# Remove all OVS bridges (start fresh)
sudo ovs-vsctl del-br br-ex
sudo ovs-vsctl del-br br-int

# Recreate bridges
sudo ovs-vsctl add-br br-ex
sudo ovs-vsctl add-br br-int
```

#### B. Assign Static IP to br-ex

```bash
# Assign IP (match your localrc HOST_IP)
sudo ip addr add 192.168.56.10/24 dev br-ex
sudo ip link set br-ex up

# Set default gateway
sudo ip route add default via 192.168.56.1 dev br-ex
```
#### C. Attach Physical Interface
```bash

# Replace `enp0s8` with your physical NIC
sudo ovs-vsctl add-port br-ex enp0s8
sudo ip link set enp0s8 up
```
D. Verify OVS Configuration
```bash
sudo ovs-vsctl show
```
Expected Output:

- br-ex with enp0s8 and no errors.
- br-int with no stale ports.


### 10.3 Fix Neutron Integration
#### A. Restart Services

```bash
sudo systemctl restart devstack@q-svc  # Neutron server
sudo systemctl restart devstack@q-agt  # OVS agent
sudo systemctl restart apache2         # Horizon dashboard
```

#### B. Clean Stale Ports

```bash
# List and delete stale tap interfaces
sudo ovs-vsctl list-ports br-int | grep tap | xargs -I {} sudo ovs-vsctl del-port br-int {}
```

### 10.4 Configure Security Groups

```bash
# Allow ICMP (ping) and SSH
openstack security group rule create --proto icmp --remote-ip 0.0.0.0/0 default
openstack security group rule create --proto tcp --dst-port 22 --remote-ip 0.0.0.0/0 default
```

### 10.5 Troubleshooting
#### A. Common Errors



#### B. Logs to Check

```bash
# OVS logs
sudo journalctl -u openvswitch-switch

# Neutron logs
tail -f /opt/stack/logs/q-svc.log
```

### 10.6 Final Checks

- `br-ex` has correct IP (`192.168.56.10/24`).
- `enp0s8` is attached to `br-ex` with no errors.
- Security groups allow `ICMP/SSH`.
- Instances get floating IPs and are reachable.


## Post-Install Steps for Azure

### 1. Allow API Access

Create NSG rules
```bash
openstack security group rule create --proto tcp --dst-port 5000,9696 --remote-ip 0.0.0.0/0 default
```


### 2. Persistent Storage

Attach Azure Disk for volumes:

```bash
openstack volume create --size 50 --type standard_lrs cinder-volumes
```