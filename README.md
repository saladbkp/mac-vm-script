# vm-snap — Mac mini 上的 macOS 虚拟机管理

用 [Tart](https://tart.run)(基于 Apple 官方 Virtualization.framework)在这台 Mac mini 上跑 macOS 虚拟机,
配合快照/黄金镜像,做到「**一进去就 ready,零手作**」。

## 文件

| 文件 | 作用 |
|---|---|
| `vm.sh` | 主脚本:建机 / 黄金镜像 / 克隆 / 删除 / 列表 / 运行 |
| `README.md` | 本文档 |

## 一次性准备(已完成)

```bash
brew install cirruslabs/cli/tart        # 装 Tart
./vm.sh create 1                        # 从 Apple 官方 IPSW 下载装好 mac-1(约16GB)
# 在 VM 里走开机设置:语言/地区/账户(本地账户密码:mac1)
```

VM 存储位置:`~/.tart/vms/<名字>`(例:`~/.tart/vms/mac-1`)。

## 命令速查

```bash
./vm.sh create 3        # 确保 mac-1..mac-3 存在(mac-1 下载, 其余从 mac-1 克隆, 已存在跳过)
./vm.sh golden 07       # 把 mac-1 做成黄金镜像 golden-07(自动先关机)
./vm.sh new 2 07        # 从 golden-07 克隆出 mac-2(已登录, 秒开即用)
./vm.sh del 2           # 删除 mac-2(在运行先停, 有确认)
./vm.sh list            # 列出所有 VM/镜像 + 路径 + 占用大小
./vm.sh run 1           # 开窗口运行 mac-1
```
