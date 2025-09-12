#!/bin/sh

set -ex

# Path to the Inno Setup executable
ISCC="/cygdrive/c/Program Files (x86)/Inno Setup 6/ISCC.exe"


# Resource paths
CYGWIN_EXTRAS=cygwin_extras

ENV_BUILD_DIR=envs/build-${GAP_VERSION}-x86_64
ENV_RUNTIME_DIR=envs/runtime-${GAP_VERSION}-x86_64

GAP_ROOT=/opt/gap-${GAP_VERSION}
GAP_ROOT_BUILD=${ENV_BUILD_DIR}${GAP_ROOT}
GAP_ROOT_RUNTIME=${ENV_RUNTIME_DIR}${GAP_ROOT}

# URL to download the Cygwin setup.exe
CYGWIN_MIRROR=http://mirrors.kernel.org/sourceware/cygwin/


# download
echo "::group::download"
mkdir -p download
(cd download && wget https://www.cygwin.com/setup-x86_64.exe)
chmod +x download/setup-x86_64.exe
echo "::endgroup::"

# cygwin setup
echo "::group::cygwin setup build"
mkdir -p envs
packages=$(for x in $(cat cygwin-gap-build.list) ; do printf "%s," $x ; done)
download/setup-x86_64.exe --site ${CYGWIN_MIRROR} \
    --root "$(cygpath -w -a envs/build-${GAP_VERSION}-x86_64)" \
    --packages $packages \
    --arch x86_64 --no-admin --no-shortcuts --quiet-mode

# Install symlinks for CCACHE
if [ -x envs/build-${GAP_VERSION}-x86_64/usr/bin/ccache ]; then
    ln -s /usr/bin/ccache envs/build-${GAP_VERSION}-x86_64/usr/local/bin/gcc
    ln -s /usr/bin/ccache envs/build-${GAP_VERSION}-x86_64/usr/local/bin/g++
fi
# A bit of cleanup
rm -f envs/build-${GAP_VERSION}-x86_64/Cygwin*.{bat,ico}
echo "::endgroup::"


# cygwin setup
echo "::group::cygwin setup runtime"
mkdir -p envs
packages=$(for x in $(cat cygwin-gap-runtime.list) ; do printf "%s," $x ; done)
download/setup-x86_64.exe --site ${CYGWIN_MIRROR} \
    --root "$(cygpath -w -a envs/runtime-${GAP_VERSION}-x86_64)" \
    --packages $packages \
    --arch x86_64 --no-admin --no-shortcuts --quiet-mode

# Install symlinks for CCACHE
if [ -x envs/runtime-${GAP_VERSION}-x86_64/usr/bin/ccache ]; then
    ln -s /usr/bin/ccache envs/runtime-${GAP_VERSION}-x86_64/usr/local/bin/gcc
    ln -s /usr/bin/ccache envs/runtime-${GAP_VERSION}-x86_64/usr/local/bin/g++
fi
# A bit of cleanup
rm -f envs/runtime-${GAP_VERSION}-x86_64/Cygwin*.{bat,ico}
echo "::endgroup::"


echo "::group::get-gap"
mkdir -p $(dirname ${GAP_ROOT_BUILD})
mv ../gap-${GAP_VERSION} ${GAP_ROOT_BUILD};
echo "::endgroup::"

echo "::group::configure"
tools/subcyg "${ENV_BUILD_DIR}" "cd ${GAP_ROOT} && ./configure"
echo "::endgroup::"

echo "::group::make"
tools/subcyg "${ENV_BUILD_DIR}" "cd ${GAP_ROOT} && make -j4"
echo "::endgroup::"

# get GAP packages (if not already present)
echo "::group::Get Packages"
tools/subcyg "${ENV_BUILD_DIR}" "cd ${GAP_ROOT} && make bootstrap-pkg-full"
tools/subcyg "${ENV_BUILD_DIR}" "cd ${GAP_ROOT} && rm -f packages.tar.gz"
echo "::endgroup::"

# build GAP packages
echo "::group::Build Packages"
tools/subcyg "${ENV_BUILD_DIR}" "cd ${GAP_ROOT}/pkg && (../bin/BuildPackages.sh --parallel || true)"
echo "::endgroup::"

# gap-prep-runtime
echo "::group::gap-prep-runtime"
mkdir -p $(dirname ${GAP_ROOT_RUNTIME})
cp -rp ${GAP_ROOT_BUILD} $(dirname ${GAP_ROOT_RUNTIME})
# Prepare / compactify runtime environment
tools/gap-prep-runtime "${GAP_ROOT_RUNTIME}" "${GAP_ROOT}"
echo "::endgroup::"


# gap-prep-runtime-extras
echo "::group::gap-prep-runtime-extras"
cp -r "${CYGWIN_EXTRAS}"/* "${ENV_RUNTIME_DIR}"
# Set the package download cache to something sensible; otherwise it
# will hard-code the package download cache used when building the
# environment in the installer, which is not what we want
# See https://github.com/sagemath/sage-windows/issues/24
sed -i '/^last-cache/{n;s|.*|\t/tmp|;}' "${ENV_RUNTIME_DIR}/etc/setup/setup.rc"
echo "::endgroup::"

# apt-cyg mirror
# Set apt-cyg to use a non-local mirror in the runtime env
echo "::group::apt-cyg mirror"
tools/subcyg "${ENV_RUNTIME_DIR}" "apt-cyg mirror ${CYGWIN_MIRROR}"
echo "::endgroup::"

# fixup-symlinks
echo "::group::fixup-symlinks"
tools/fixup-symlinks ${ENV_RUNTIME_DIR} > ${ENV_RUNTIME_DIR}/etc/symlinks.lst
echo "::endgroup::"

# ISCC
echo "::group::ISCC"
mkdir -p dist
#cd ${CUDIR}
"${ISCC}" /DGapVersion=${GAP_VERSION} /DGapArch=x86_64 /Q gap.iss
echo "::endgroup::"
