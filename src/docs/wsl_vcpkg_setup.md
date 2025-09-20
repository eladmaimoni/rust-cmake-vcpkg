

1. Install build essentials
```
sudo apt-get update -y && sudo apt-get upgrade -y
sudo apt-get install build-essential software-properties-common curl unzip tar pkg-config -y
``

2. clone vcpkg and run the installer

```
  git clone https://github.com/microsoft/vcpkg.git
  cd vcpkg
  ./bootstrap-vcpkg.sh
```

3. add environment variables to ~/.bashrc

```
export PATH="~/workspace/vcpkg:$PATH"
export VCPKG_ROOT=~/workspace/vcpkg
export VCPKG_DEFAULT_BINARY_CACHE=~/workspace/VCPKG_BINARY_CACHE
```