#version=RHEL7
# Install OS instead of upgrade
install

# Reboot after installation
reboot --eject

# Use network installation
url --url="http://mirror-centos.locaweb.com.br/7/os/x86_64/"

# License agreement
eula --agreed

# Use graphical install
#graphical

# Use text mode install
text

# Do not configure the X Window System
skipx

# Run the Setup Agent on first boot
firstboot --enable

# Keyboard layouts
keyboard --vckeymap=us --xlayouts='us'

# System language
lang en_US.UTF-8

# Network information
network --bootproto=dhcp --noipv6 --activate
network --hostname=centos7.claudioborges.org

# Root password
rootpw --iscrypted $6$3jbQnNUNY/.1hlbg$ellrx8S7vY7NyXVy7z4PoqA15gGagIY6UdxvxDU26T2cMa0NqOIgISpP9Gby0Exr5qd6WrLYpQQ2FJXzHG7Kj.

# System services
services --enabled="NetworkManager,sshd,chronyd"

# System timezone
timezone America/Sao_Paulo --isUtc --ntpservers=3.centos.pool.ntp.org,0.centos.pool.ntp.org,2.centos.pool.ntp.org,1.centos.pool.ntp.org

# Clear the Master Boot Record
zerombr

# Include partition scheme
%include /tmp/partitioning.txt

%pre
!/bin/bash
# Use RAID+LVM or just LVM to partition the disk

# Partitioning scheme:
#
# /dev/md0 - 512Mb - /boot xfs
# /dev/md1 - raid device + LVM VolGroup00 (if you have 2 or more disks)
# /dev/mapper/VolGroup00/lv_swap - the swap is calculated over the amount
# of RAM in the system, ex:
# if RAM < 2GB then SWAP = 2x physical RAM
# if RAM > 2GB or MEM < 8GB then SWAP = Equal to the amount of RAM
# if RAM > 8GB then SWAP = At least 4 GB
# /dev/mapper/VolGroup00/lv_root - 3Gb   - /    xfs
# /dev/mapper/VolGroup00/lv_tmp  - 512Mb - /tmp xfs
# /dev/mapper/VolGroup00/lv_var  - 1Gb   - /var xfs

# Get the disks
COUNT=0
for DISK in $(awk '{if ($NF ~ "^(s|h)d|cciss" && $NF !~ "((s|h)d|c.d.)[a-z][0-9]$") print $4}' /proc/partitions); do
    DEVS[${COUNT}]="${DISK}"
    DISKS[${COUNT}]="${DISK//\/dev\/}"
    let COUNT++
done

# Define the RAID level
if [ ${COUNT} -eq "1" ]; then
    LEVEL=-1
elif [ ${COUNT} -eq "2" ]; then
    LEVEL=1
elif [ ${COUNT} -eq "3" ]; then
    LEVEL=5
elif [ ${COUNT} -ge "4" ]; then
    LEVEL=10
fi

# Calculate the SWAP size over the amount of RAM
MEM=$(($(sed -n 's/^MemTotal: \+\([0-9]*\) kB/\1/p' /proc/meminfo) / 1024))
if [ "${MEM}" -lt "2048" ]; then
    SWAP=$((MEM * 2))
elif [ "${MEM}" -gt "2048" ] || [ "${MEM}" -le "8192" ]; then
    SWAP=${MEM}
elif [ "${MEM}" -ge "8192" ]; then
    SWAP=4096
fi

# If the system has two disks (or more), it will create the RAID + LVM
if [ ${LEVEL} -ge "1" ]; then
    x=${#DEVS[@]}
    DEVS=${DEVS[@]:0}
    DISKS=${DISKS[@]:0}
    echo "ignoredisk --only-use=${DISKS// /,}"                 > /tmp/partitioning.txt
    echo "clearpart --all --initlabel --drives=${DISKS// /,}" >> /tmp/partitioning.txt
    for ((i=0; i < ${#DEVS[@]}; i++)); do
        echo "part raid.0${i} --fstype=\"mdmember\" --size=512 --ondisk=${DISK[$i]}" >> /tmp/partitioning.txt
        echo "part raid.0${x} --fstype=\"mdmember\" --grow     --ondisk=${DISK[$i]}" >> /tmp/partitioning.txt
        RAIDPARTS1[$i]="raid.0${i}"
        RAIDPARTS2[$x]="raid.0${x}"
        let x++
    done
    echo "raid /boot --device=0 --fstype=\"xfs\"   --level=raid${LEVEL} ${RAIDPARTS1[@]:0}" >> /tmp/partitioning.txt
    echo "raid pv.00 --device=1 --fstype=\"lvmpv\" --level=raid${LEVEL} ${RAIDPARTS2[@]:0}" >> /tmp/partitioning.txt
# Otherwise, it will use just LVM
else
    echo "part /boot --fstype=\"xfs\"   --size=512"            >> /tmp/partitioning.txt
    echo "part pv.00 --fstype=\"lvmpv\" --ondisk=${DISK[@]:0}" >> /tmp/partitioning.txt
fi

# Define the volume group and logical volumes
cat >> /tmp/partitioning.txt <<EOF
volgroup VolGroup00 pv.00
logvol swap --fstype="swap" --size=${SWAP} --name=lv_swap --vgname=VolGroup00
logvol /    --fstype="xfs"  --size=3072 --name=lv_root --vgname=VolGroup00
logvol /tmp --fstype="xfs"  --size=512 --name=lv_tmp --vgname=VolGroup00
logvol /var --fstype="xfs"  --size=1024 --name=lv_var --vgname=VolGroup00
EOF
%end

# Packages to install
%packages
chrony
ftp
kexec-tools
vim-enhanced
wget
%end
