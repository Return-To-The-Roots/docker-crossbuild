FROM buildpack-deps:jessie-curl

# based on multiarch/crossbuild

RUN sed -i s/httpredir/ftp.de/g /etc/apt/sources.list

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get clean \
    && apt-get update \
    && apt-get dist-upgrade \
    && apt-get clean

# Install deps
RUN set -x ; \
    echo deb http://emdebian.org/tools/debian/ jessie main > /etc/apt/sources.list.d/emdebian.list \
    && curl -sL http://emdebian.org/tools/debian/emdebian-toolchain-archive.key | apt-key add - \
    && dpkg --add-architecture i386 \
    && apt-get update
RUN apt-get install -y -q \
        bc \
        binfmt-support \
        binutils-multiarch \
        binutils-multiarch-dev \
        build-essential \
        clang \
        curl \
        devscripts \
        gdb \
        git-core \
        llvm \
        mercurial \
        multistrap \
        patch \
        python-software-properties \
        software-properties-common \
        subversion \
        wget \
        xz-utils \
        cmake \
    && apt-get clean

# FIXME: install gcc-multilib

# Install Windows cross-tools
RUN apt-get install -y mingw-w64 \
    && apt-get clean


# Install OSx cross-tools
ENV OSXCROSS_REVISION=bdee5c1d000bd9fd560b1061dca9677f04b9ec75 \
    DARWIN_SDK_VERSION=10.11 \
    DARWIN_VERSION=15

# ENV DARWIN_SDK_URL=https://www.dropbox.com/s/yfbesd249w10lpc/MacOSX${DARWIN_SDK_VERSION}.sdk.tar.xz
ENV DARWIN_SDK_URL=https://github.com/apriorit/osxcross-sdks/raw/master/MacOSX{DARWIN_SDK_VERSION}.sdk.tar.xz

ADD tarballs /tarballs

RUN mkdir -p "/tmp/osxcross" \
    && cd "/tmp/osxcross" \
    && curl -sLo osxcross.tar.gz "https://codeload.github.com/tpoechtrager/osxcross/tar.gz/${OSXCROSS_REVISION}" \
    && tar --strip=1 -xzf osxcross.tar.gz \
    && rm -f osxcross.tar.gz \
    && mkdir -p tarballs \
    && if [ -f /tarballs/MacOSX${DARWIN_SDK_VERSION}.sdk.tar.xz ] ; then \
        echo "Using SDK for ${DARWIN_SDK_VERSION} from /tarballs" \
        && ln -s /tarballs/* tarballs/ ; \
    else \
        echo "Downloading SDK for ${DARWIN_SDK_VERSION} from ${DARWIN_SDK_URL}" \
        && curl -sLo tarballs/MacOSX${DARWIN_SDK_VERSION}.sdk.tar.xz "${DARWIN_SDK_URL}" ; \
    fi \
    && tools/get_dependencies.sh \
    && yes "" | SDK_VERSION="${DARWIN_SDK_VERSION}" OSX_VERSION_MIN=10.5 ./build.sh \
    && mv target /usr/osxcross \
    && cd /usr/osxcross \
    && rm -rf /tmp/osxcross \
    && rm -rf /usr/osxcross/SDK/MacOSX10.11.sdk/usr/share/man

# Create symlinks for triples and set default CROSS_TRIPLE
ENV LINUX_TRIPLES= \
    DARWIN_TRIPLES=x86_64h-apple-darwin${DARWIN_VERSION},x86_64-apple-darwin${DARWIN_VERSION},i386-apple-darwin${DARWIN_VERSION} \
    WINDOWS_TRIPLES=i686-w64-mingw32,x86_64-w64-mingw32 \
    CROSS_TRIPLE=x86_64-linux-gnu

RUN find / -name osxcross-wrapper && ls -la /usr/osxcross

COPY ./assets/osxcross-wrapper /usr/bin/osxcross-wrapper

RUN set -x ; \
    mkdir -p /usr/x86_64-linux-gnu && \
    for triple in $(echo ${LINUX_TRIPLES} | tr "," " "); do \
        for bin in /etc/alternatives/$triple-* /usr/bin/$triple-*; do \
            if [ ! -f /usr/$triple/bin/$(basename $bin | sed "s/$triple-//") ]; then \
                ln -s $bin /usr/$triple/bin/$(basename $bin | sed "s/$triple-//"); \
            fi; \
        done; \
    done && \
    for triple in $(echo ${DARWIN_TRIPLES} | tr "," " "); do \
        mkdir -p /usr/$triple/bin; \
        for bin in /usr/osxcross/bin/$triple-*; do \
            ln -s /usr/bin/osxcross-wrapper /usr/$triple/bin/$(basename $bin | sed "s/$triple-//"); \
        done && \
        rm -f /usr/$triple/bin/clang*; \
        ln -s cc /usr/$triple/bin/gcc; \
        ln -s /usr/osxcross/SDK/MacOSX${DARWIN_SDK_VERSION}.sdk/usr /usr/x86_64-linux-gnu/$triple ; \
    done; \
    for triple in $(echo ${WINDOWS_TRIPLES} | tr "," " "); do \
        mkdir -p /usr/$triple/bin; \
        for bin in /etc/alternatives/$triple-* /usr/bin/$triple-*; do \
            if [ ! -f /usr/$triple/bin/$(basename $bin | sed "s/$triple-//") ]; then \
                ln -s $bin /usr/$triple/bin/$(basename $bin | sed "s/$triple-//"); \
            fi; \
        done; \
        ln -s gcc /usr/$triple/bin/cc; \
        ln -s /usr/$triple /usr/x86_64-linux-gnu/$triple ; \
    done
    && ln -s /usr/osxcross/tools/osxcross-macports /usr/bin/macports
    
# we need to use default clang binary to avoid a bug in osxcross that recursively call himself
# with more and more parameters

# Image metadata
ENTRYPOINT ["/usr/bin/crossbuild"]
CMD ["/bin/bash"]
WORKDIR /workdir
COPY ./assets/crossbuild /usr/bin/crossbuild

# install dependencies for return-to-the-roots
RUN apt-get install -y -q \
        libboost1.55-all-dev \
        g++-4.8 \
        cmake \
        libsdl1.2-dev \
        libsdl-mixer1.2-dev \
        libcurl4-openssl-dev \
        libbz2-dev \
        libminiupnpc-dev \
        liblua5.2-dev \
        ccache \
    && apt-get clean

ENV CCACHE_DIR=/workdir/.ccache
