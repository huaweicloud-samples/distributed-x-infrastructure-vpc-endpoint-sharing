variable "region" {
  description = "华为云区域，例如 cn-north-4"
  type        = string
  default     = "cn-north-4"
}

variable "name_prefix" {
  description = "资源命名前缀，便于区分与清理"
  type        = string
  default     = "vpc-ep-share"
}

variable "hub_cidr" {
  description = "Hub（共享服务）VPC 的 CIDR"
  type        = string
  default     = "10.0.0.0/22"
}

variable "spoke_cidr" {
  description = "Spoke（工作负载）VPC 的 CIDR"
  type        = string
  default     = "10.0.4.0/24"
}

variable "hub_subnet_cidrs" {
  description = "Hub VPC 三个私有子网 CIDR，与 availability_zones 一一对应"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
}

variable "spoke_subnet_cidrs" {
  description = "Spoke VPC 三个私有子网 CIDR，与 availability_zones 一一对应"
  type        = list(string)
  default     = ["10.0.4.0/26", "10.0.4.64/26", "10.0.4.128/26"]
}

variable "availability_zones" {
  description = "可用区列表；前三个用于 Hub/Spoke 子网（一一对应），ER 使用第 1 与第 4 个（cn-north-4b/c 偶发 ER 服务器不足）"
  type        = list(string)
  default     = ["cn-north-4a", "cn-north-4b", "cn-north-4c", "cn-north-4g"]
}

variable "er_asn" {
  description = "企业路由器 ER 的 ASN"
  type        = number
  default     = 64512
}

variable "interface_endpoint_service_ids" {
  description = "Hub 要托管的「接口型」终端节点服务 ID 列表（华为云发布的云服务型终端节点，按 region 在控制台 VPC > 终端节点服务 > 公共终端节点服务 查询）。为空则不创建接口终端节点，仅保留 OBS 网关终端节点与 CoreDNS 转发骨架。"
  type        = list(string)
  default     = []
}

variable "obs_public_service_name" {
  description = "OBS 公共终端节点服务的名称，用于自动发现网关型终端节点服务 ID。绝大多数 region 为 OBS；个别 region 可能带后缀，请按控制台实际名称调整。"
  type        = string
  default     = "OBS"
}

variable "enable_obs_gateway" {
  description = "是否创建 OBS 网关型终端节点。cn-north-4 公共服务中 OBS 网关仅有特殊局点（lz/ies 后缀）且实测创建失败，默认关闭；如需开启请先按 region 在控制台确认存在可用的标准 OBS 网关服务。"
  type        = bool
  default     = false
}

variable "coredns_flavor" {
  description = "CoreDNS ECS 规格（显式指定）"
  type        = string
  default     = "s6.small.1"
}

variable "test_ecs_flavor" {
  description = "Spoke 验证用 ECS 规格（显式指定）"
  type        = string
  default     = "s6.small.1"
}

variable "ecs_system_disk_type" {
  description = "ECS 系统盘类型，必须显式指定（华为云侧必填，规格直接决定磁盘性能等级）"
  type        = string
  default     = "GPSSD"
}

variable "ecs_system_disk_size" {
  description = "ECS 系统盘大小（GB）"
  type        = number
  default     = 40
}

variable "ecs_image_name_regex" {
  description = "ECS 镜像名称正则，必须首尾锚定以避免命中 GPU 变体"
  type        = string
  default     = "^Ubuntu 22.04 server 64bit$"
}

variable "key_pair" {
  description = "ECS 登录密钥对名称（需在目标 region 预先创建）；验证实例不分配公网 IP，经堡垒机登录。"
  type        = string
}

variable "enable_nat_gateway" {
  description = "是否创建 NAT 网关为 Hub 私有子网提供出网。CoreDNS 首次引导安装、以及 ECS 出网验证需要出网；设为 false 时请在自定义镜像中预置 CoreDNS，或改用华为云原生 dns_resolver_rule（见 docs/architecture.md）。"
  type        = bool
  default     = false
}

variable "ram_principals" {
  description = "跨账号共享 ER 的 RAM 主体（账号 ID 列表）。为空表示单账号演示（不创建 RAM 共享）；非空则把这些账号加入 ER 共享。"
  type        = list(string)
  default     = []
}

variable "account_id" {
  description = "本账号 ID，仅在 ram_principals 非空（跨账号）时用于构造 ER 资源 URN"
  type        = string
  default     = ""
}
