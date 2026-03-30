# Base Jupyter configuration
# This file contains the base configuration for Jupyter

import os
from jupyter_core.paths import jupyter_data_dir

# Base configuration
c.NotebookApp.allow_origin = '*'  # For development only
c.NotebookApp.allow_remote_access = True
c.NotebookApp.quit_button = True

# File save hooks
def scrub_output_pre_save(model, **kwargs):
    """Scrub output before saving notebooks"""
    if model['type'] != 'notebook':
        return
    if model['content'] and model['content']['metadata']:
        # Clear metadata and outputs
        for cell in model['content'].get('cells', []):
            if cell['cell_type'] == 'code':
                cell['execution_count'] = None
                cell['outputs'] = []

# Configure pre-save hook if enabled
if os.getenv('JUPYTER_SCRUB_OUTPUT', 'true').lower() == 'true':
    c.FileContentsManager.pre_save_hook = scrub_output_pre_save

# Configure extensions
c.NotebookApp.nbserver_extensions = {
    'jupyter_tooling': True,
}
