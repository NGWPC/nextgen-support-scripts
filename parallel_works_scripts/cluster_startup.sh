#!/usr/bin/env bash
set -euo pipefail

# install yum-utils
sudo dnf -y install yum-utils >/dev/null 2>&1 || true

# install Docker
if ! command -v docker >/dev/null 2>&1; then
    if [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
        sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    fi
    sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

# enable Docker on boot
sudo systemctl enable --now docker

# install mountpoint-s3
if ! command -v mount-s3 >/dev/null 2>&1; then
    sudo dnf -y install https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.rpm
fi

# install dnf packages
if [ -n "${DNF_PACKAGES_EXTRA:-}" ]; then
    sudo dnf -y install ${DNF_PACKAGES_EXTRA}
fi

# install python packages
if [ -n "${PY_PIP_PKGS:-}" ]; then
    sudo dnf -y install python3-pip
    sudo python3 -m pip install --upgrade pip
    sudo python3 -m pip install ${PY_PIP_PKGS}
fi

# ensure a sudoers drop-in exists that grants passwordless sudo to all users in the wheel group
if [ ! -f /etc/sudoers.d/99-wheel-nopw ]; then
    echo '%wheel ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/99-wheel-nopw >/dev/null
    sudo chmod 440 /etc/sudoers.d/99-wheel-nopw
fi

# add users to docker and wheel groups
if [ -n "${ADD_USERS:-}" ]; then
    if getent group docker >/dev/null 2>&1; then
        for u in ${ADD_USERS}; do
            id -u "$u" >/dev/null 2>&1 && sudo usermod -aG docker "$u" || echo "warn: user $u not found"
        done
    else
        echo "warn: docker group not found; skipping docker memberships"
    fi
    for u in ${ADD_USERS}; do
        id -u "$u" >/dev/null 2>&1 && sudo usermod -aG wheel "$u" || echo "warn: user $u not found"
    done
fi

echo "cluster startup complete"
