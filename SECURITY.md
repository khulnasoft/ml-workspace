# Security Hardening Guide: ml-workspace

This platform has been stabilized according to modern enterprise security standards. This guide explains the security features and how to leverage them.

## 🛡️ Core Security Architecture

### 1. Non-Root Execution
The platform runs as the `khulnasoft` user (UID 1000, GID 100) by default. This follows the **Principle of Least Privilege** and mitigates container breakout risks.

### 2. Zero-Trust Internal Networking
Every workspace generates a 32-character `WORKSPACE_INTERNAL_AUTH_TOKEN` on startup. 
*   **VS Code Server** and **JupyterLab** require this token for authentication.
*   The **Nginx Proxy** handles token injection automatically for the primary user.
*   Internal services are further isolated using **Unix Domain Sockets (UDS)** for VS Code, removing local port exposure.

### 3. Supply Chain Governance
The build pipeline includes automated security gates:
*   **SBOM Generation**: Use `make sbom` to generate a full inventory of packages.
*   **Vulnerability Scanning**: Use `make scan` to audit the image with Trivy (fails on High/Critical).
*   **Policy-as-Code**: Use `make audit` to validate image configuration with Open Policy Agent (OPA).

---

## 🔒 Runtime Hardening (Phase 5)

To achieve maximum isolation, we provide custom kernel-level profiles.

### Seccomp (System Call Filtering)
The `runtime-security/seccomp.json` profile restricts the syscalls the container can make to the Linux kernel. It explicitly blocks dangerous actions like `mount`, `reboot`, and `pivot_root`.

**How to run with Seccomp:**
```bash
make run-hardened
```

### AppArmor (Path-based Mandatory Access Control)
The `runtime-security/apparmor-profile` provides granular filesystem and capability restrictions.

**How to apply:**
1.  Load the profile on your host: `sudo apparmor_parser -r -W runtime-security/apparmor-profile`
2.  Run the container with: `--security-opt apparmor=ml-workspace-hardened`

---

## 🔑 Enterprise Integration

### Secrets Management
The platform prioritizes secrets mounted at `/run/secrets/`. You can provide the following:
*   **SSH_PRIVATE_KEY**: Mounted as the primary identity.
*   **AUTHORIZED_KEYS**: Appended to the workspace user's authorized list.
*   **WORKSPACE_INTERNAL_AUTH_TOKEN**: Fixed token for multi-tenant environments.

### Structured Logging
Enable JSON logging for ELK/Splunk integration:
```bash
docker run -e WORKSPACE_LOG_JSON=true ...
```
