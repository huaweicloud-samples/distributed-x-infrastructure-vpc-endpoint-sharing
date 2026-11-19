# ============================================================================
# 企业路由器 ER
# 同一 region 内互联 Hub / Spoke VPC。由于华为云每 VPC 仅 1 张默认路由表
# （配额=1），这里只用默认路由表、往里追路由，不新建表。
# ============================================================================

# 每个 VPC 仅含默认路由表（我们未创建自定义表），单凭 vpc_id 即可取到默认表。
data "huaweicloud_vpc_route_table" "hub_default" {
  vpc_id = huaweicloud_vpc.hub.id
}

data "huaweicloud_vpc_route_table" "spoke_default" {
  vpc_id = huaweicloud_vpc.spoke.id
}

resource "huaweicloud_er_instance" "this" {
  name = "${var.name_prefix}-er"
  asn  = var.er_asn
  # 使用 a+g 两个可用区（cn-north-4b/c 偶发服务器不足，ER.04009005）
  availability_zones         = [var.availability_zones[0], var.availability_zones[3]]
  enable_default_association = true
  enable_default_propagation = true
}

resource "huaweicloud_er_vpc_attachment" "hub" {
  instance_id = huaweicloud_er_instance.this.id
  vpc_id      = huaweicloud_vpc.hub.id
  subnet_id   = huaweicloud_vpc_subnet.hub[0].id
  name        = "${var.name_prefix}-hub-attach"
}

resource "huaweicloud_er_vpc_attachment" "spoke" {
  instance_id = huaweicloud_er_instance.this.id
  vpc_id      = huaweicloud_vpc.spoke.id
  subnet_id   = huaweicloud_vpc_subnet.spoke[0].id
  name        = "${var.name_prefix}-spoke-attach"
}

# 显式私网路由：Hub/Spoke 互指，下一跳为企业路由器（type=er）。
# 与 OBS 网关终端节点自动注入的 OBS 路由、可选 NAT 的 0.0.0.0/0 路由前缀均不冲突。
resource "huaweicloud_vpc_route" "hub_to_spoke" {
  vpc_id         = huaweicloud_vpc.hub.id
  route_table_id = data.huaweicloud_vpc_route_table.hub_default.id
  destination    = var.spoke_cidr
  type           = "er"
  nexthop        = huaweicloud_er_instance.this.id
}

resource "huaweicloud_vpc_route" "spoke_to_hub" {
  vpc_id         = huaweicloud_vpc.spoke.id
  route_table_id = data.huaweicloud_vpc_route_table.spoke_default.id
  destination    = var.hub_cidr
  type           = "er"
  nexthop        = huaweicloud_er_instance.this.id
}

# --- 可选：跨账号共享 ER ----------------------------------------------------
# 单账号演示默认不创建（ram_principals 为空）。跨账号生产部署时填入目标账号 ID，
# 并把本账号 ER 通过华为云 RAM 共享出去；接收方用 huaweicloud_ram_resource_share_accepter 接受。
# 注意：resource_urns 的 URN 格式需按账号实际校验（region / account_id / 资源类型段）。
resource "huaweicloud_ram_resource_share" "er" {
  count                     = length(var.ram_principals) > 0 ? 1 : 0
  name                      = "${var.name_prefix}-er-share"
  resource_urns             = ["urn:huaweicloud:er:${var.region}:${var.account_id}:enterprise-router/${huaweicloud_er_instance.this.id}"]
  principals                = var.ram_principals
  allow_external_principals = false
}
