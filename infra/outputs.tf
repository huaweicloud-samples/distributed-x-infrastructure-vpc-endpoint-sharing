output "hub_vpc_id" {
  description = "Hub VPC ID"
  value       = huaweicloud_vpc.hub.id
}

output "spoke_vpc_id" {
  description = "Spoke VPC ID"
  value       = huaweicloud_vpc.spoke.id
}

output "er_instance_id" {
  description = "企业路由器（ER）实例 ID"
  value       = huaweicloud_er_instance.this.id
}

output "coredns_private_ip" {
  description = "CoreDNS ECS 私有 IP，Spoke 子网 dns_list 首位即指向它"
  value       = huaweicloud_compute_instance.coredns.network[0].fixed_ip_v4
}

output "obs_gateway_endpoint_id" {
  description = "OBS 网关型终端节点 ID（enable_obs_gateway=false 时为空）"
  value       = var.enable_obs_gateway ? huaweicloud_vpcep_endpoint.obs_gateway[0].id : ""
}

output "interface_endpoint_ids" {
  description = "Hub 托管的接口型终端节点 ID 列表"
  value       = [for ep in huaweicloud_vpcep_endpoint.interface : ep.id]
}
