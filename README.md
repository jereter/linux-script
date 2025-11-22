# Rocky Linux 10 常用脚本

Rocky Linux 一键设置本机静态IP: 
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/jereter/linux-script/refs/heads/main/set_static_ip.sh)" -- 192.168.1.x
```

Rocky Linux 一键设置远程代理IP: 
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/jereter/linux-script/refs/heads/main/set_proxy.sh)" -- 192.168.1.x:7890
```
