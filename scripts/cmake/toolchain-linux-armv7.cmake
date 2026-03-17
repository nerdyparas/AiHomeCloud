# CMake toolchain file for cross-compiling to Linux armv7 (hard-float)
# on an x86_64 Ubuntu host using the gcc-arm-linux-gnueabihf toolchain.
#
# Prerequisites (installed by the CI workflow):
#   sudo dpkg --add-architecture armhf
#   sudo apt-get install gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf \
#                        libssl-dev:armhf zlib1g-dev:armhf

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR armv7l)

set(CROSS_TRIPLE arm-linux-gnueabihf)

set(CMAKE_C_COMPILER   ${CROSS_TRIPLE}-gcc)
set(CMAKE_CXX_COMPILER ${CROSS_TRIPLE}-g++)

# Ubuntu multiarch installs foreign-arch libraries under /usr/lib/<triple>/
# and arch-specific headers under /usr/include/<triple>/.
set(OPENSSL_ROOT_DIR        /usr/lib/${CROSS_TRIPLE})
set(OPENSSL_INCLUDE_DIR     /usr/include/${CROSS_TRIPLE})
set(OPENSSL_SSL_LIBRARY     /usr/lib/${CROSS_TRIPLE}/libssl.so)
set(OPENSSL_CRYPTO_LIBRARY  /usr/lib/${CROSS_TRIPLE}/libcrypto.so)

set(ZLIB_LIBRARY     /usr/lib/${CROSS_TRIPLE}/libz.so)
set(ZLIB_INCLUDE_DIR /usr/include)

# Direct CMake to search only in the foreign sysroot for libraries/headers,
# but use the host filesystem for build tools (programs).
set(CMAKE_FIND_ROOT_PATH
    /usr/${CROSS_TRIPLE}
    /usr/lib/${CROSS_TRIPLE}
)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
