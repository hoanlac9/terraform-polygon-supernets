# Default Security Group of VPC should allow all traffic that's internal
resource "aws_default_security_group" "default" {
  vpc_id = var.devnet_id

  ingress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
    self      = true
  }
}

resource "aws_security_group" "all_node_instances" {
  name        = format("all-%s-%s-nodes", var.network_type, var.deployment_name)
  description = format("Configuration for the %s %s collection of instances", var.network_type, var.deployment_name)
  vpc_id      = var.devnet_id
}
resource "aws_security_group_rule" "all_node_instances" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = -1
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.all_node_instances.id
}

locals {
  all_primary_network_interface_ids = concat(var.non_validator_primary_network_interface_ids, var.validator_primary_network_interface_ids, var.fullnode_primary_network_interface_ids, var.geth_primary_network_interface_ids)
  p2p_primary_network_interface_ids = concat(var.non_validator_primary_network_interface_ids, var.validator_primary_network_interface_ids, var.fullnode_primary_network_interface_ids)
}

resource "aws_network_interface_sg_attachment" "all_node_instances" {
  count                = length(local.all_primary_network_interface_ids)
  security_group_id    = aws_security_group.all_node_instances.id
  network_interface_id = local.all_primary_network_interface_ids[count.index]
}

resource "aws_security_group" "open_rpc" {
  name        = "internal-rpc-access"
  description = "Allowing internal rpc"
  vpc_id      = var.devnet_id
}
resource "aws_security_group_rule" "open_rpc" {
  type              = "ingress"
  from_port         = var.http_rpc_port
  to_port           = var.http_rpc_port
  protocol          = "TCP"
  cidr_blocks       = var.network_acl
  security_group_id = aws_security_group.open_rpc.id
}
resource "aws_network_interface_sg_attachment" "open_rpc" {
  count                = length(local.p2p_primary_network_interface_ids)
  security_group_id    = aws_security_group.open_rpc.id
  network_interface_id = local.p2p_primary_network_interface_ids[count.index]
}

resource "aws_security_group" "open_http" {
  name        = "external-explorer-access"
  description = "Allowing explorer acccess"
  vpc_id      = var.devnet_id
}
resource "aws_security_group_rule" "open_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "TCP"
  cidr_blocks       = var.network_acl
  security_group_id = aws_security_group.open_http.id
}

resource "aws_security_group" "open_rpc_geth" {
  name        = "internal-geth-access"
  description = "configuration for geth access"
  vpc_id      = var.devnet_id
}
resource "aws_security_group_rule" "open_rpc_geth" {
  type              = "ingress"
  from_port         = var.rootchain_rpc_port
  to_port           = var.rootchain_rpc_port
  protocol          = "TCP"
  cidr_blocks       = var.network_acl
  security_group_id = aws_security_group.open_rpc_geth.id
}
resource "aws_network_interface_sg_attachment" "open_rpc_geth" {
  count                = var.geth_count
  security_group_id    = aws_security_group.open_rpc_geth.id
  network_interface_id = element(var.geth_primary_network_interface_ids, count.index)
}

resource "aws_security_group" "monitoring" {
  name        = "monitoring-sg"
  description = "configuration for monitoring tools access"
  vpc_id      = var.devnet_id
}
resource "aws_network_interface_sg_attachment" "monitoring" {
  count                = var.geth_count
  security_group_id    = aws_security_group.monitoring.id
  network_interface_id = element(var.monitoring_primary_network_interface_ids, count.index)
}
resource "aws_security_group_rule" "promeheus" {
  type              = "ingress"
  from_port         = 9090
  to_port           = 9090
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.monitoring.id
  description       = "Prometheus"
}

resource "aws_security_group_rule" "ssm_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = -1
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.monitoring.id
  description       = "ssm"
}

resource "aws_security_group_rule" "ssm_inbound" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = -1
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.monitoring.id
  description       = "ssm"
}

resource "aws_security_group" "explorer" {
  name        = "explorer-sg"
  description = "configuration for explorer tools access"
  vpc_id      = var.devnet_id
}
resource "aws_network_interface_sg_attachment" "explorer" {
  count                = var.geth_count
  security_group_id    = aws_security_group.explorer.id
  network_interface_id = element(var.explorer_primary_network_interface_ids, count.index)
}

resource "aws_security_group_rule" "explorer_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = -1
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.explorer.id
  description       = "ssm"
}

resource "aws_security_group_rule" "explorer_inbound" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = -1
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.explorer.id
  description       = "ssm"
}