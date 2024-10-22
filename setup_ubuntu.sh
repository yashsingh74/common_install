#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
set -o xtrace

# Dependency file path
DEPENDENCY_FILE="dependency_versions.txt"
source $DEPENDENCY_FILE

# Function to parse the dependency file and return version
get_version_from_file() {
    local pkg_name="$1"
    local version="$(grep "^${pkg_name}=" "${DEPENDENCY_FILE}" | cut -d'=' -f2)"
    echo "${version}"
}


# Function to check if the software is installed and install it
check_and_install() {
    local pkg_name="$1"
    local install_cmd_latest="$2"
    local install_cmd_specific="$3"
    local version_cmd="$4"

    local version=$(get_version_from_file "${pkg_name}")

    if command -v $pkg_name &>/dev/null; then
        echo "$pkg_name is already installed."
        $version_cmd
    else
        echo "$pkg_name is not installed. Version specified: ${version}"
        if [ -z "${version}" ]; then
            echo "Installing the latest version of ${pkg_name}..."
        else
            echo "Installing version ${version} of ${pkg_name}..."
            install_cmd="${install_cmd_specific//\{\{version\}\}/$version}"
            eval "${install_cmd}"
        fi
        if [ $? -eq 0 ]; then
            echo "${pkg_name} installation successful."
            $version_cmd
        else
            echo "Failed to install ${pkg_name}."
        fi
    fi
}

# Docker installation steps
install_docker() {
    local version=$(get_version_from_file "docker")
    # Uninstall any old Docker versions
    sudo apt-get remove -y docker docker.io containerd runc
    # Install necessary packages for setting up the repository
    sudo apt-get update
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    # Add Docker’s official GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    # Set up the Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    # Install Docker either with a specific version or the latest
    if [ -z "$version" ]; then
        echo "Installing the latest version of Docker..."
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        echo "Installing Docker version $version..."
        sudo apt-get install -y docker-ce="$version" docker-ce-cli="$version" containerd.io docker-buildx-plugin docker-compose-plugin
    fi
    # Enable and start Docker service
    sudo systemctl enable docker
    sudo systemctl start docker

    echo "Adding the current user to the docker group..."
    sudo groupadd docker  # Create the docker group if it doesn't exist
    sudo usermod -aG docker $USER
    # Inform user to log out and log back in
    echo "Please log out and log back in to apply the group change, or run 'newgrp docker' to switch the group immediately."
    # Verify Docker installation
    docker --version
}

# Function to install Zsh from source using curl
install_zsh() {
    local version=$(get_version_from_file "zsh")
    sudo apt-get install -y git build-essential autoconf yodl
    # Fetch Zsh source code
    if [ -z "$version" ]; then
        # Install the latest version from GitHub
        echo "Installing the latest version of Zsh from GitHub..."
        git clone https://github.com/zsh-users/zsh.git
        cd zsh
        ./Util/bootstrap
        ./configure
        make -j$(nproc)
        sudo make install
        cd ..
        rm -rf zsh
    else
        # Install specific version from GitHub
        echo "Installing Zsh version $version from GitHub..."
        git clone https://github.com/zsh-users/zsh.git
        cd zsh
        git checkout "zsh-$version"
        ./Util/bootstrap
        ./configure
        make -j$(nproc)
        sudo make install
        cd ..
        rm -rf zsh
    fi
    # Make Zsh the default shell
    echo "Changing the default shell to Zsh..."
    chsh -s $(which zsh)
    # Verify Zsh installation
    zsh --version
}

# Function to install jq
install_jq() {
    local version=$(get_version_from_file "jq")
    # Update package list
    sudo apt-get update
    if [ -z "$version" ]; then
        # Install the latest version of jq
        echo "Installing the latest version of jq..."
        sudo apt-get install -y jq
    else
        # Install specific version of jq
        echo "Installing jq version $version..."
        sudo apt-get install -y jq="$version"
    fi
    # Verify jq installation
    jq --version
}

# update and upgrade all the default_packages
sudo apt-get update -y && sudo apt-get upgrade -y

# Install Python
check_and_install "python3" \
    "sudo apt install -y python3 python3-pip" \
    "sudo apt install -y python3={{version}} python3-pip" \
    "python3 --version"

# Install Go
check_and_install "go" \
    "curl -LO https://golang.org/dl/go1.23.2.linux-amd64.tar.gz && sudo tar -C /usr/local -xzf go1.20.5.linux-amd64.tar.gz && export PATH=$PATH:/usr/local/go/bin && rm -rf go{{version}}.linux-amd64.tar.gz" \
    "curl -LO https://golang.org/dl/go{{version}}.linux-amd64.tar.gz && sudo tar -C /usr/local -xzf go{{version}}.linux-amd64.tar.gz && export PATH=$PATH:/usr/local/go/bin && rm -rf go{{version}}.linux-amd64.tar.gz" \
    "go version"

# Install kubectl
check_and_install "kubectl" \
    "sudo apt install -y kubectl" \
    "curl -LO https://dl.k8s.io/release/v{{version}}/bin/linux/amd64/kubectl && sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl" \
    "kubectl version --client"

# Install tmux
check_and_install "tmux" \
    "sudo apt install -y tmux" \
    "sudo apt install -y tmux={{version}}" \
    "tmux -V"

# Install kind (Kubernetes in Docker)
check_and_install "kind" \
    "curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64 && sudo chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind" \
    "curl -Lo ./kind https://kind.sigs.k8s.io/dl/v{{version}}/kind-linux-amd64 && sudo chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind" \
    "kind --version"

# Install Docker
install_docker

# Install Zsh
# install_zsh

# Install Git
check_and_install "git" \
    "sudo apt install -y git" \
    "sudo apt install -y git={{version}}" \
    "git --version"

# Install jq
install_jq

echo "Installation process completed."
