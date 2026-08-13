# DeepSeek Harness Docker 部署

## 文件说明

```
docker/
├── Dockerfile              # 单阶段构建：只 COPY 本地构建产物，不编译
├── docker-compose.yml      # 服务编排，启动 dsh 容器
├── .dockerignore           # 构建上下文过滤
├── entrypoint.sh           # 容器启动入口脚本
├── dsh.patch.yml           # 覆盖 webserver 绑定到 0.0.0.0（容器环境需要）
├── nginx/
│   └── default.conf        # 参考用的 nginx 反向代理配置
└── README.md               # 本文件
```

## 前置要求

- Docker Engine 24+
- Docker Compose v2+
- 宿主机上运行一个 nginx 实例（用于反向代理）
- **本地需要 Node.js 22+ 和 pnpm**

## 工作原理

所有构建工作都在**本地开发机**完成，服务器**只做 COPY**，不执行任何编译。

| 构建内容 | 在哪里执行 | 说明 |
|---------|-----------|------|
| 前端 SPA | **本地开发机** | Vite 构建，输出 `apps/web/dist/` |
| 后端 TypeScript | **本地开发机** | tsc + tsdown 编译，输出 `apps/cli/lib/`、`packages/*/lib/` |
| 生产依赖 | **服务器容器内** | `pnpm install --prod` 安装 Linux 版 native addon |
| Docker 镜像 | **服务器** | 只 COPY 编译产物 + 安装生产依赖，**仅需 2-3 分钟** |

## 构建与部署流程

### 步骤 1：本地完整构建

```bash
# 在本地开发机（Windows，有足够内存）执行
cd deepseek-harness
pnpm install
pnpm run build
```

这会生成所有构建产物：
- `apps/web/dist/` — 前端静态文件（跨平台）
- `apps/cli/lib/` — CLI 入口（跨平台 JS）
- `packages/*/lib/` — 各包编译产物（跨平台 JS）

### 步骤 2：上传构建产物到服务器

```bash
# 只上传构建产物和必要文件，大幅减少上传量
scp -r \
  apps/cli/ \
  apps/web/dist/ \
  apps/web/package.json \
  packages/ \
  vendor/ \
  patches/ \
  package.json pnpm-lock.yaml pnpm-workspace.yaml \
  docker/ \
  root@your-server:/path/to/deepseek-harness/
```


### 步骤 3：构建 Docker 镜像

```bash
# 服务器上构建，只 COPY 编译产物 + 安装生产依赖
# --network host：使用宿主机网络
# --build-arg HTTP_PROXY/HTTPS_PROXY：可选，用于代理下载 npm 包
docker build -f docker/Dockerfile \
  --network host \
  --build-arg HTTP_PROXY=http://127.0.0.1:7890 \
  --build-arg HTTPS_PROXY=http://127.0.0.1:7890 \
  -t 595998300/deepseek-harness:latest .
```

### 步骤 4：启动容器

```bash
# 使用 docker-compose 启动（已配置 network_mode: host）
docker compose -f docker/docker-compose.yml up -d
```

## 验证

```bash
# 检查容器是否正常运行
docker ps --filter name=dsh

# 检查 dsh 进程日志
docker logs dsh

# 测试 API 是否响应
curl http://localhost:3000/
```

## 配置 nginx

将 `docker/nginx/default.conf` 复制到你的 nginx 配置目录，然后重载 nginx：

```bash
# Linux
sudo cp docker/nginx/default.conf /etc/nginx/conf.d/dsh.conf
sudo nginx -s reload
```

## 持久化数据

容器使用 Docker volume `dsh_home` 持久化会话数据、设置和用户配置：

```bash
# 查看 volume 位置
docker volume inspect dsh_dsh_home

# 备份数据
docker run --rm -v dsh_dsh_home:/data -v $(pwd):/backup alpine tar czf /backup/dsh-backup.tar.gz -C /data .
```

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DSH_TELEMETRY_DISABLED` | `1` | 关闭遥测上报（容器环境默认关闭） |

API Key 不需要在环境变量中配置，启动后访问 Web 界面，在设置页面中配置即可。设置会持久化到 volume，重启不丢失。

## 常见问题

### 容器启动后无法访问

1. 检查容器日志：`docker logs dsh`
2. 确认 nginx 已正确配置并重载
3. 确认宿主机没有其他进程占用 3000 端口

### 构建失败

1. 确保本地已执行 `pnpm run build` 完整构建
2. 检查 `node_modules/` 是否已安装（`pnpm install`）

### 如何更新

```bash
# 本地重新完整构建
pnpm run build

# 只上传构建产物到服务器
scp -r \
  apps/cli/ \
  apps/web/dist/ \
  apps/web/package.json \
  packages/ \
  vendor/ \
  patches/ \
  package.json pnpm-lock.yaml pnpm-workspace.yaml \
  docker/ \
  root@your-server:/path/to/deepseek-harness/

# 服务器上重新构建镜像并启动
docker build -f docker/Dockerfile \
  --network host \
  --build-arg HTTP_PROXY=http://127.0.0.1:7890 \
  --build-arg HTTPS_PROXY=http://127.0.0.1:7890 \
  -t 595998300/deepseek-harness:latest .
docker compose -f docker/docker-compose.yml up -d
```

## nginx 配置要点

`docker/nginx/default.conf` 包含三个关键配置，你的 nginx 必须覆盖：

1. **WebSocket 升级**：`/api/events.mux` 和 `/api/events.host` 需要设置 `Upgrade` 和 `Connection` 头，否则浏览器 WebSocket 连接失败
2. **SSE 关闭缓冲**：`/api/` 路径下必须设置 `proxy_buffering off`，否则实时事件流被缓冲导致前端卡死
3. **请求体大小**：建议设置 `client_max_body_size 50m`，支持附件上传和会话导出