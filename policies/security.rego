package workspace.security

# Deny if USER is root (UID 0)
deny[msg] {
    # Check for root user or missing USER instruction
    not input.config.User
    msg := "Security Violation: Docker image must specify a USER. Defaulting to root is prohibited."
}

deny[msg] {
    input.config.User == "root"
    msg := "Security Violation: Docker image must not run as root user."
}

deny[msg] {
    input.config.User == "0"
    msg := "Security Violation: Docker image must not run as UID 0."
}

# Ensure critical labels are present
required_labels := {"workspace.version", "workspace.flavor", "org.opencontainers.image.vendor"}

deny[msg] {
    some label
    required_labels[label]
    not input.config.Labels[label]
    msg := sprintf("Governance Violation: Missing required label '%s'", [label])
}
