# Jupyter Security Configuration
# This file contains security-related configuration for Jupyter

import os
import ssl

# SSL/TLS configuration
ssl_enabled = os.getenv('JUPYTER_SSL_ENABLED', 'false').lower() == 'true'
if ssl_enabled:
    cert_file = os.getenv('JUPYTER_SSL_CERT', '/etc/ssl/jupyter.crt')
    key_file = os.getenv('JUPYTER_SSL_KEY', '/etc/ssl/jupyter.key')
    
    if os.path.exists(cert_file) and os.path.exists(key_file):
        c.NotebookApp.certfile = cert_file
        c.NotebookApp.keyfile = key_file
        c.NotebookApp.ssl_version = ssl.PROTOCOL_TLSv1_2
    else:
        print(f"Warning: SSL certificate or key not found at {cert_file} or {key_file}")

# Security headers
c.NotebookApp.tornado_settings = {
    'headers': {
        'Content-Security-Policy': "default-src 'self' 'unsafe-inline' 'unsafe-eval' data: blob: https:;",
        'X-Content-Type-Options': 'nosniff',
        'X-Frame-Options': 'SAMEORIGIN',
        'X-XSS-Protection': '1; mode=block',
    }
}

# Authentication
if 'JUPYTER_PASSWORD' in os.environ:
    from jupyter_server.auth import passwd
    c.NotebookApp.password = passwd(os.environ['JUPYTER_PASSWORD'])
    del os.environ['JUPYTER_PASSWORD']

# Disable token-based authentication if using password
if c.NotebookApp.password:
    c.NotebookApp.token = ''

# Rate limiting
c.NotebookApp.rate_limit_window = 3  # seconds
c.NotebookApp.rate_limit_interval = 1  # seconds
c.NotebookApp.rate_limit_requests = 100  # requests per window
