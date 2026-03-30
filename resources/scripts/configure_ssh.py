#!/usr/bin/python

"""
Configure ssh service
"""

import os
from subprocess import call

# Enable logging
from workspace_utils import get_secret, log

HOME = os.path.expanduser("~")
RESOURCE_FOLDER = os.getenv("RESOURCES_PATH")

# Export environment for ssh sessions
# call("printenv > $HOME/.ssh/environment", shell=True)
with open(HOME + "/.ssh/environment", "w") as fp:
    for env in os.environ:
        if env == "LS_COLORS":
            continue
        # ignore most variables that get set by kubernetes if enableServiceLinks is not disabled
        # https://github.com/kubernetes/kubernetes/pull/68754
        if "SERVICE_PORT" in env.upper():
            continue
        if "SERVICE_HOST" in env.upper():
            continue
        if "PORT" in env.upper() and "TCP" in env.upper():
            continue
        fp.write(env + "=" + str(os.environ[env]) + "\n")

### SSH Key Management
SSH_KEY_NAME = "id_ed25519"
ssh_path = os.path.join(HOME, ".ssh")
os.makedirs(ssh_path, exist_ok=True)

ssh_priv_key_file = os.path.join(ssh_path, SSH_KEY_NAME)
ssh_pub_key_file = ssh_priv_key_file + ".pub"

# Check if keys are provided via secrets
provided_priv_key = get_secret("SSH_PRIVATE_KEY")
provided_pub_key = get_secret("SSH_PUBLIC_KEY")

if provided_priv_key:
    log.info("Mounting SSH private key from secrets.")
    with open(ssh_priv_key_file, "w") as f:
        f.write(provided_priv_key)
    if provided_pub_key:
        with open(ssh_pub_key_file, "w") as f:
            f.write(provided_pub_key)
    else:
        log.info("Generating public key from provided private key.")
        call(f"ssh-keygen -y -f {ssh_priv_key_file} > {ssh_pub_key_file}", shell=True)
elif not os.path.isfile(ssh_priv_key_file):
    log.info("Creating new SSH Key (" + SSH_KEY_NAME + ")")
    call(
        f'ssh-keygen -f {ssh_priv_key_file} -t ed25519 -q -N "" > /dev/null', shell=True
    )

# Copy public key to resources for Nginx to serve
call(f"/bin/cp -rf {ssh_pub_key_file} /resources/public-key.pub", shell=True)

# Authorized Keys management
auth_keys_file = os.path.join(ssh_path, "authorized_keys")
call(f"touch {auth_keys_file}", shell=True)

provided_auth_keys = get_secret("AUTHORIZED_KEYS")
if provided_auth_keys:
    log.info("Appending authorized_keys from secrets.")
    with open(auth_keys_file, "a") as f:
        f.write("\n" + provided_auth_keys + "\n")

# Also auto-authorize the container's own key
call(f"echo '' >> {auth_keys_file}", shell=True)
call(
    'grep -qxF "$(cat {pub_key})" {auth_keys} || cat {pub_key} >> {auth_keys}'.format(
        pub_key=ssh_pub_key_file, auth_keys=auth_keys_file
    ),
    shell=True,
)

# Add identity to ssh agent -> e.g. can be used for git authorization
call(
    'eval "$(ssh-agent -s)" && ssh-add '
    + HOME
    + "/.ssh/"
    + SSH_KEY_NAME
    + " > /dev/null",
    shell=True,
)

# Fix permissions
# https://superuser.com/questions/215504/permissions-on-private-key-in-ssh-folder
# https://gist.github.com/grenade/6318301
# https://help.ubuntu.com/community/SSH/OpenSSH/Keys

call("chmod 700 ~/.ssh/", shell=True)
call("chmod 600 ~/.ssh/" + SSH_KEY_NAME, shell=True)
call("chmod 644 ~/.ssh/" + SSH_KEY_NAME + ".pub", shell=True)

# TODO Config backup does not work when setting these:
# call("chmod 644 ~/.ssh/authorized_keys", shell=True)
# call("chmod 644 ~/.ssh/known_hosts", shell=True)
# call("chmod 644 ~/.ssh/config", shell=True)
# call("chmod 700 ~/.ssh/", shell=True)
# call("chmod -R 600 ~/.ssh/", shell=True)
# call("chmod 644 ~/.ssh/authorized_keys", shell=True)
# call("chmod 644 ~/.ssh/known_hosts", shell=True)
# call("chmod 644 ~/.ssh/config", shell=True)
# call("chmod 644 ~/.ssh/" + SSH_KEY_NAME + ".pub", shell=True)
###
### Configure sshd_config
NB_USER = os.getenv("NB_USER", "root")
SSHD_CONFIG = "/etc/ssh/sshd_config"
if os.path.exists(SSHD_CONFIG):
    with open(SSHD_CONFIG, "r") as f:
        content = f.read()
    content = content.replace("{NB_USER}", NB_USER)
    with open(SSHD_CONFIG, "w") as f:
        f.write(content)

# Ensure SSH host keys are generated and have correct permissions if missing
if not os.path.exists("/etc/ssh/ssh_host_ed25519_key"):
    log.info("Generating SSH host keys...")
    call("ssh-keygen -A", shell=True)

# Fix host key permissions for non-root user
call(
    "chown -R {user}:{gid} /etc/ssh/".format(
        user=NB_USER, gid=os.getenv("NB_GID", "100")
    ),
    shell=True,
)
call("chmod 600 /etc/ssh/ssh_host_*_key", shell=True)
