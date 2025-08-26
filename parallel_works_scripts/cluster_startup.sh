#!/usr/bin/env bash
set -euo pipefail

# install dnf-plugins-core
sudo dnf -y install dnf-plugins-core >/dev/null 2>&1 || true

# install gh cli
if ! command -v gh >/dev/null 2>&1; then
    curl -fsSL https://cli.github.com/packages/rpm/gh-cli.repo | sudo tee /etc/yum.repos.d/github-cli.repo
    sudo dnf -y install gh
fi

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

## add /ngencerf-app/ngencerf-server/cli/bin to all user's PATH
echo 'export PATH="/ngencerf-app/ngencerf-server/cli/bin:$PATH"' | sudo tee /etc/profile.d/ngencerf-cli.sh
sudo chmod +x /etc/profile.d/ngencerf-cli.sh

echo "cluster startup complete"
