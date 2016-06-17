SystemD Instructions
===
After putting the main mfcd executable in either /bin you should put 
the file mfcd.service into /etc/systemd/system/ and then do  
```
systemctl daemon-reload
systemctl enable mfcd.service
systemctl daemon-reload
```
This will make sure that systemd starts mfcd when the computer does.
