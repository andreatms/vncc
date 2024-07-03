# Utilizzo dello strumento software Terraform per lo sviluppo di applicativo su cluster Kubernetes

Progetto di Virtual Network and Cloud Computing

## Requisiti
- Python 3
- [Kubespray](https://github.com/kubernetes-sigs/kubespray.git)
- [Terraform](https://terraform.io)

## Setup Kubernetes cluster
Per creare questo cluster sono state utilizzare due macchine virtuali Xubuntu 22 con 4 GB di RAM e 2 vCores ciascuna, connesse tramite una rete con NAT gestita da VirtualBox.

### Setup della rete
Per prima cosa bisogna modificare la configurazione di rete modificando il file  ```/etc/netplam/01-network-manager-all.yaml```
```bash
sudo nano /etc/netplan/01-network-manager-all.yaml
```
---
**Controller**
```yml
network:
   version: 2 
   renderer: NetworkManager 
   ethernets:
      enp0s3: 
      dhcp4: no 
      addresses: [192.168.43.10/24] 
      gateway4: 192.168.43.1 
      nameservers: addresses: [8.8.8.8, 8.8.4.4]
```

**Worker**
```yml
network: 
   version: 2 
   renderer: NetworkManager
   ethernets: 
      enp0s3: 
      dhcp4: no 
      addresses: [192.168.43.11/24] 
      gateway4: 192.168.43.1 
      nameservers: addresses: [8.8.8.8, 8.8.4.4]
```
---

Modificare il file  ```/etc/hosts``` ed inserire le seguenti righe.
```bash
sudo nano /etc/hosts
```
```bash
192.168.43.10 controller controller.example.com 
192.168.43.11 worker worker.example.com 

# Ansible inventory hosts BEGIN 
192.168.43.10 controller.provaspray.local controller node1 
192.168.43.11 worker.provaspray.local worker node2
```
---
Si procede ora a configurare un accesso remoto tramite SSH per far comunicare le macchine, va quindi creata una coppia di chiavi con i seguenti comandi
```bash
ssh-keygen -t rsa -P ""
```
Si procede ora a copiare le chiavi
```bash
ssh-copy-id 192.168.43.10
ssh-copy-id 192.168.43.11
```
Modificare il file ```/etc/sudoers``` e modificare le seguenti righe
```bash
sudo nano /etc/sudoers
```
```
root ALL=(ALL) NOPASSWD: ALL
<utente> ALL=(ALL) NOPASSWD: ALL
```
### Setup Kubespray
#### Requisiti
Installare python su tutti i nodi del cluster
```bash
sudo apt install python3-pip
sudo pip3 install --upgrade pip
sudo apt install git
```
#### Kubespray
Scaricare ed installare kubespray nel controller
```bash
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
sudo pip install -r requirements.txt
```
Copiare la cartella ```inventory/sample``` in ```inventory/mycluster```
```bash
cp -rfp inventory/sample inventory/cluster
```
Aggiornare l'inventory file di Ansible come segue:
```bash 
declare -a IPS=(192.168.43.10 192.168.43.11)
CONFIG_FILE=inventory/mycluster/hosts.yaml python3 contrib/inventory_builder/inventory.py ${IPS[@]}
```
Controllare ora la configurazione del file ```inventory/mycluster/hosts.yml```
```yml 
all:
   hosts: 
      node1: 
         ansible_host: 192.168.43.10
         ip: 192.168.43.10 
         access_ip: 192.168.43.10 
      node2: 
         ansible_host: 192.168.43.11
         ip: 192.168.43.11
         access_ip: 192.168.43.11
   children: 
      kube_control_plane:
         hosts:
            node1:
      kube_node: 
         hosts:
            node2:
      etcd:
         hosts:
            node1:
      k8s_cluster: 
         children: 
            kube_control_plane:
            kube_node: 
      calico_rr: 
         hosts: {}
```
Modificare il file ```inventory/mycluster/group_vars/all/all.yml```
```yml 
upstream_dns_servers:
   - 8.8.8.8
   - 8.8.4.4
```
Modificare le seguenti righe del file ```inventory/mycluster/group_vars/k8s-cluster/k8s-cluster.yml```
```yml 
kube_config_dir: /etc/kubernetes
```
```yml 
kube_network_plugin: calico
```
```yml 
# Kubernetes internal network for services, unused block of space. kube_service_addresses: 10.233.0.0/18 
# internal network. When used, it will assign IP 
# addresses from this range to individual pods. 
# This network must be unused in your network infrastructure!
kube_pods_subnet: 172.16.0.0/24
```
```yml 
kube_network_node_prefix: 24
```
```yml 
container_manager: containerd
```
```yml 
resolvconf_mode: host_resolvconf
```

Resettare il cluster per controllare che le connessioni e le configurazioni siano funzionanti
```bash
ansible-playbook -i inventory/mycluster/hosts.yaml --become --become-user=root reset.yml
```
Installare ora kubernetes
```bash
ansible-playbook -i inventory/mycluster/hosts.yaml --become --become-user=root cluster.yml
```
Installare kubectl
```bash
sudo snap install kubectl --classic
```
e renderlo utilizzabile da un utente diverso da root
```bash
sudo cp /etc/kubernetes/admin.conf /home/<utente>/config
```
---
(Opzionale) Modificare il file in sola lettura
```bash
sudo chmod +r ~/config
```
---
```bash
mkdir .kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Controllare il corretto funzionamento del cluster
```bash
kubectl get nodes
```
### Componenti aggiuntivi
#### Metrics server
Scaricare il file
```bash
wget -O components.yaml https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```
e aggiungere la seguente riga in fondo
```yaml
- --kubelet-insecure-tls
```
Creare il metric server
```bash
kubectl apply -f ./components.yaml
```
## Setup Terraform
Aggiungere la repository di Hashicorp
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update
```
Installare Terraform
```bash
sudo apt install terraform
```
Verificare l'avvenuta installazione tramite il comando
```bash
terraform -help
```

## Deploy del progetto Terraform
Per prima cosa è necessario creare un file ```terraform.tfvars``` in cui vengono dichiarate le seguenti variabili
```
host                   = "https://127.0.0.1:6443"
client_certificate     = "LS0tLS1..."
client_key             = "LS0tLS1..."
cluster_ca_certificate = "LS0tLS1..."
```
Per visualizzare i valore da inserire è sufficiente utilizzare il comando
 ```bash
kubectl config view --minify --flatten
```


Per creare il progetto è necessario eseguire i seguenti comandi nella directory in cui sono posizionati i file  ```file_server.tf``` (o qualsiasi altro ```.tf```)  e ```terraform.tfvars```
#### Inizializzazione del ambiente Terraform
```bash
terraform init
```
#### Pianificazione
```bash
terraform plan
```
Tramite questo comando, Terraform andrà ad elencare le modifiche che verranno applicate al progetto tramite il comando successivo.
#### Creazione/Modifica
```bash
terraform apply
```
Questo comando mostrerà nuovamente le modifiche che verranno eseguite dopo aver confermato l'invio del comando tramite la stringa ```yes```. 

#### Eliminazione
```bash
terraform destroy
```
Tramite questo comando è possibile rilasciare tutte le risorse gestite dal progetto Terraform.
