
pushd .
cd %1
mkdir build
cd build
cmake %*
popd
