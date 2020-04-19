# This Dockerfile builds an image with Ardour and some other goodies installed.
# Jack is omitted on purpose: ALSA gives better latency when playing on a MIDI keyboard
# and feeding MIDI to synth plugins.


# Pull the base image and install the dependencies per the source package;
# this is a good approximation of what is needed.

from ubuntu:18.04 as base-ubuntu

run cp /etc/apt/sources.list /etc/apt/sources.list~
run sed -Ei 's/^# deb-src /deb-src /' /etc/apt/sources.list
run apt -y update
run apt install -y --no-install-recommends software-properties-common apt-utils
run add-apt-repository ppa:apt-fast/stable
run apt -y update
run env DEBIAN_FRONTEND=noninteractive apt-get -y install apt-fast
run echo debconf apt-fast/maxdownloads string 16 | debconf-set-selections
run echo debconf apt-fast/dlflag boolean true | debconf-set-selections
run echo debconf apt-fast/aptmanager string apt-get | debconf-set-selections

run echo "MIRRORS=( 'http://archive.ubuntu.com/ubuntu, http://de.archive.ubuntu.com/ubuntu, http://ftp.halifax.rwth-aachen.de/ubuntu, http://ftp.uni-kl.de/pub/linux/ubuntu, http://mirror.informatik.uni-mannheim.de/pub/linux/distributions/ubuntu/' )" >> /etc/apt-fast.conf

run apt-fast -y update && apt-fast -y upgrade

# Based on the dependencies, butld Ardour proper. In the end create a tar binary bundle.

from base-ubuntu as ardour

run apt-fast install -y libboost-dev libasound2-dev libglibmm-2.4-dev libsndfile1-dev
run apt-fast install -y libcurl4-gnutls-dev libarchive-dev liblo-dev libtag-extras-dev
run apt-fast install -y vamp-plugin-sdk librubberband-dev libudev-dev libnfft3-dev
run apt-fast install -y libaubio-dev libxml2-dev libusb-1.0-0-dev
run apt-fast install -y libpangomm-1.4-dev liblrdf0-dev libsamplerate0-dev
run apt-fast install -y libserd-dev libsord-dev libsratom-dev liblilv-dev
run apt-fast install -y libgtkmm-2.4-dev libsuil-dev

run apt-fast install -y wget curl

run mkdir /build-ardour
workdir /build-ardour
run wget http://archive.ubuntu.com/ubuntu/pool/universe/a/ardour/ardour_5.12.0-3.dsc
run wget http://archive.ubuntu.com/ubuntu/pool/universe/a/ardour/ardour_5.12.0.orig.tar.bz2
run wget http://archive.ubuntu.com/ubuntu/pool/universe/a/ardour/ardour_5.12.0-3.debian.tar.xz

run dpkg-source -x ardour_5.12.0-3.dsc

workdir /tmp
run curl https://waf.io/waf-1.6.11.tar.bz2 | tar xj
workdir waf-1.6.11

run patch -p1 < /build-ardour/ardour-5.12.0/tools/waflib.patch
run ./waf-light -v --make-waf --tools=misc,doxygen,/build-ardour/ardour-5.12.0/tools/autowaf.py --prelude=''
run cp ./waf /build-ardour/ardour-5.12.0/waf

workdir /build-ardour/ardour-5.12.0
run ./waf configure --no-phone-home --with-backend=alsa
run ./waf build -j4
run ./waf install
run apt-fast install -y chrpath rsync unzip
run ln -sf /bin/false /usr/bin/curl
workdir tools/linux_packaging
run ./build --public --strip some
run ./package --public --singlearch


# Build QMidiArp LV2 plugins only

from  base-ubuntu as qmidiarp

run apt-fast install -y git autoconf automake libtool libasound2-dev qt5-default
run apt-fast install -y g++ pkg-config lv2-dev
run mkdir /build-qmidiarp
workdir /build-qmidiarp
run git clone https://github.com/emuse/qmidiarp.git
workdir qmidiarp
run autoreconf -i
run ./configure --disable-buildapp --prefix=/usr
run make
run make install
run mkdir /install-qmidiarp
workdir /usr/lib
run tar czvf /install-qmidiarp/qmidiarp-lv2.tar.gz ./lv2
workdir /install-qmidiarp
run tar tzvf qmidiarp-lv2.tar.gz

# Build Guitarix proper w/o standalone app

from ardour as guitarix-proper
run apt-fast install -y git
run mkdir /build-guitarix-proper
workdir /build-guitarix-proper
run git clone https://github.com/moddevices/guitarix.git
workdir guitarix/trunk
run apt-fast install -y intltool libzita-convolver-dev libzita-resampler-dev
run apt-fast install -y libeigen3-dev
run ./waf configure --no-standalone --mod-lv2 --prefix=/usr
run ./waf build
run ./waf install

# Build Guitarix extra LV2

from ardour as guitarix

run apt-fast install -y git
run mkdir /build-guitarix
workdir /build-guitarix
run git clone https://github.com/brummer10/GxPlugins.lv2.git
workdir GxPlugins.lv2
run git submodule init
run git submodule update
run apt-fast install -y make g++ lv2-dev pkg-config
run make
run make install
run mkdir /install-guitarix
workdir /usr/lib
run tar czvf /install-guitarix/guitarix-lv2.tar.gz ./lv2 
workdir /install-guitarix
run tar tzvf guitarix-lv2.tar.gz

# Build Dexed VST

from ardour as dexed

run apt-fast install -y git
run mkdir /build-dexed
workdir /build-dexed
run git clone https://github.com/asb2m10/dexed.git
workdir dexed
run git checkout v0.9.4
run apt-fast install -y freeglut3-dev g++ libasound2-dev libcurl4-openssl-dev
run apt-fast install -y libfreetype6-dev libx11-dev libxcomposite-dev
run apt-fast install -y libxcursor-dev libxinerama-dev libxrandr-dev mesa-common-dev make
workdir Builds/Linux
run make CONFIG=Release "CXXFLAGS=-D JUCE_ALSA=0"
run install -Dm755 build/Dexed.so /usr/lib/vst/Dexed.so 

# Get x42 plugins which supposedly do not require registration and can be downloaded as binaries

from ardour as x42

run apt-fast install -y curl unzip wget

run mkdir /install-x42
workdir /install-x42
run for proj in x42-avldrums x42-midievent x42-plumbing x42-scope zero-convolver setBfree; do \
                export X42_VERSION=$(wget -q -O - http://x42-plugins.com/x42/linux/${proj}.latest.txt) ;\
                echo Downloading ${proj}-${X42_VERSION} ;\
                rsync -a -q --partial rsync://x42-plugins.com/x42/linux/${proj}-${X42_VERSION}-x86_64.tar.gz \
                "/install-x42/${proj}-${X42_VERSION}-x86_64.tar.gz" ; done

workdir /install-x42
run for f in *.tar.gz ; do tar xzvf $f ; done
run for d in $(find . -type d -maxdepth 1 | grep -v '\.$') ; do (cd $d; cp -afpr . /usr/lib/lv2) ; done

# Get x42 plugins that should be built from source

from ardour as x42p

run apt-fast install -y git mesa-common-dev libglu1-mesa-dev libjack-jackd2-dev libzita-convolver-dev libltc-dev
run mkdir -p /build-x42
workdir /build-x42
run git clone https://github.com/x42/x42-plugins.git
workdir x42-plugins
run make all
run make install PREFIX=/usr
workdir stepseq.lv2/misc
run make
run ./boxmaker 16 8
run ./boxmaker 32 8
workdir /build-x42/x42-plugins/stepseq.lv2
run export RW=../robtk/ ; make clean ; make N_STEPS=16 && make install N_STEPS=16 PREFIX=/usr
run export RW=../robtk/ ; make clean ; make N_STEPS=12 && make install N_STEPS=12 PREFIX=/usr
run ls -l /usr/lib/lv2

# Build Zynaddsubfx Fusion

from ardour as zynfusion

run apt-fast install -y git build-essential git ruby libtool libmxml-dev automake cmake libfftw3-dev 
run apt-fast install -y libjack-jackd2-dev liblo-dev libz-dev libasound2-dev mesa-common-dev libgl1-mesa-dev 
run apt-fast install -y libglu1-mesa-dev libcairo2-dev libfontconfig1-dev bison sed make
run mkdir /build-zynfusion
workdir /build-zynfusion
run git clone https://github.com/zynaddsubfx/zyn-fusion-build.git
workdir zyn-fusion-build
run grep -v "sudo echo sudo" build-linux.rb | grep -v "^build_demo_package\(\)" | sed 's/sudo//g' >build-linux-nosudo.rb
run ruby build-linux-nosudo.rb

# Build Calf plugins

from ardour as calf

run apt-fast install -y libtool autoconf libexpat1-dev libglib2.0-dev libfluidsynth-dev libglade2-dev lv2-dev make
run mkdir /build-calf
workdir /build-calf
run wget http://calf-studio-gear.org/files/calf-0.90.3.tar.gz
run tar xzvf calf-0.90.3.tar.gz
workdir calf-0.90.3
run ./autogen.sh
run ./configure --prefix=/usr/
run make -j 2
run make install

# Build SooperLooper LV2

from ardour as sooper

run apt-fast install -y git
run mkdir /build-sl
workdir /build-sl
run git clone https://github.com/moddevices/sooperlooper-lv2-plugin.git
workdir sooperlooper-lv2-plugin/sooperlooper
run make 
run make install INSTALL_PATH=/usr/lib/lv2

# Build helm synthesizer

from ardour as helm

run apt-fast install -y git mesa-common-dev libglvnd-dev
run mkdir /build-helm
workdir /build-helm
run git clone https://github.com/mtytel/helm.git
workdir helm
run make lv2
run make vst
run make install_lv2
run make install_vst

# build amSynth

from ardour as amsynth

run apt-fast install -y git autoconf automake libtool cmake intltool liboscpack-dev dssi-dev
run mkdir /build-amsynth
workdir /build-amsynth
run git clone https://github.com/amsynth/amsynth.git
workdir amsynth
run git checkout release-1.9.0
run autoreconf -i
run libtoolize --force
run intltoolize
run ./configure --prefix=/usr --with-alsa --with-lv2 --with-vst --without-jack --with-gui --without-pandoc \
                --disable-dependency-tracking
run make
run make install

# Build Carla

from ardour as carla

run apt-fast install -y git python3-pyqt5.qtsvg python3-rdflib pyqt5-dev-tools \
                   libmagic-dev liblo-dev libasound2-dev libx11-dev \
                   libgtk2.0-dev qtbase5-dev libfluidsynth-dev
run mkdir /build-carla
workdir /build-carla
run git clone https://github.com/falkTX/Carla.git
workdir Carla
run git checkout v2.0.0
run make PREFIX=/usr
run make install PREFIX=/usr

# Build Drumgizmo

from ardour as drumgizmo

run apt-fast install -y build-essential autoconf  automake libtool \
                  lv2-dev xorg-dev libsndfile1-dev libzita-resampler-dev
run mkdir /build-drumgizmo
workdir /build-drumgizmo
run wget http://www.drumgizmo.org/releases/drumgizmo-0.9.17/drumgizmo-0.9.17.tar.gz
run tar xzvf drumgizmo-0.9.17.tar.gz
workdir drumgizmo-0.9.17
run ./configure --prefix=/usr --with-lv2dir=/usr/lib/lv2 --enable-lv2 --disable-cli
run make
run make install

# Final assembly. Pull all parts together.

from base-ubuntu as adls

# No recommended and/or suggested packages here

run echo "APT::Get::Install-Recommends \"false\";" >> /etc/apt/apt.conf
run echo "APT::Get::Install-Suggests \"false\";" >> /etc/apt/apt.conf
run echo "APT::Install-Recommends \"false\";" >> /etc/apt/apt.conf
run echo "APT::Install-Suggests \"false\";" >> /etc/apt/apt.conf

# Install Ardour from the previously created bundle.

run mkdir -p /install-ardour
workdir /install-ardour
copy --from=ardour /build-ardour/ardour-5.12.0/tools/linux_packaging/Ardour-5.12.0-dbg-x86_64.tar .
run tar xvf Ardour-5.12.0-dbg-x86_64.tar
workdir Ardour-5.12.0-dbg-x86_64

# Install some libs that were not picked by bundlers - mainly X11 related.

run apt -y install gtk2-engines-pixbuf libxfixes3 libxinerama1 libxi6 libxrandr2 libxcursor1 libsuil-0-0
run apt -y install libxcomposite1 libxdamage1 liblzo2-2 libkeyutils1 libasound2 libgl1 libusb-1.0-0

# First time it will fail because one library was not copied properly.

run ./.stage2.run || true

# Copy the missing libraries

run cp /usr/lib/x86_64-linux-gnu/gtk-2.0/2.10.0/engines/libpixmap.so Ardour_x86_64-5.12.0-dbg/lib
run cp /usr/lib/x86_64-linux-gnu/suil-0/libsuil_x11_in_gtk2.so Ardour_x86_64-5.12.0-dbg/lib
run cp /usr/lib/x86_64-linux-gnu/suil-0/libsuil_qt5_in_gtk2.so Ardour_x86_64-5.12.0-dbg/lib

# It will ask questions, say no.

run echo -ne "n\nn\nn\nn\nn\n" | ./.stage2.run

# Delete the unpacked bundle

run rm -rf /install-ardour

# Install QMidiArp

run mkdir /install-qmidiarp
copy --from=qmidiarp /install-qmidiarp /install-qmidiarp
workdir /usr/lib
run tar xzvf /install-qmidiarp/qmidiarp-lv2.tar.gz
run rm -rf /install-qmidiarp

# Install guitarix proper

copy --from=guitarix-proper /usr/lib/lv2 /usr/lib/lv2
copy --from=guitarix-proper /usr/share /usr/share

run apt-fast install -y libgxwmm-dev

# Install guitarix extra LV2

run mkdir /install-guitarix

copy --from=guitarix /install-guitarix /install-guitarix
workdir /usr/lib
run tar xzvf /install-guitarix/guitarix-lv2.tar.gz
run rm -rf /install-guitarix

# Install Dexed

run mkdir -p /usr/lib/vst

copy --from=dexed /usr/lib/vst/Dexed.so /usr/lib/vst

# Install x42 plugins

run apt-fast install -y libglu1-mesa
copy --from=x42 /usr/lib/lv2 /usr/lib/lv2
copy --from=x42p /usr/lib/lv2 /usr/lib/lv2

# Install zyn-fusion

copy --from=zynfusion /build-zynfusion/zyn-fusion-build /build-zynfusion/zyn-fusion-build
workdir /build-zynfusion/zyn-fusion-build 
run find . -name '*.tar.bz2'
run tar -jxvf zyn-fusion-linux-64bit-3.0.3-patch1-release.tar.bz2
workdir zyn-fusion
run ln -sf /bin/false /usr/bin/pkg-config
run bash ./install-linux.sh
run rm -rf /build-zynfusion
run apt-fast install -y libmxml1 

# Install Calf plugins

run apt-fast install -y libfluidsynth-dev
copy --from=calf /usr/lib/calf /usr/lib/calf
copy --from=calf /usr/share/calf /usr/share/calf
copy --from=calf /usr/lib/lv2 /usr/lib/lv2

# Install SooperLooper LV2

copy --from=sooper /usr/lib/lv2 /usr/lib/lv2

# Install helm

copy --from=helm /usr/share/helm /usr/share/helm
copy --from=helm /usr/lib/lv2 /usr/lib/lv2
copy --from=helm /usr/lib/lxvst /usr/lib/lxvst

# Install amsynth

copy --from=amsynth /usr/share/amsynth /usr/share/amsynth
copy --from=amsynth /usr/lib/lv2 /usr/lib/lv2
copy --from=amsynth /usr/lib/vst /usr/lib/vst

# Install Carla

run apt-fast install -y libmagic1 python3 libglib2.0-dev-bin python3-pyqt5.qtsvg python3-rdflib
copy --from=carla /usr/lib/carla /usr/lib/carla
copy --from=carla /usr/share/carla /usr/share/carla
copy --from=carla /usr/lib/vst /usr/lib/vst

# Install Drumgizmo

run apt-fast install -y libzita-resampler1
copy --from=drumgizmo /usr/lib/lv2 /usr/lib/lv2

# Finally clean up

run apt-fast clean
run apt-get clean autoclean
run apt-get autoremove -y
run rm -rf /var/lib/apt
run rm -rf /var/lib/dpkg
run rm -rf /var/lib/cache
run rm -rf /var/lib/log
run rm -rf /tmp/*
copy .qmidiarprc /root

from scratch

copy --from=adls / /

