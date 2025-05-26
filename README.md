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

```bash
[[local|localrc]]

# Host IP address
#HOST_IP=$(hostname -I | awk '{print $1}')
HOST_IP=192.168.56.10
SERVICE_HOST=$HOST_IP


# Floating IPs: make sure this subnet is not in use on your local network
#FLOATING_RANGE=192.168.1.224/27

# Internal (fixed) network for VM communication
FIXED_RANGE=10.0.0.0/24

# Set common passwords
ADMIN_PASSWORD=stackpass
DATABASE_PASSWORD=$ADMIN_PASSWORD
RABBIT_PASSWORD=$ADMIN_PASSWORD
SERVICE_PASSWORD=$ADMIN_PASSWORD


# ---- Neutron + provider network on enp0s8 ----
PUBLIC_INTERFACE=enp0s8
PUBLIC_NETWORK_GATEWAY=192.168.56.1
FLOATING_RANGE=192.168.56.0/24
Q_FLOATING_ALLOCATION_POOL=start=192.168.56.100,end=192.168.56.199

# Map the interface into br-ex and expose it as a flat provider net
OVS_BRIDGE_MAPPINGS=public:br-ex
PUBLIC_BRIDGE=br-ex
Q_USE_PROVIDERNET_FOR_PUBLIC=True

# Enable services
enable_service h-eng h-api h-api-cfn h-api-cw   # Heat
enable_service horizon                          # Horizon dashboard
enable_service s-account s-container s-object s-proxy  # Swift

# Reduce disk usage for logs
LOGDAYS=1

# Disable rate limiting
API_RATE_LIMIT=False

# Destination directory for DevStack
DEST=/opt/stack

# Swift specific config
SWIFT_HASH=$(echo $RANDOM | md5sum | head -c 30)
SWIFT_REPLICAS=1

# Logging (optional)
LOGFILE=$DEST/logs/stack.sh.log


# ── Telemetry (metering + metrics + alarms) ─────────────────────────────────
enable_plugin ceilometer https://opendev.org/openstack/ceilometer
enable_service ceilometer-acompute ceilometer-acentral ceilometer-api \
               ceilometer-collector ceilometer-api-cfn ceilometer-api-cloudwatch
enable_plugin gnocchi https://opendev.org/openstack/gnocchi
enable_service gnocchi-api gnocchi-metricd gnocchi-statsd
enable_plugin aodh https://opendev.org/openstack/aodh
enable_service aodh-api aodh-evaluator aodh-notifier

# ── Billing / Rating ─────────────────────────────────────────────────────────
enable_plugin cloudkitty https://opendev.org/openstack/cloudkitty.git master
enable_service ck-api ck-proc ck-rating ck-upgrade

# ── Configuration snippets for Telemetry / Billing ────────────────────────────
# Ceilometer needs a notification driver:
CEILOMETER_NOTIFICATION_DRIVER=messagingv2

# Gnocchi
GNOCCHI_DB_CONNECT=sqlite:////opt/stack/data/gnocchi.sqlite
GNOCCHI_INDEXER_BACKEND=sqlite

# Aodh (alarms)
enable_service mongodb
AODH_BACKEND_DATABASE=mongodb

# CloudKitty (uses Ceilometer/ Gnocchi as data source)
CLOUDKITTY_BACKEND=sqlalchemy
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


## 10. After a reboot — what to expect & how to restore

DevStack does not rebuild the bridge on boot. Here are the approach you can have.

### Netplan bridge that survives reboots
Apply it once with sudo netplan apply. From then on `br‑ex` is up (with the IP) before DevStack starts, so SSH to `192.168.56.10` works immediately after every reboot.



```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s8: {}
  bridges:
    br-ex:
      interfaces: [enp0s8]
      addresses: [192.168.56.10/24]
      parameters:
        stp: false
```
