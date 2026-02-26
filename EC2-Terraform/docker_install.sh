#!/bin/bash

echo "Installing Docker..."

# Update system
sudo apt update -y

# Install required packages
sudo apt install -y ca-certificates curl gnupg

# Add Docker official GPG key
sudo install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt update -y
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Start Docker
sudo systemctl start docker
sudo systemctl enable docker

# Allow ubuntu user to run Docker without sudo
sudo usermod -aG docker ubuntu

echo "Docker installed successfully!"
echo "Please logout and login again to use Docker without sudo."