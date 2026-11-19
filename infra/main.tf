# ============================================================================
# Terraform 入口：公共数据源与共享定义
# 本实践按角色拆分文件：
#   main.tf     —— 公共数据源（ECS 镜像），Hub 与 Spoke 共用
#   hub.tf      —— Hub（共享服务 VPC）：接口型终端节点 + CoreDNS 转发器 + 可选 NAT
#   spoke.tf    —— Spoke（工作负载 VPC）：子网 DNS 指向 + OBS 网关终端节点 + 验证实例
#   er.tf       —— 企业路由器 ER：VPC 连接、互指路由、可选 RAM 跨账号共享
#   variables.tf / outputs.tf / provider.tf / versions.tf
# ============================================================================

# 公共镜像数据源：Hub 的 CoreDNS 实例与 Spoke 的验证实例共用同一个 Ubuntu 镜像。
# name_regex 必须首尾锚定（^...$），否则会命中同系列的 GPU / 变体镜像。
data "huaweicloud_images_image" "ubuntu" {
  name_regex  = var.ecs_image_name_regex
  most_recent = true
}
