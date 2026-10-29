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


    