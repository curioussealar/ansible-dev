FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    sudo \
    python3 \
    python3-pip \
    curl \
    net-tools \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

# Create ansible user with passwordless sudo
RUN useradd -m -s /bin/bash ansible \
    && echo "ansible ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/ansible \
    && chmod 0440 /etc/sudoers.d/ansible

# Set up SSH authorized_keys from build arg (inject public key at build time)
# The key can also be added via the Semaphore Key Store at runtime.
ARG ANSIBLE_PUBKEY=""
RUN mkdir -p /home/ansible/.ssh \
    && chmod 700 /home/ansible/.ssh \
    && if [ -n "$ANSIBLE_PUBKEY" ]; then echo "$ANSIBLE_PUBKEY" > /home/ansible/.ssh/authorized_keys; fi \
    && touch /home/ansible/.ssh/authorized_keys \
    && chmod 600 /home/ansible/.ssh/authorized_keys \
    && chown -R ansible:ansible /home/ansible/.ssh

# sshd configuration — key auth only, no root login
RUN mkdir -p /var/run/sshd \
    && sed -i \
        -e 's/#PasswordAuthentication yes/PasswordAuthentication no/' \
        -e 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' \
        -e 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' \
        /etc/ssh/sshd_config \
    && ssh-keygen -A

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D", "-e"]
