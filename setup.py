#!/usr/bin/env python3

from setuptools import setup, find_packages
import os

# Read package version from __init__.py
def get_version():
    init_path = os.path.join('resources', '__init__.py')
    with open(init_path, 'r') as f:
        for line in f:
            if line.startswith('__version__'):
                return line.split('=')[1].strip().strip('"\'')
    return '0.1.0'

# Read long description from README.md
def get_long_description():
    try:
        with open('README.md', 'r', encoding='utf-8') as f:
            return f.read()
    except FileNotFoundError:
        return ""

# Core dependencies
install_requires = [
    "numpy>=1.21.0",
    "pandas>=1.3.0",
    "matplotlib>=3.4.0",
    "scikit-learn>=1.0.0",
    "jupyter>=1.0.0",
    "tqdm>=4.62.0",
    "pyyaml>=6.0",
    "python-dotenv>=0.19.0",
    "loguru>=0.6.0"
]

# Development dependencies
extras_require = {
    'dev': [
        'pytest>=7.0.0',
        'pytest-cov>=3.0.0',
        'black>=22.0.0',
        'isort>=5.10.0',
        'mypy>=0.910',
        'flake8>=4.0.0',
        'pre-commit>=2.15.0',
        'jupyterlab>=3.0.0',
        'ipykernel>=6.0.0',
        'pylint>=2.15.0',
        'pytest-mock>=3.10.0',
    ],
    'ml': [
        'transformers>=4.15.0',
        'datasets>=2.0.0',
        'evaluate>=0.3.0',
        'optuna>=3.0.0',
        'mlflow>=1.25.0',
    ],
    'dl': [
        'torch>=1.10.0',
        'torchvision>=0.13.0',
        'torchaudio>=0.12.0',
        'pytorch-lightning>=1.7.0',
        'tensorboard>=2.10.0',
    ],
    'data': [
        'dask>=2021.6.0',
        'dask-ml>=1.9.0',
        'polars>=0.13.0',
        'vaex>=4.12.0',
        'modin[all]>=0.15.0',
    ]
}

# Package data
package_data = {
    'resources': ['*.yaml', '*.yml', '*.json', '*.txt', '*.md'],
    'deployment': ['*.yaml', '*.yml', '*.json', '*.txt', '*.md'],
}

setup(
    name="ml-space",
    version=get_version(),
    description="ML Workspace with pre-configured libraries for machine learning",
    long_description=get_long_description(),
    long_description_content_type='text/markdown',
    author="ML Space Team",
    author_email="team@mlspace.ai",
    url="https://github.com/khulnasoft-bot/ml-space",
    packages=find_packages(include=['resources', 'deployment', 'resources.*', 'deployment.*']),
    python_requires=">=3.8,<3.13",
    install_requires=install_requires,
    extras_require=extras_require,
    package_data=package_data,
    include_package_data=True,
    classifiers=[
        'Development Status :: 3 - Alpha',
        'Intended Audience :: Developers',
        'Intended Audience :: Science/Research',
        'License :: OSI Approved :: MIT License',
        'Programming Language :: Python :: 3',
        'Programming Language :: Python :: 3.8',
        'Programming Language :: Python :: 3.9',
        'Programming Language :: Python :: 3.10',
        'Programming Language :: Python :: 3.11',
        'Topic :: Scientific/Engineering',
        'Topic :: Scientific/Engineering :: Artificial Intelligence',
    ],
    entry_points={
        'console_scripts': [
            'mlspace=resources.cli:main',
        ],
    },
)
