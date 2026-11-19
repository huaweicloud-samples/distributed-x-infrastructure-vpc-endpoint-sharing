# ============================================================================
# Spoke（工作负载 VPC）
# Spoke VPC 经 ER 连到 Hub，关联 OBS 网关终端节点，
# 并把子网 dns_list 指向 Hub 的 CoreDNS，透明复用 Hub 的接口终端节点。
# ============================================================================

resource "huaweicloud_vpc" "spoke" {
  name = "${var.name_prefix}-spoke"
  cidr = var.spoke_cidr
}

resource "huaweicloud_vpc_subnet" "spoke" {
  for_each          = { for i, c in var.spoke_subnet_cidrs : i => c }
  name              = "${var.name_prefix}-spoke-private-${each.key}"
  cidr              = each.value
  gateway_ip        = cidrhost(each.value, 1)
  vpc_id            = huaweicloud_vpc.spoke.id
  availability_zone = var.availability_zones[each.key]
  # dns_list 首位指向 Hub 的 CoreDNS（由其转发云服务私有域名到 Hub 内置 DNS），
  # 次位保留华为云内置 DNS 兜底。
  dns_list = [
    huaweicloud_compute_instance.coredns.network[0].fixed_ip_v4,
    "100.125.0.250",
  ]
}

# --- Spoke 验证实例安全组：仅放通入站 SSH（来自 Hub 堡垒机），出方向沿用默认 allow-all ---
resource "huaweicloud_networking_secgroup" "spoke_instance" {
  name        = "${var.name_prefix}-spoke-instance"
  description = "SG for spoke test instance (SSH from hub bastion)"
}

resource "huaweicloud_networking_secgroup_rule" "spoke_ingress_ssh" {
  security_group_id = huaweicloud_networking_secgroup.spoke_instance.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  ports             = "22"
  remote_ip_prefix  = var.hub_cidr
}

# --- OBS 网关型终端节点（可选，默认关闭）----------------------------------
# 网关型终端节点指向 OBS，自动在关联路由表注入 OBS 路由，无需 network_id。
# ⚠️ cn-north-4 公共服务中 OBS 网关仅有特殊局点（lz/ies 后缀），实测创建
# 全部 failed；标准 OBS 网关服务需按目标 region 控制台确认。默认关闭，
# 需要时置 enable_obs_gateway=true 并按 region 调整 obs_public_service_name。
data "huaweicloud_vpcep_public_services" "obs" {
  count        = var.enable_obs_gateway ? 1 : 0
  service_name = var.obs_public_service_name
}

resource "huaweicloud_vpcep_endpoint" "obs_gateway" {
  count       = var.enable_obs_gateway ? 1 : 0
  service_id  = data.huaweicloud_vpcep_public_services.obs[0].services[0].id
  vpc_id      = huaweicloud_vpc.spoke.id
  routetables = [data.huaweicloud_vpc_route_table.spoke_default.id]
}

# --- Spoke 验证用 ECS -------------------------------------------------------
# 验证实例不分配公网 IP，经 Hub 堡垒机/跳板以密钥对登录。
resource "huaweicloud_compute_instance" "test" {
  name               = "${var.name_prefix}-spoke-test"
  image_id           = data.huaweicloud_images_image.ubuntu.id
  flavor_id          = var.test_ecs_flavor
  key_pair           = var.key_pair
  availability_zone  = var.availability_zones[0]
  security_group_ids = [huaweicloud_networking_secgroup.spoke_instance.id]
  system_disk_type   = var.ecs_system_disk_type
  system_disk_size   = var.ecs_system_disk_size

  network {
    uuid = huaweicloud_vpc_subnet.spoke[0].id
  }
}
