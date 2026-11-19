# ============================================================================
# Hub（共享服务 VPC）
# 在 Hub VPC 内托管接口型终端节点 + CoreDNS 转发器，并经 ER 与 Spoke 互联。
# ============================================================================
# 公共镜像数据源统一放在 infra/main.tf（Hub 与 Spoke 的 ECS 共用）。

resource "huaweicloud_vpc" "hub" {
  name = "${var.name_prefix}-hub"
  cidr = var.hub_cidr
  # 华为云 VPC 默认开启 DNS 主机名解析
}

resource "huaweicloud_vpc_subnet" "hub" {
  for_each          = { for i, c in var.hub_subnet_cidrs : i => c }
  name              = "${var.name_prefix}-hub-private-${each.key}"
  cidr              = each.value
  gateway_ip        = cidrhost(each.value, 1)
  vpc_id            = huaweicloud_vpc.hub.id
  availability_zone = var.availability_zones[each.key]
}

# --- 终端节点安全组：仅放通入站 443（接口终端节点服务对象） -------------------
# 注意：华为云创建安全组时默认自带 allow-all egress，勿再显式建全放出方向规则
# （否则报 conflict）。
resource "huaweicloud_networking_secgroup" "endpoints" {
  name        = "${var.name_prefix}-hub-endpoints"
  description = "Security group for VPC endpoints in hub"
}

resource "huaweicloud_networking_secgroup_rule" "endpoints_ingress_443" {
  security_group_id = huaweicloud_networking_secgroup.endpoints.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  ports             = "443"
  remote_ip_prefix  = "10.0.0.0/21"
}

# --- CoreDNS 安全组：放通入站 DNS（53/tcp + 53/udp），来自 Hub+Spoke 网段 ----
resource "huaweicloud_networking_secgroup" "coredns" {
  name        = "${var.name_prefix}-hub-coredns"
  description = "Security group for CoreDNS forwarder in hub"
}

resource "huaweicloud_networking_secgroup_rule" "coredns_ingress_dns_tcp" {
  security_group_id = huaweicloud_networking_secgroup.coredns.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  ports             = "53"
  remote_ip_prefix  = "10.0.0.0/21"
}

resource "huaweicloud_networking_secgroup_rule" "coredns_ingress_dns_udp" {
  security_group_id = huaweicloud_networking_secgroup.coredns.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  ports             = "53"
  remote_ip_prefix  = "10.0.0.0/21"
}

# --- Hub 托管的接口型终端节点 ----------------------------------------------
# 华为云发布的云服务型终端节点按 region 查询 service_id 后填入
# var.interface_endpoint_service_ids。enable_dns 自动注入私有域名解析。
resource "huaweicloud_vpcep_endpoint" "interface" {
  for_each   = toset(var.interface_endpoint_service_ids)
  service_id = each.value
  vpc_id     = huaweicloud_vpc.hub.id
  network_id = huaweicloud_vpc_subnet.hub[0].id # 接口终端节点的子网（network_id 即子网 ID）
  enable_dns = true
}

# --- CoreDNS 转发器 ---------------------------------------------------------
# 运行在 Hub VPC：把云服务的私有域名查询转发到 Hub 内置 DNS（100.125.0.250），
# 由其解析出接口终端节点的私有 IP；Spoke 子网 dns_list 首位指向本 ECS 私有 IP。
resource "huaweicloud_compute_instance" "coredns" {
  name               = "${var.name_prefix}-coredns"
  image_id           = data.huaweicloud_images_image.ubuntu.id
  flavor_id          = var.coredns_flavor
  key_pair           = var.key_pair
  availability_zone  = var.availability_zones[0]
  security_group_ids = [huaweicloud_networking_secgroup.coredns.id]
  system_disk_type   = var.ecs_system_disk_type
  system_disk_size   = var.ecs_system_disk_size

  user_data = <<-EOT
    #!/bin/bash
    set -e
    # CoreDNS 静态二进制安装（需出网；私有环境请预置到自定义镜像或启用 NAT）
    CORE_DNS_VER=1.11.1
    if ! command -v /usr/local/bin/coredns >/dev/null 2>&1; then
      curl -fsSL -o /tmp/coredns.tgz "https://github.com/coredns/coredns/releases/download/v$${CORE_DNS_VER}/coredns_$${CORE_DNS_VER}_linux_amd64.tgz"
      tar -xzf /tmp/coredns.tgz -C /tmp
      install -m 0755 /tmp/coredns /usr/local/bin/coredns
    fi
    mkdir -p /etc/coredns
    cat > /etc/coredns/Corefile <<'CORE'
    .:53 {
        forward . 100.125.0.250
        cache 30
        log
    }
    CORE
    cat > /etc/systemd/system/coredns.service <<'UNIT'
    [Unit]
    Description=CoreDNS forwarder
    After=network.target
    [Service]
    ExecStart=/usr/local/bin/coredns -conf /etc/coredns/Corefile
    Restart=always
    [Install]
    WantedBy=multi-user.target
    UNIT
    systemctl enable --now coredns
  EOT

  network {
    uuid = huaweicloud_vpc_subnet.hub[0].id
  }
}

# --- 可选：NAT 网关为 Hub 私有子网提供出网（CoreDNS 引导 / ECS 出网验证） ----
resource "huaweicloud_nat_gateway" "hub" {
  count     = var.enable_nat_gateway ? 1 : 0
  name      = "${var.name_prefix}-hub-nat"
  spec      = "1"
  vpc_id    = huaweicloud_vpc.hub.id
  subnet_id = huaweicloud_vpc_subnet.hub[0].id
}

# 0.0.0.0/0 -> NAT（type=nat，nexthop=NAT 网关 ID）；与 ER 私网路由前缀不冲突。
resource "huaweicloud_vpc_route" "hub_internet" {
  count          = var.enable_nat_gateway ? 1 : 0
  vpc_id         = huaweicloud_vpc.hub.id
  route_table_id = data.huaweicloud_vpc_route_table.hub_default.id
  destination    = "0.0.0.0/0"
  type           = "nat"
  nexthop        = huaweicloud_nat_gateway.hub[0].id
}
