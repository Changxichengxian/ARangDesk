# ARangDesk

一个 Windows 桌面图标整理脚本：快捷方式和常用文件夹排在左侧，普通文件排在右侧。

## 下载后怎么装

从 GitHub 下载 ZIP 后，先解压，再双击 `install_shortcut.cmd`。

安装脚本会把必要文件复制到：

```text
%LOCALAPPDATA%\ARangDesk
```

然后在当前用户真实的桌面目录创建 `整理桌面.lnk`。安装完成后，下载的 ZIP 和解压出来的文件夹都可以删除。

## 使用

双击桌面上的 `整理桌面` 快捷方式，整理完成后会显示：

```text
本次整理已完成。按空格或者 Enter 键取消这次更改；按其他键退出。
```

按空格或 Enter 会把本次整理前的图标位置恢复回来。

## 安装桌面快捷方式

运行 `install_shortcut.cmd` 会使用 Windows 返回的桌面路径，所以桌面在 `C:\Users\用户名\Desktop`、OneDrive 桌面或其他重定向位置都可以。

注意：程序本体不会只剩一个 `整理桌面.cmd`。这个 `.cmd` 还需要同目录下的 `organize_desktop.ps1`。安装脚本会自动把这两个文件放到 `%LOCALAPPDATA%\ARangDesk`，桌面上只保留快捷方式。

## 完全删除

ARangDesk 不会添加开机启动，也不会写注册表。要完全去除，删掉这些就可以：

1. 桌面上的 `整理桌面` 快捷方式。
2. `%LOCALAPPDATA%\ARangDesk` 文件夹。
3. 如果装过早期测试版，也删掉 `%LOCALAPPDATA%\DeskARanger` 文件夹。

找不到 `%LOCALAPPDATA%` 时，可以打开文件资源管理器，在地址栏输入 `%LOCALAPPDATA%` 后回车。

## 预览

运行 `preview_organize_desktop.cmd` 可以只查看将要排列的位置，不会移动图标。

## 注意

如果 Windows 的“自动排列图标”已开启，脚本会停止。需要先在桌面右键菜单的“查看”里关闭“自动排列图标”。
