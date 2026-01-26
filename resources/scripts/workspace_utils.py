import os
import sys

from loguru import logger


def setup_logging():
    # Remove default handler
    logger.remove()

    # Check if JSON logging is enabled
    use_json = os.getenv("WORKSPACE_LOG_JSON", "false").lower() == "true"
    log_level = os.getenv("WORKSPACE_LOG_LEVEL", "INFO").upper()

    if use_json:
        logger.add(sys.stdout, format="{message}", serialize=True, level=log_level)
    else:
        format = (
            "<green>{time:YYYY-MM-DD HH:mm:ss}</green> | "
            "<level>{level: <8}</level> | <cyan>{name}</cyan>:"
            "<cyan>{function}</cyan>:<cyan>{line}</cyan> - <level>{message}</level>"
        )
        logger.add(sys.stdout, format=format, level=log_level)

    return logger


# Initialize default logger
log = setup_logging()


def get_secret(name, default=None):
    """
    Get a secret from /run/secrets (Kubernetes/Docker Secret) or fallback to Environment Variable.
    """
    secret_path = os.path.join(
        os.getenv("WORKSPACE_SECRETS_PATH", "/run/secrets"), name
    )
    if os.path.exists(secret_path):
        try:
            with open(secret_path, "r") as f:
                log.info(f"Using secret from file: {name}")
                return f.read().strip()
        except Exception:
            log.error(f"Failed to read secret file: {name}")

    return os.getenv(name, default)
