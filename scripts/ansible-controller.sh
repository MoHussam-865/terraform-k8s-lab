#!/bin/bash

sudo apt update

# install python3
sudo apt install python3 -y


#---------------------
# Create ansadmin user
#---------------------

if id "ansadmin" &>/dev/null; then
    echo "User ansadmin already exists"
else
    echo "Creating user ansadmin..."
    sudo useradd -m -s /bin/bash ansadmin
fi


# Add sudo permission if not already configured
if grep -q "^ansadmin ALL=(ALL) NOPASSWD: ALL" /etc/sudoers; then
    echo "ansadmin sudo permission already exists"
else
    echo "Adding ansadmin sudo permission..."
    echo "ansadmin ALL=(ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers > /dev/null
fi


#---------------------
# Install SSH
#---------------------

sudo apt install ssh -y


# install ansible
sudo apt install ansible -y


# Configure SSH folder

sudo mkdir -p /home/ansadmin/.ssh

sudo touch /home/ansadmin/.ssh/authorized_keys

sudo chown -R ansadmin:ansadmin /home/ansadmin/.ssh

sudo chmod 700 /home/ansadmin/.ssh

sudo chmod 600 /home/ansadmin/.ssh/authorized_keys


#---------------------
# Master Only
#---------------------

echo "Master node detected. Installing Ansible..."


# generate SSH keys if they don't exist

if [ ! -f /home/ansadmin/.ssh/id_rsa ]; then
    sudo -u ansadmin ssh-keygen -t rsa -b 4096 -N "" -f /home/ansadmin/.ssh/id_rsa
else
    echo "SSH keys already exist"
fi

# Create Ansible inventory

sudo mkdir -p /etc/ansible

# Create ansible.cfg if it does not exist
if [ ! -f /etc/ansible/ansible.cfg ]; then

    echo "Creating Ansible configuration..."

    sudo tee /etc/ansible/ansible.cfg > /dev/null <<EOF
[defaults]
host_key_checking = False
inventory = /etc/ansible/hosts
remote_user = ansadmin
private_key_file = /home/ansadmin/.ssh/id_rsa
EOF

else
    echo "Ansible configuration already exists"
fi

# Create Ansible inventory if it does not exist
if [ ! -f /etc/ansible/hosts ]; then

    echo "Creating Ansible inventory..."

    sudo tee /etc/ansible/hosts > /dev/null <<EOF
[master]
10.1.0.10

[workers]
10.1.0.6
10.1.0.8
EOF

else
    echo "Ansible inventory already exists"
fi


# Allow ansadmin to read inventory and config

sudo chown -R root:ansadmin /etc/ansible
sudo chmod 750 /etc/ansible
sudo chmod 640 /etc/ansible/ansible.cfg
sudo chmod 640 /etc/ansible/hosts


echo "Ansible setup completed successfully"


# ----------------------
# Create K8s cluster using Ansible playbook
# ----------------------

# echo "Creating k8s cluster using Ansible playbook..."

# git clone https://github.com/MoHussam-865/anible-k8s-project
# cd anible-k8s-project
# sed -i '1s/^\xEF\xBB\xBF//' ansible.cfg
# ansible-playbook playbooks/site.yml

# echo "cluster created successfully"

