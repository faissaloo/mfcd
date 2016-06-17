Upstart Instructions
===
After putting the main mfcd executable in either /bin or /usr/bin you should put 
the files /init_files/mfcd and /init_files/mfcd.conf into /etc/init.d and then do  
```
sudo chmod 755 /etc/init.d/mfcd
sudo update-rc.d mfcd defaults
```
This will make it so that upstart starts the daemon when the computer does.
