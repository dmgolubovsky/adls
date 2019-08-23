# This Dockerfile builds an image with Ardour and some other goodies installed.
# Jack is omitted on purpose: ALSA gives better latency when playing on a MIDI keyboard
# and feeding MIDI to synth plugins.


# Pull the base image and install the dependencies per the source package;
# this is a good approximation of what is needed.

from ubuntu:18.04 as base-ubuntu

run echo "APT::Get::Install-Recommends \"false\";" >> /etc/apt/apt.conf
run echo "APT::Get::Install-Suggests \"false\";" >> /etc/apt/apt.conf

run apt -y update && apt -y upgrade
run cp /etc/apt/sources.list /etc/apt/sources.list~
run sed -Ei 's/^# deb-src /deb-src /' /etc/apt/sources.list
run apt-get -y update


# Based on the dependencies, butld Ardour proper. In the end create a tar binary bundle.

from base-ubuntu as ardour

run apt install -y libboost-dev libasound2-dev libglibmm-2.4-dev libsndfile1-dev
run apt install -y libcurl4-gnutls-dev libarchive-dev liblo-dev libtag-extras-dev
run apt install -y vamp-plugin-sdk librubberband-dev libudev-dev libnfft3-dev
run apt install -y libaubio-dev libxml2-dev libusb-1.0-0-dev
run apt install -y libpangomm-1.4-dev liblrdf0-dev libsamplerate0-dev
run apt install -y libserd-dev libsord-dev libsratom-dev liblilv-dev
run apt install -y libgtkmm-2.4-dev libsuil-dev

run apt install -y wget curl

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
run apt install -y chrpath rsync unzip
run ln -sf /bin/false /usr/bin/curl
workdir tools/linux_packaging
run ./build --public --strip some
run ./package --public --singlearch


# Build QMidiArp LV2 plugins only

from  base-ubuntu as qmidiarp

run apt install -y git autoconf automake libtool libasound2-dev qt5-default
run apt install -y g++ pkg-config lv2-dev
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

# Final assembly. Pull all parts together.

from base-ubuntu as adls

# Install Ardour from the previously created bundle.

run mkdir -p /install-ardour
workdir /install-ardour
copy --from=ardour /build-ardour/ardour-5.12.0/tools/linux_packaging/Ardour-5.12.0-dbg-x86_64.tar .
run tar xvf Ardour-5.12.0-dbg-x86_64.tar
workdir Ardour-5.12.0-dbg-x86_64

# Install some libs that were not picked by bundlers - mainly X11 related.

run apt-get -y install gtk2-engines-pixbuf libxfixes3 libxinerama1 libxi6 libxrandr2 libxcursor1 libsuil-0-0
run apt-get -y install libxcomposite1 libxdamage1 liblzo2-2 libkeyutils1 libasound2 libgl1 libusb-1.0-0

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

# Finally clean up

run apt-get clean autoclean
run apt-get autoremove -y
run rm -rf /var/lib/{apt,dpkg,cache,log}/

from scratch

copy --from=adls / /
copy .qmidiarprc /root

