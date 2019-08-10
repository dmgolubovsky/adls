# This Dockerfile builds an image with Ardour and some other goodies installed.
# Jack is omitted on purpose: ALSA gives better latency when playing on a MIDI keyboard
# and feeding MIDI to synth plugins.


# Pull the base image and install the dependencies per the source package;
# this is a good approximation of what is needed.

from ubuntu:18.04 as common-deps

run apt -y update && apt -y upgrade

run cp /etc/apt/sources.list /etc/apt/sources.list~
run sed -Ei 's/^# deb-src /deb-src /' /etc/apt/sources.list
run apt-get -y update

run apt-get -y build-dep ardour

run apt-get -y install git

# Based on the dependencies, butld Ardour proper. In the end create a tar binary bundle.

from common-deps as ardour

run mkdir /build-ardour

workdir /build-ardour

run git clone git://git.ardour.org/ardour/ardour.git 5.12

workdir 5.12

run git checkout 5.12

run ./waf configure --no-phone-home --with-backend=alsa

run ./waf build

run ./waf install

run apt install -y chrpath curl rsync unzip

workdir tools/linux_packaging

run ./build --public --strip some

run ./package --public --singlearch

# Final assembly. Pull all parts together.

from ubuntu:18.04 as adls

run apt -y update && apt -y upgrade

# Install some libs that were not picked by bundlers - mainly X11 related.

run apt -y install gtk2-engines-pixbuf libxfixes3 libxinerama1 libxi6 libxrandr2 libxcursor1
run apt -y install libxcomposite1 libxdamage1 liblzo2-2 libkeyutils1 libasound2 libgl1 libsuil-0-0

# Install Ardour from the previously created bundle.

run mkdir -p /install-ardour

workdir /install-ardour

copy --from=ardour /build-ardour/5.12/tools/linux_packaging/Ardour-5.12.0-dbg-x86_64.tar .

run tar xvf Ardour-5.12.0-dbg-x86_64.tar

workdir Ardour-5.12.0-dbg-x86_64

# First time it will fail because one library was not copied properly.

run ./.stage2.run || true

# Copy the missing libraries

run cp /usr/lib/x86_64-linux-gnu/gtk-2.0/2.10.0/engines/libpixmap.so Ardour_x86_64-5.12.0-dbg/lib
run cp /usr/lib/x86_64-linux-gnu/suil-0/libsuil_x11_in_gtk2.so Ardour_x86_64-5.12.0-dbg/lib

# It will ask questions, say no.

run echo -ne "n\nn\nn\nn\nn" | ./.stage2.run

# Delete the unpacked bundle

run rm -rf /install-ardour



# Finally clean up

run apt-get clean autoclean
run apt-get autoremove -y
run rm -rf /var/lib/{apt,dpkg,cache,log}/

from scratch

copy --from=adls / /

