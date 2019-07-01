#!/usr/bin/env bash
set -e

log_msg () {
    echo
    echo "[`date`] - BUILD SCRIPT - $1"
}

BUILD_DIR="$(pwd)/build"
MINICONDA_HOME=$BUILD_DIR/miniconda3
log_msg "Initializing Miniconda3 environment: $MINICONDA_HOME"
curl -O https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh
sh Miniconda3-latest-Linux-x86_64.sh -b -p $MINICONDA_HOME
export PATH=$MINICONDA_HOME/bin/:$PATH

cd conda
export PYTORCH_FINAL_PACKAGE_DIR=$BUILD_DIR/artifacts
export DESIRED_PYTHON=3.7
export TORCH_CONDA_BUILD_FOLDER=pytorch-1.0.1
export PYTORCH_REPO=pytorch
export PYTORCH_BRANCH=v1.0.1
source scl_source enable devtoolset-7
conda install -y conda-build=3.16
./build_pytorch.sh 100 1.0.1 1 # cuda 10.0 pytorch 1.0.1 build_number 1

