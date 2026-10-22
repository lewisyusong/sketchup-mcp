# SketchUp MCP

SketchUp MCP 通过 Model Context Protocol（MCP）把 AI 客户端连接到 SketchUp。它可以读取当前选择、创建和修改几何体、设置材质、导出模型，也可以通过受控的 Ruby 代码执行完成更复杂的建模任务。

仓库同时包含两部分：

| 组件 | 位置 | 用途 |
| --- | --- | --- |
| SketchUp 插件 | [`sketchup_mcp_v1.6.0.rbz`](./sketchup_mcp_v1.6.0.rbz) | 安装在 SketchUp 中，在本机 `127.0.0.1:9876` 提供 TCP 服务 |
| Python MCP 服务 | [`src/sketchup_mcp/server.py`](./src/sketchup_mcp/server.py) | 连接 MCP 客户端与 SketchUp 插件 |

通信链路如下：

```text
MCP 客户端  <-- stdio -->  Python MCP 服务  <-- TCP 127.0.0.1:9876 -->  SketchUp 插件
```

## 环境要求

- SketchUp（支持 Ruby 扩展的桌面版）
- Python 3.10 或更高版本
- [uv](https://docs.astral.sh/uv/)（推荐，用于启动或开发 Python MCP 服务）
- 支持 stdio MCP 的客户端，例如 Claude Desktop、Cursor 或其他兼容客户端

## 快速开始

### 1. 安装 SketchUp 插件

发布包位于仓库根目录：

```text
sketchup_mcp_v1.6.0.rbz
```

安装步骤：

1. 打开 SketchUp。
2. 进入 `Extensions > Extension Manager`。部分版本位于 `Window > Extension Manager`。
3. 点击 `Install Extension`，选择根目录中的 `sketchup_mcp_v1.6.0.rbz`。
4. 完成安装后重启 SketchUp。

升级旧版本时，先在 Extension Manager 中卸载旧插件，再安装新的 `.rbz`，避免同时加载多个版本。

### 2. 启动 SketchUp 端服务

重启 SketchUp 后，进入：

```text
Extensions > MCP Server > Start Server
```

Ruby Console 中应出现类似以下内容：

```text
MCP: Server created on port 9876
MCP: Server started and listening
```

停止服务使用 `Extensions > MCP Server > Stop Server`。插件只监听本机回环地址 `127.0.0.1`，默认端口为 `9876`。

### 3. 启动 Python MCP 服务

直接使用 PyPI 上发布的版本：

```powershell
uvx sketchup-mcp
```

也可以在克隆后的仓库中运行当前源码：

```powershell
uv sync
uv run sketchup-mcp
```

服务启动后会等待 MCP 客户端通过 stdio 建立连接。若 SketchUp 端尚未启动，MCP 服务仍可启动，但调用建模工具时会连接失败。

### 4. 配置 MCP 客户端

在客户端配置中加入以下服务器。不同客户端的配置文件位置不同，请以对应客户端的 MCP 配置说明为准。

```json
{
  "mcpServers": {
    "sketchup": {
      "command": "uvx",
      "args": ["sketchup-mcp"]
    }
  }
}
```

如果要从本地源码运行，可将 `command` 改为 `uv`，并通过 `--directory` 指向仓库目录：

```json
{
  "mcpServers": {
    "sketchup": {
      "command": "uv",
      "args": [
        "run",
        "--directory",
        "C:\\path\\to\\SketchupMCP",
        "sketchup-mcp"
      ]
    }
  }
}
```

修改配置后重启 MCP 客户端，并确认 SketchUp 中的 `MCP Server` 已处于运行状态。

## 可用工具

| 工具 | 作用 |
| --- | --- |
| `create_component` | 创建 `cube`、`cylinder`、`sphere` 或 `cone` |
| `delete_component` | 按实体 ID 删除对象 |
| `transform_component` | 按实体 ID 移动、旋转或缩放对象 |
| `get_selection` | 获取当前 SketchUp 选择集 |
| `set_material` | 给指定实体应用当前文档中的材质 |
| `export_scene` | 导出 `skp`、`obj`、`dae`、`stl`、`png`、`jpg/jpeg` |
| `create_mortise_tenon` | 创建榫卯结构 |
| `create_dovetail` | 创建燕尾榫 |
| `create_finger_joint` | 创建指接榫 |
| `eval_ruby` | 在 SketchUp 中执行任意 Ruby 代码 |

示例指令：

- “创建一个位于原点的 100 × 60 × 40 cm 长方体。”
- “把当前选中的对象向上移动 20 cm。”
- “给选中的对象应用名为 `Oak` 的材质。”
- “把当前视图导出为 1920 × 1080 的 PNG。”
- “用 Ruby 创建一个带圆角和门板细节的柜体。”

单位与 SketchUp 当前模型的单位保持一致。`eval_ruby` 功能很强，执行前应先检查代码，尤其是删除、覆盖文件和批量修改模型的代码。

## 工作流建议

1. 先保存模型，再让 AI 执行批量修改。
2. 复杂任务拆成创建、检查、调整、导出几个步骤。
3. 删除或覆盖对象前，先通过 `get_selection` 或 Ruby 代码确认目标实体 ID。
4. 对重要操作使用 SketchUp 的撤销栈；复杂 Ruby 脚本应在 `model.start_operation` 和 `model.commit_operation` 之间执行。

## 故障排查

### MCP 客户端无法连接

- 确认 MCP 客户端配置中的命令为 `uvx sketchup-mcp`，且 `uv` 已安装。
- 在终端手动运行一次 `uvx sketchup-mcp`，检查启动日志。
- 修改客户端配置后，完全退出并重新打开客户端。

### Python 服务无法连接 SketchUp

- 确认 SketchUp 中已执行 `Extensions > MCP Server > Start Server`。
- 检查 Ruby Console 是否有端口占用或扩展加载错误。
- 确认端口 `9876` 未被其他程序占用：

```powershell
Get-NetTCPConnection -LocalPort 9876 -ErrorAction SilentlyContinue
```

- 如果安装后菜单没有出现，重启 SketchUp，并在 Extension Manager 中确认 `SketchUp MCP Server` 已启用。

### 工具调用失败或超时

- 先保存模型，再将复杂操作拆成较小的命令。
- 查看 SketchUp 的 Ruby Console 和启动 MCP 服务的终端日志。
- 某些导出格式依赖 SketchUp 当前版本或已安装的导入/导出组件；若导出失败，可先改用 `skp` 或 `png`。

### 安装新版本后仍运行旧代码

- 在 Extension Manager 中卸载旧版本。
- 完全退出 SketchUp 后重新打开。
- 再安装根目录中的 `sketchup_mcp_v1.6.0.rbz`。

## 从源码开发

Python 服务位于 `src/sketchup_mcp/`。安装依赖并启动：

```powershell
uv sync
uv run sketchup-mcp
```

运行仓库中的连接测试（需要先启动 SketchUp 端服务）：

```powershell
uv run python test_eval_ruby.py
```

SketchUp 插件源码位于 `su_mcp/`：

```text
su_mcp/
├── extension.json
├── package.rb
├── su_mcp.rb
└── su_mcp/
    └── main.rb
```

`.rbz` 本质上是 ZIP 包。发布包至少需要以下条目：

```text
su_mcp.rb
extension.json
su_mcp/main.rb
```

修改插件后，可使用 `su_mcp/package.rb` 重新打包；该脚本需要 Ruby 和 `rubyzip`。本次发布包已直接放在仓库根目录，便于分发。

## 安全说明

- 插件默认只绑定 `127.0.0.1`，不要将其改写为公网地址。
- `eval_ruby` 可以执行任意 SketchUp Ruby 代码，并拥有当前用户权限。
- 只连接可信的 MCP 客户端，不要将端口转发给不可信来源。
- 处理不受信任的提示词或脚本时，先审查代码，再决定是否执行。

## 致谢与许可

项目结构受到 [Blender MCP](https://github.com/ahujasid/blender-mcp) 启发。

本项目使用 MIT License。
