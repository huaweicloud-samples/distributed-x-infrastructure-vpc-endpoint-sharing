# 部署指导书 · 跨 VPC 共享云服务私有访问

## 前置条件

| 项目 | 要求 |
|------|------|
| 账号权限 | 具备 VPC / VPCEP / ER / ECS / RAM 的创建权限；RAM 共享需主账号或被授权 |
| 工具 | Terraform ≥ 1.9.0；访问华为云 API 的网络出口 |
| 区域 | 同一 region 内部署（ER / VPCEP 仅支持同区域） |
| 密钥 | 请在华为云“我的凭证”页面获取 Access Key 与 Secret Access Key，并在部署前设置 `HW_ACCESS_KEY` / `HW_SECRET_KEY` / `HW_REGION_NAME`；不要将凭据写入代码或配置文件 |
| 密钥对 | 在目标 region 预先创建 ECS 登录密钥对，部署时通过 `-var="key_pair=<名称>"` 传入 |
| 终端节点服务 ID | Hub 要托管的接口型终端节点对应华为云发布的云服务型终端节点 ID（控制台：VPC → 终端节点服务 → 公共终端节点服务）；可按 region 查询后填入 `interface_endpoint_service_ids`（为空则仅建 CoreDNS 骨架与 ER 互联）。OBS 网关终端节点为可选（`enable_obs_gateway`，默认关闭——部分 region 无标准 OBS 网关服务，如 cn-north-4 仅有特殊局点） |

## 快速开始

```bash
# 1. 设置凭证（替换占位符；不要提交真实值）
export HW_ACCESS_KEY="<HW_ACCESS_KEY>"
export HW_SECRET_KEY="<HW_SECRET_KEY>"
export HW_REGION_NAME="cn-north-4"

cd infra

# 2. 初始化（首次会生成 .terraform.lock.hcl）
terraform init

# 3. 预览（不创建资源）
terraform plan \
-var="region=cn-north-4" \
-var="key_pair=<你的密钥对名称>" \
-var='interface_endpoint_service_ids=["<服务ID-1>","<服务ID-2>"]'

# 4. 创建
terraform apply \
-var="region=cn-north-4" \
-var="key_pair=<你的密钥对名称>" \
-var='interface_endpoint_service_ids=["<服务ID-1>","<服务ID-2>"]'
```

## 分步说明

1. **Plan 阶段**：确认 Hub/Spoke VPC、ER 实例与两个 VPC 连接、CoreDNS ECS、两条 ER 私网路由均被创建；`interface_endpoint_service_ids` 为空时接口终端节点资源数为 0，`enable_obs_gateway=false` 时 OBS 网关终端节点不创建。
2. **Apply 阶段**：先建 VPC/子网/ER，再建终端节点与 ECS，最后建路由（依赖关系由 Terraform 自动编排）。Spoke 子网 `dns_list` 在 CoreDNS ECS 私有 IP 就绪后写入。
3. **验证**：见「使用方法 / 验证」。

## 使用方法 / 验证

1. 登录 Spoke 的验证用 ECS（经 Hub 堡垒机或跳板，密钥对登录）。
2. 解析云服务域名，应返回 Hub 终端节点私有 IP（`10.0.0.0/22` 段内）：
```bash
dig +short <云服务域名> # 例如 OBS / KMS 等区域的私有域名
```
3. 访问 OBS（网关终端节点）：`ping` 或 `curl` OBS 端点，流量应走 Spoke 关联路由表中的 OBS 路由，不经过公网。
4. 从 Spoke ECS 访问任一 Hub 托管的接口终端节点对应服务，确认经 ER 互通。

> 部署完成后请按本节步骤自行验证，确认业务功能可用，方可视为交付完成。

## 清理资源

```bash
terraform destroy \
-var="region=cn-north-4" \
-var="key_pair=<你的密钥对名称>" \
-var='interface_endpoint_service_ids=["<服务ID-1>","<服务ID-2>"]'
```

> ER 连接、ECS、终端节点等资源删除后立即释放；`terraform destroy` 仅清理本 state 内资源。
> 删除后建议在控制台或 API 直查确认无残留（尤其孤儿云硬盘）。

## 跨账号生产变体

单账号演示中 Hub/Spoke 共用同一 provider。跨账号（组织内共享）时：

1. 用 provider alias 分别配置 Hub 账号与 Spoke 账号凭证。
2. Hub 侧通过 `huaweicloud_ram_resource_share` 把 ER 实例共享给目标账号（`ram_principals` 填对方账号 ID，`account_id` 填本账号），接收方用 `huaweicloud_ram_resource_share_accepter` 接受。
3. 终端节点 DNS 共享由 Hub 的 CoreDNS 承担，无需额外共享解析规则。

## 可选：原生 DNS 条件转发

若希望去掉 CoreDNS ECS（免出网安装、免一台 ECS），可改用华为云原生条件转发。需要先创建 DNS 解析器出站终端节点（`huaweicloud_dns_resolver_endpoint`），再把转发规则挂到该终端节点上：

```hcl
# 出站终端节点（子网内选择可用 IP 作为 DNS 出口）
resource "huaweicloud_dns_resolver_endpoint" "outbound" {
  name      = "${var.name_prefix}-resolver-out"
  direction = "OUTBOUND"
  vpc_id    = huaweicloud_vpc.hub.id
  ip_addresses {
    subnet_id = huaweicloud_vpc_subnet.hub[0].id
  }
}

# 条件转发规则：把云服务域名转发到 Hub 内置 DNS
resource "huaweicloud_dns_resolver_rule" "cloud" {
  name        = "${var.name_prefix}-fwd"
  domain_name = "myhuaweicloud.com"
  endpoint_id = huaweicloud_dns_resolver_endpoint.outbound.id
  rule_type   = "FORWARD"
  ip_addresses {
    ip_address = "100.125.0.250"
  }
}

# 关联 Spoke VPC，使 Spoke 的云服务域名查询走该转发规则
resource "huaweicloud_dns_resolver_rule_associate" "spoke" {
  resolver_rule_id = huaweicloud_dns_resolver_rule.cloud.id
  vpc_id           = huaweicloud_vpc.spoke.id
}
```

> 该原生能力按 region 可用性可能不同；启用前请在目标 region 控制台确认 `dns_resolver_rule` 支持。
