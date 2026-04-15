# AGENTS.md

## Scope & Priority
- 本文件用于在当前仓库内工作的编码代理。
- 目标是让代理在 1 分钟内建立工作边界，而不是替代产品介绍、部署教程或完整 onboarding。
- 规则优先级固定为：用户或维护者直接指令 > `AGENTS.md` > CI、`go.mod`、`package.json`、`Makefile` 等可执行清单 > `README.md` / `DEV_GUIDE.md`。
- 文档冲突时，以可执行事实为准。
- 当前 Go 版本以 `backend/go.mod` 和 `.github/workflows/backend-ci.yml` 为准，即 `1.26.2`。
- 发现旧文档、旧命令或目录漂移时，先核对仓库现状，再决定是否改文档或代码。

## Project Map
- `backend/`：Go 后端，入口在 `cmd/server`。
- 核心业务主要位于 `backend/internal/{handler,service,repository,middleware,server,...}`。
- `frontend/`：Vue 3 + Vite 管理端，源代码在 `src/`，测试主要位于 `src/__tests__/`。
- `deploy/`：Docker Compose 与部署示例。
- `docs/`：补充文档目录，只按实际文件内容引用。
- `tools/`：CI 和安全扫描用到的辅助脚本。
- 前端构建产物输出到 `backend/internal/web/dist`。
- 修改前端时，应编辑 `frontend/src/**`，不要手改 `backend/internal/web/dist/**`。

## Working Rules
- 保持后端分层边界，遵守 `backend/.golangci.yml` 的限制。
- `handler` 和 `service` 不应直接导入 `repository`、`gorm` 或 `redis`。
- 前端包管理与脚本执行统一使用 `pnpm`，不要引入 `npm` 工作流或锁文件。
- 修改 `backend/ent/schema/**` 后，必须运行 `cd backend && go generate ./ent`，并提交生成后的 `backend/ent/**`。
- 修改 `backend/cmd/server/**` 中的 Wire 装配或 provider 图后，必须运行 `cd backend && go generate ./cmd/server`，并提交 `wire_gen.go`。
- 不要把根 `Makefile` 里的 `datamanagement*` 目标当作当前仓库标准流程；当前仓库没有 `datamanagement/` 目录。
- 优先做小而聚焦的改动；只有在当前任务直接需要时，才调整相邻层或文档。

## Verification
- 后端一般逻辑改动：`cd backend && make test-unit`
- 后端涉及数据库、Redis、网关转发、中间件、计费或集成链路：额外运行 `cd backend && make test-integration`
- 后端交付前质量检查：`cd backend && golangci-lint run ./...`
- 前端页面、状态、路由、接口绑定改动：`cd frontend && pnpm run lint:check && pnpm run typecheck`
- 前端涉及已有测试覆盖区域、交互流程或 `src/__tests__/**` 附近逻辑：额外运行 `cd frontend && pnpm run test:run`
- 前端涉及构建链路、静态资源落盘、Vite 配置或嵌入式 Web 产物：额外运行 `cd frontend && pnpm run build`
- 前后端联动改动必须分别验证两侧，不接受只跑单侧命令就宣称完成。
- 无法运行某条验证命令时，要明确说明原因和未验证范围。

## Generated Code & Gotchas
- `backend/ent/**` 和 `backend/cmd/server/wire_gen.go` 都是生成结果；先改输入，再重新生成，不要直接手改生成文件。
- Windows 本地数据库或缓存连接优先使用 `127.0.0.1`，避免 `localhost` 的解析差异。
- PowerShell 和 `psql` 中，带 `$` 的 hash 或 SQL 字符串、以及中文路径，都是常见坑点；复杂 SQL 优先写入文件后用 `psql -f` 执行。

## References
- `README.md`：产品总览、部署方式、仓库高层背景。
- `DEV_GUIDE.md`：本地开发约定、Windows 常见坑点、团队补充说明。
- `.github/workflows/*.yml`：CI 实际执行的版本、测试和安全检查。
