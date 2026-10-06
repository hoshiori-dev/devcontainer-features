<h1 align="center">devcontainer-features</h1>

<p align="center">
  hoshiori-dev 维护的一组 <a href="https://containers.dev/implementors/features/">Dev Container Features</a>。<br>
  每个 feature 单独发布到 GitHub Container Registry，各自按 SemVer 管理版本。
</p>

<p align="center">
  <a href="README.md">English</a> · <b>简体中文</b>
</p>

<p align="center">
  <a href="https://github.com/hoshiori-dev/devcontainer-features/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/hoshiori-dev/devcontainer-features/actions/workflows/ci.yml/badge.svg?branch=main"></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/github/license/hoshiori-dev/devcontainer-features"></a>
</p>

<p align="center">
  <a href="#使用">使用</a> · <a href="#features">Features</a> · <a href="#原则与审计">原则</a> ·
  <a href="#自己检查已发布的版本">审计</a> · <a href="#参与贡献">参与贡献</a>
</p>

> 本文是 [README.md](README.md) 的中文翻译。两者不一致时，以英文版为准。

## 使用

在 `devcontainer.json` 里用 feature 的 id 和主版本号引用它：

```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu24.04",
  "features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/deno:1": {},
    "ghcr.io/hoshiori-dev/devcontainer-features/uv:1": {}
  }
}
```

引用地址的格式都是 `ghcr.io/hoshiori-dev/devcontainer-features/<feature-id>:<major>`。

> [!NOTE]
> 这个集合还没有收录进 [containers.dev 索引](https://containers.dev/features)，所以编辑器的 feature
> 选择器里找不到它们。引用地址需要手动输入。

`:1` 这样的主版本标签会跟随新的次版本和补丁版本，下次重建容器时就会用上。每个 feature 的选项和限制写在它自己的 README
里。

## Features

<!-- features:start -->

| Feature                                                            | 说明                                                                                                                                                                  |
| ------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [apk-packages](src/apk-packages/README.md)                         | 用 apk 从 Alpine Linux 镜像已配置的软件源安装一组系统软件包。                                                                                                         |
| [apt-packages](src/apt-packages/README.md)                         | 用 apt-get 从 Debian 或 Ubuntu 镜像已配置的软件源安装一组系统软件包。                                                                                                 |
| [colab-cli](src/colab-cli/README.md)                               | 用 uv 和隔离的 Python 3.12 为远程用户安装 Google Colab CLI。                                                                                                          |
| [deno](src/deno/README.md)                                         | 安装 Deno CLI 并按官方发布的校验和验证；用 deno install --global 安装的工具放在共用的 PATH 位置。                                                                     |
| [dnf-packages](src/dnf-packages/README.md)                         | 从镜像已启用的软件源安装列出的系统软件包。                                                                                                                            |
| [firewall](src/firewall/README.md)                                 | 把容器的出站和转发流量限制在由预设、域名和 CIDR 组成的允许列表内（或拦截拒绝列表中的目标），每次启动时通过 nftables 和 dnsmasq 应用这些规则。它是护栏，不是安全边界。 |
| [glab](src/glab/README.md)                                         | 从经过校验和验证的 GitLab 发布包安装 GitLab CLI（glab），不配置任何认证。                                                                                             |
| [hf-cli](src/hf-cli/README.md)                                     | 用官方独立安装器为远程用户安装 Hugging Face CLI，可选安装上游的 hf-cli agent skill。                                                                                  |
| [hf-mount](src/hf-mount/README.md)                                 | 从上游发布的二进制文件安装 hf-mount 守护进程及其 NFS 和 FUSE 后端，用来把 Hugging Face Buckets 和仓库挂载为本地文件系统。                                             |
| [nvidia-container-toolkit](src/nvidia-container-toolkit/README.md) | 从 NVIDIA 签名的软件源安装 NVIDIA Container Toolkit，并把 nvidia 运行时注册到 dev container 内的 Docker 守护进程。                                                    |
| [openspec](src/openspec/README.md)                                 | 从 npm registry 安装 OpenSpec CLI（openspec），验证每个包的完整性哈希和 registry 签名；所需的 Node.js 运行时作为依赖一并带入。                                        |
| [pacman-packages](src/pacman-packages/README.md)                   | 用 pacman 从 Arch Linux 镜像已配置的软件源安装一组系统软件包，安装时会做一次完整的系统升级。                                                                          |
| [uv](src/uv/README.md)                                             | 安装 Astral 的 uv 和 uvx，可选安装 Python 命令行工具；uv 的 Python 解释器和缓存保存在重建后仍然保留的卷上。                                                           |
| [zypper-packages](src/zypper-packages/README.md)                   | 从镜像已启用的软件源安装列出的系统软件包。                                                                                                                            |

<!-- features:end -->

## 原则与审计

feature 的安装脚本在构建镜像时以 root 身份运行，所以它做了什么，不该只能听我们的一面之词。我们按四条原则开发：

- **只用官方来源。** feature 只从上游自己控制的主机、上游用来发布的平台或官方 registry
  下载，不额外引入第三方镜像站或重新打包的版本。系统软件包来自你的镜像已经配置好的软件源。feature 自己请求的每个 URL
  都写在它的规格 `openspec/specs/<feature-id>/spec.md` 里。
- **上游提供校验手段时一定校验。** 上游发布了校验和或签名，feature 就会取回并用它核对下载内容，核对不了就失败。没有哪个
  feature 会关闭证书或签名检查。
- **脚本写出来是给人读的。** 每个 `install.sh` 在开头列出它要下载的 URL
  和它信任的签名密钥，写法面向会在使用前审查它的人。
- **选项不隐藏行为。** 我们设计选项时遵循一点：如果某个配置会让 feature 执行不寻常的操作或访问不寻常的地址，它在你审阅的
  `devcontainer.json` 里看起来也应该不寻常。

脚本之外：每个改动都要经过 pull request，对某个 feature 的改动会在它支持的每个镜像上测试，包括连续安装两次。GitHub
Actions 按 commit SHA 固定。版本只由 `main` 上的 [Release workflow](.github/workflows/release.yml)
发布，发布后它会给对应的 commit 打上 `<feature-id>/v<version>` 标签。

### 自己检查已发布的版本

你可以把 registry 上实际提供的内容和发布标签对应的源码做比较，一共四步：

1. 取回发布标签 `<feature-id>/v<version>` 处的源码。
2. 直接从 registry 取回已发布的制品。
3. 比较两者，它们应该完全一致。
4. 固定你检查过的 digest，这样重建时不会换成别的内容。

下面的命令做的就是这四步。请在 Linux 或任意 dev container 里运行，需要 `git`、`curl`、`tar` 和 `sha256sum`。

<details>
<summary>显示命令</summary>

```bash
(
    set -euo pipefail
    REPO=hoshiori-dev/devcontainer-features
    ID=deno
    VERSION=1.0.1

    # 一个空目录，这样上次运行留下的文件不会被当成结果。
    WORK=$(mktemp -d)
    cd "$WORK"

    # 1. 构建这个版本所用的源码：发布标签处的代码。
    git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$ID/v$VERSION" \
        "https://github.com/$REPO.git" source

    # 2. 已发布的制品，直接从 registry 取。
    TOKEN=$(curl -fsSL "https://ghcr.io/token?scope=repository:$REPO/$ID:pull" |
        sed -nE 's/.*"token":"([^"]+)".*/\1/p')
    curl -fsSL -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/vnd.oci.image.manifest.v1+json" \
        "https://ghcr.io/v2/$REPO/$ID/manifests/$VERSION" -o manifest.json
    # feature 的 manifest 里有两个 blob：一个空的 config，以及唯一的一层，也就是 feature 本身。
    DIGESTS=$(grep -oE 'sha256:[0-9a-f]{64}' manifest.json)
    [ "$(echo "$DIGESTS" | wc -l)" -eq 2 ] || { echo "unexpected manifest: stop here" >&2; exit 1; }
    LAYER=$(echo "$DIGESTS" | tail -n 1)
    curl -fsSL -H "Authorization: Bearer $TOKEN" \
        "https://ghcr.io/v2/$REPO/$ID/blobs/$LAYER" -o feature.tar
    echo "${LAYER#sha256:}  feature.tar" | sha256sum --check

    # 3. 比较。有任何差异都会打印出来，并在这里停下。
    mkdir published && tar -xf feature.tar -C published
    diff -r "source/src/$ID" published
    echo "identical to $ID/v$VERSION; read the source in $WORK/source/src/$ID"

    # 4. 用来固定版本的引用地址，这样重建时不会换成别的内容。
    DIGEST=$(sha256sum manifest.json | cut -d' ' -f1)
    echo "ghcr.io/$REPO/$ID@sha256:$DIGEST"
)
```

</details>

这些命令会在第一个失败的步骤停下，只有比较通过后才打印引用地址。信任它之前，先到命令打印出的 目录里读一遍 `install.sh`
以及它旁边的
`scripts/`（如果有）：你的构建运行的就是这些，容器启动时运行的也是它留下的这些。想用你读过的那个确切版本，就在
`devcontainer.json` 里用第 4 步得到的引用地址替换 `:1` 标签。之后要升级版本，把这套检查再做一遍。

> [!IMPORTANT]
> **这些还不能保证什么**
>
> - 已发布的制品没有签名，也没有来源证明（[#100](https://github.com/hoshiori-dev/devcontainer-features/issues/100)）。上面的比较是现在唯一可用的检查。
> - 上游没有发布校验和或签名时，下载只依赖 TLS。feature 的规格会逐项写明这样的下载。
> - feature 安装的是你指定的上游版本。如果上游自己发布了有问题的版本，feature 会照样安装。

## 参与贡献

| 你是         | 从这里开始                         |
| ------------ | ---------------------------------- |
| 人类贡献者   | [CONTRIBUTING.md](CONTRIBUTING.md) |
| 要报告漏洞   | [SECURITY.md](SECURITY.md)         |
| Coding agent | [AGENTS.md](AGENTS.md)             |

Coding agent：如果你还没有读过
[AGENTS.md](AGENTS.md)，在这个仓库里做任何事之前先读它。它是你的入口，会把你带到当前任务对应的规则。

## 许可证

[Apache License 2.0](LICENSE)
