#!/bin/bash
dir=$1
sd=$2 
echo dir:$dir sd:${sd} 
echo mkdir ${dir}
mkdir  -p ${dir}

echo cd ${dir}
cd  ${dir}

#mount sd card
echo mkdir src_boot src_root
mkdir -p src_boot src_root
echo mount ${sd}1 ${sd}2
mount -t vfat -o umask=0000  ${sd}1 ./src_boot/
mount -t ext4 ${sd}2 ./src_root/

isosize=`df -B 1M | grep ${sd} | awk '{ sum+=$3};END {print sum}'`
isosize=$((isosize+isosize/5))

echo Build ${dir}.img ${isosize}M ...
dd if=/dev/zero of=${dir}.img bs=1M count=${isosize}

parted ${dir}.img --script -- mklabel msdos
parted ${dir}.img --script -- mkpart primary fat32 8192s 122479s
parted ${dir}.img --script -- mkpart primary ext4 122880s -1


loopdevice=`sudo losetup -f --show ${dir}.img`
r=`kpartx -sva ${loopdevice} | awk '{print $3}'`
read -r -a devices <<< $r

loop0p1=/dev/mapper/${devices[0]}
loop0p2=/dev/mapper/${devices[1]}

mkfs.vfat -n boot ${loop0p1}
mkfs.ext4 ${loop0p2}

mkdir tgt_boot tgt_root
mount -t vfat -o umask=0000 ${loop0p1} ./tgt_boot/
mount -t ext4 ${loop0p2} ./tgt_root/

cp -rfp ./src_boot/* ./tgt_boot/

chmod 777 tgt_root
rm -rf ./tgt_root/*
cd tgt_root
echo Dump...
dump -0uaf - ../src_root/ | sudo restore -rf -

cd ..
echo Replace PARTUUID
bootid=`blkid | grep ${loop0p1} | grep -oP "(?<=PARTUUID=\")\S*(?=\")"`
echo PARTUUID boot ${bootid}
rootid=`blkid | grep ${loop0p2} | grep -oP "(?<=PARTUUID=\")\S*(?=\")"`
echo PARTUUID root ${rootid}

sed -i "s/root=PARTUUID=[[:graph:]]*/root=PARTUUID=${rootid}/" tgt_boot/cmdline.txt
echo "New cmdline.txt"
cat tgt_boot/cmdline.txt

oldbootid=`grep -oP "(?<=PARTUUID=)\S*(?=\s+/boot\s+)" tgt_root/etc/fstab`
echo Old PARTUUID boot ${oldbootid}
oldrootid=`grep -oP "(?<=PARTUUID=)\S*(?=\s+/\s+)" tgt_root/etc/fstab`
echo Old PARTUUID root ${oldrootid}

sed -i "s/${oldbootid}/${bootid}/" tgt_root/etc/fstab
sed -i "s/${oldrootid}/${rootid}/" tgt_root/etc/fstab

echo "New /etc/fstab:"
cat tgt_root/etc/fstab

echo Clean...
umount src_boot src_root tgt_boot tgt_root

kpartx -d ${loopdevice}
losetup -d ${loopdevice}

rmdir src_boot src_root tgt_boot tgt_root

echo Finished!
ls -l

