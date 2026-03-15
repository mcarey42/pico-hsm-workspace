#!/bin/bash
#
TARGET=picohsm-runtime
if [ ! -d "$TARGET" ]; then
    mkdir $TARGET
else
    echo "$TARGET already exists, skipping creation"
fi

cd $TARGET

# Test that we have python3 and venv install and if not install it
if ! command -v python3 &> /dev/null
then
    echo "python3 could not be found, installing..."
    sudo apt update && sudo apt install -y python3
else
    echo "python3 is installed"
fi

if ! python3 -m venv --help &> /dev/null
then
    echo "python3-venv could not be found, installing..."
    sudo apt update && sudo apt install -y python3-venv
else
    echo "python3-venv is installed"
fi

# ensure we have git installed
if ! command -v git &> /dev/null
then
    echo "git could not be found, installing..."
    sudo apt update && sudo apt install -y git
else
    echo "git is installed"
fi

# now clone https://github.com/mcarey42/pypicokey and https://github.com/mcarey42/pypicohsm
if [ ! -d "pypicokey" ]; then
    git clone git@github.com:mcarey42/pypicokey.git
else
    echo "pypicokey already exists, pulling latest..."
    git -C pypicokey pull
fi

if [ ! -d "pypicohsm" ]; then
    git clone git@github.com:mcarey42/py-picohsm.git pypicohsm
else
    echo "pypicohsm already exists, pulling latest..."
    git -C pypicohsm pull
fi

# Ensure we've got https://github.com/mcarey42/pico-hsm.git
if [ ! -d "pico-hsm" ]; then
    git clone git@github.com:mcarey42/pico-hsm.git
else
    echo "pico-hsm already exists, pulling latest..."
    git -C pico-hsm pull
fi

# build the venv
python3 -m venv venv
source venv/bin/activate

# Install dependencies first so local packages can rely on them
cat >requirements.txt <<"EOF"
pycvc
cryptography
pyscard
pyusb
libusb
libusb_package
base58
EOF

pip3 install -r requirements.txt

# Install from local clones last so local fixes always take priority
pip3 install --force-reinstall --no-deps ./pypicokey
pip3 install --force-reinstall --no-deps ./pypicohsm

