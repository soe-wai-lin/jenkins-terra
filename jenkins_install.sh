#!/bin/bash

exec > /var/log/user-data.log 2>&1

set -e  # Exit on any error

# Update package list
sudo apt-get update -y

sudo touch /test

# Install required dependencies
sudo apt-get install -y gnupg curl software-properties-common apt-transport-https

# Add Jenkins GPG key
sudo mkdir -p /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian/jenkins.io-2023.key

# Add Jenkins repository
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian binary/" | \
  sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

# Update package list again with Jenkins repo
sudo apt-get update -y

# Install Jenkins and Java if not already present
sudo apt-get install -y openjdk-17-jdk 

sudo apt-get install jenkins -y

# Enable and start Jenkins service
sudo systemctl start jenkins

sudo systemctl enable --now jenkins

### Trivy Install ###
sudo wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null

sudo echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" | sudo tee -a /etc/apt/sources.list.d/trivy.list

sudo apt update -y

sudo apt-get install trivy -y

### Install Docker ###

sudo apt update -y
sudo apt -y install apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update -y
sudo apt -y install docker-ce docker-ce-cli containerd.io 
sudo snap install docker -y
sudo systemctl start docker
sudo systemctl enable --now docker
sudo usermod -aG docker jenkins

### Add PostgresSQL repository ###

sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'

sudo wget -qO- https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo tee /etc/apt/trusted.gpg.d/pgdg.asc &>/dev/null

sudo apt update -y

sudo apt-get -y install postgresql postgresql-contrib

sudo systemctl enable --now postgresql

# Create PostgreSQL user and database for SonarQube
echo "Creating PostgreSQL user and database for SonarQube..."
sudo -u postgres psql -c "CREATE USER sonar WITH PASSWORD 'sonar';"
sudo -u postgres psql -c "ALTER USER sonar WITH LOGIN;" # Ensure the user can log in
sudo -u postgres psql -c "CREATE DATABASE sonarqube WITH OWNER sonar ENCODING 'UTF8';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE sonarqube TO sonar;"
echo "PostgreSQL user and database created successfully."


### Add Adoptium repository ###

sudo wget -O - https://packages.adoptium.net/artifactory/api/gpg/key/public | tee /etc/apt/keyrings/adoptium.asc

sudo echo "deb [signed-by=/etc/apt/keyrings/adoptium.asc] https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | tee /etc/apt/sources.list.d/adoptium.list

sudo apt-get update -y

sudo echo "sonarqube - nofile 65536" >> /etc/security/limits.conf

sudo echo "sonarqube - nproc 4096" >> /etc/security/limits.conf

sudo echo "vm.max_map_count = 262144" >> /etc/sysctl.conf

### Sonarqube Installation ###
#### Download and Extract ###

sudo wget https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-9.9.0.65466.zip

sudo apt install unzip -y

sudo unzip sonarqube-9.9.0.65466.zip -d /opt

sudo mv /opt/sonarqube-9.9.0.65466 /opt/sonarqube

### Create a user and set permissions ###

sudo groupadd sonar

sudo useradd -c "user to run SonarQube" -d /opt/sonarqube -g sonar sonar

sudo chown sonar:sonar /opt/sonarqube -R

sudo echo "sonar.jdbc.username=sonar" >> /opt/sonarqube/conf/sonar.properties
sudo echo "sonar.jdbc.password=sonar" >> /opt/sonarqube/conf/sonar.properties
sudo echo "sonar.jdbc.url=jdbc:postgresql://localhost:5432/sonarqube" >> /opt/sonarqube/conf/sonar.properties


### Create service for Sonarqube ###

SERVICE_FILE="/etc/systemd/system/sonar.service"

# Create the service file
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=SonarQube service
After=syslog.target network.target

[Service]
Type=forking
ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
User=sonar
Group=sonar
Restart=always
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd to recognize the new service
sudo systemctl daemon-reload

sudo systemct start sonar.service

sudo systemct restart sonar.service

# Enable the service to start on boot
sudo systemctl enable sonar.service


