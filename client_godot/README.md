# mir2x Godot 客户端

这是与原 C++ 客户端并列的 Godot 4.7 客户端工程。项目基准画布为
800×600 用于账号流程；进入游戏后采用 1024×768 布局，面板保持原始像素尺寸。
旧的 800×600 / 1920×1080 窗口配置在进入游戏时按 1024×768 应用。账号流程使用原客户端纹理和原坐标，可直接在 Godot 编辑器中
打开 `.tscn` 查看完整效果。

## 原始资源准备

Godot 客户端不维护第二份游戏资源。`build_remote.sh` 默认从仓库上级的
`../mir2x_res` 复制原版字体，并用 `godotworldres` 将地图、角色、物品 ZSDB
转换到 `client_godot/build/world_res`。可用 `MIR2X_RES_REPO_PATH` 指定其它位置；
开发时可设置 `MIR2X_GODOT_MAP_ID=24` 只转换当前测试地图。

```sh
GODOT_BIN=/home/czx/godot MIR2X_GODOT_MAP_ID=24 ./client_godot/build_remote.sh
```

## 场景

- `scenes/startup/logo.tscn`：启动 Logo
- `scenes/startup/sync.tscn`：服务器连接与进度条
- `scenes/account/login.tscn`：登录
- `scenes/account/create_account.tscn`：创建账号
- `scenes/account/change_password.tscn`：修改密码
- `scenes/account/select_character.tscn`：选择角色
- `scenes/account/create_character.tscn`：创建角色
- `scenes/account/delete_character_dialog.tscn`：删除角色确认

`project.godot` 的入口是启动 Logo，启动流程会连接
`10.0.15.150:7000`，然后进入登录场景。

## Ubuntu 构建

在仓库根目录执行：

```sh
ssh ubuntu@10.0.15.150 \
  'cd /home/ubuntu/mir3/mir2x && ./client_godot/build_remote.sh'
```

脚本使用 `/home/ubuntu/.local/bin/godot4` 导入并编译 GDScript，随后生成：

```text
client_godot/build/mir2x-client.pck
```

## 协议测试

无副作用的账号协议测试：

```sh
/home/ubuntu/.local/bin/godot4 --headless \
  --path client_godot \
  res://tests/network_login_smoke.tscn
```

默认测试账号的只读登录、查询角色测试：

```sh
/home/ubuntu/.local/bin/godot4 --headless \
  --path client_godot \
  res://tests/network_query_smoke.tscn
```

协议层已覆盖登录、注册、改密、查询角色、创建角色、删除角色和进入游戏。
固定结构大小以 Ubuntu C++ 编译器的 `sizeof` 为准，包括
`StaticBuffer<64>` 的尾部对齐字节。
