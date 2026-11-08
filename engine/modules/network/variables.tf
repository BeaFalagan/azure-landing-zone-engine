variable "name" {
  description = "Virtual network name."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][-a-zA-Z0-9._]{0,62}[a-zA-Z0-9_]$", var.name))
    error_message = "name is not a valid virtual network name."
  }
}

variable "resource_group_name" {
  description = "Resource group of the network resources."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "tags" {
  description = "Tags for every network resource."
  type        = map(string)
  default     = {}
}

variable "address_space" {
  description = "VNet address space (IPv4 CIDRs written as network addresses)."
  type        = list(string)

  validation {
    condition     = length(var.address_space) > 0 && alltrue([for c in var.address_space : try(cidrhost(c, 0) == split("/", c)[0], false)])
    error_message = "address_space needs at least one valid CIDR written as a network address (e.g. 10.48.48.0/20, not 10.48.50.0/20)."
  }

  validation {
    condition = alltrue(flatten([
      for i, a in var.address_space : [
        for j, b in var.address_space : i >= j || try(
          cidrhost(format("%s/%d", cidrhost(a, 0), min(tonumber(split("/", a)[1]), tonumber(split("/", b)[1]))), 0) !=
          cidrhost(format("%s/%d", cidrhost(b, 0), min(tonumber(split("/", a)[1]), tonumber(split("/", b)[1]))), 0),
        false)
      ]
    ]))
    error_message = "address_space ranges overlap with each other."
  }
}

variable "dns_servers" {
  description = "Custom DNS servers. Empty list = Azure-provided DNS."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for ip in var.dns_servers : can(cidrhost("${ip}/32", 0))])
    error_message = "dns_servers must be IPv4 addresses."
  }
}

variable "subnets" {
  description = <<-EOT
    Subnets by short name. Each subnet gets its own NSG.
    NSG rule source/destination accept a CIDR, a service tag (VirtualNetwork, AzureLoadBalancer, Internet), "*",
    "@subnet" (this subnet) or "@hub" (hub address space). Rule priority defaults to 100 + 10 x position in the list.
  EOT
  type = map(object({
    name              = string
    nsg_name          = string
    prefix            = string
    service_endpoints = optional(list(string), [])
    delegation = optional(object({
      service = string
      actions = list(string)
    }))
    nsg_rules = optional(list(object({
      name        = string
      direction   = string
      access      = string
      protocol    = string
      source      = string
      destination = optional(string, "@subnet")
      ports       = optional(list(string), ["*"])
      priority    = optional(number)
    })), [])
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for s in values(var.subnets) : try(cidrhost(s.prefix, 0) == split("/", s.prefix)[0] && tonumber(split("/", s.prefix)[1]) <= 29, false)])
    error_message = "Each subnet prefix must be a valid CIDR written as a network address, /29 or larger."
  }

  validation {
    condition = alltrue([
      for s in values(var.subnets) : anytrue([
        for space in var.address_space : try(
          tonumber(split("/", s.prefix)[1]) >= tonumber(split("/", space)[1]) &&
          cidrhost(format("%s/%s", cidrhost(s.prefix, 0), split("/", space)[1]), 0) == cidrhost(space, 0),
        false)
      ])
    ])
    error_message = "Every subnet prefix must be inside the VNet address_space."
  }

  validation {
    condition = alltrue(flatten([
      for i, a in values(var.subnets) : [
        for j, b in values(var.subnets) : i >= j || try(
          cidrhost(format("%s/%d", cidrhost(a.prefix, 0), min(tonumber(split("/", a.prefix)[1]), tonumber(split("/", b.prefix)[1]))), 0) !=
          cidrhost(format("%s/%d", cidrhost(b.prefix, 0), min(tonumber(split("/", a.prefix)[1]), tonumber(split("/", b.prefix)[1]))), 0),
        false)
      ]
    ]))
    error_message = "Subnet prefixes overlap with each other."
  }

  validation {
    condition = alltrue(flatten([
      for s in values(var.subnets) : [
        for r in s.nsg_rules : (
          contains(["inbound", "outbound"], r.direction) &&
          contains(["allow", "deny"], r.access) &&
          contains(["tcp", "udp", "icmp", "any"], r.protocol) &&
          can(regex("^[a-z][a-z0-9-]{1,62}$", r.name)) &&
          length(r.ports) > 0 &&
          alltrue([for p in r.ports : can(regex("^(\\*|[0-9]{1,5}(-[0-9]{1,5})?)$", p))])
        )
      ]
    ]))
    error_message = "NSG rules: direction inbound|outbound, access allow|deny, protocol tcp|udp|icmp|any, lowercase name, ports like \"443\", \"8080-8090\" or \"*\"."
  }

  validation {
    condition = alltrue([
      for s in values(var.subnets) : length(distinct([for r in s.nsg_rules : r.name])) == length(s.nsg_rules)
    ])
    error_message = "NSG rule names must be unique within a subnet."
  }

  validation {
    condition = alltrue(flatten([
      for s in values(var.subnets) : [
        for direction in ["inbound", "outbound"] : (
          length([for i, r in s.nsg_rules : coalesce(r.priority, 100 + 10 * i) if r.direction == direction]) ==
          length(distinct([for i, r in s.nsg_rules : coalesce(r.priority, 100 + 10 * i) if r.direction == direction]))
        )
      ]
    ]))
    error_message = "Two NSG rules of the same subnet and direction end up with the same priority. Remove the explicit priority or choose another value."
  }

  validation {
    condition     = alltrue(flatten([for s in values(var.subnets) : [for i, r in s.nsg_rules : coalesce(r.priority, 100 + 10 * i) >= 100 && coalesce(r.priority, 100 + 10 * i) <= 4096]]))
    error_message = "NSG rule priorities must be between 100 and 4096 (too many rules in one subnet?)."
  }

  validation {
    condition     = var.hub != null || !anytrue(flatten([for s in values(var.subnets) : [for r in s.nsg_rules : r.source == "@hub" || r.destination == "@hub"]]))
    error_message = "NSG rules use the hub alias, but the network is not peered to a hub."
  }
}

variable "hub" {
  description = "Hub to peer with. null = isolated VNet (no peering, no route to a firewall)."
  type = object({
    virtual_network_id  = string
    address_space       = list(string)
    firewall_private_ip = optional(string)
    use_remote_gateways = optional(bool, false)
  })
  default = null

  validation {
    condition     = var.hub == null || can(regex("^/subscriptions/[0-9a-f-]{36}/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+$", var.hub.virtual_network_id))
    error_message = "hub.virtual_network_id must be a virtual network resource ID."
  }

  validation {
    condition = var.hub == null || alltrue(flatten([
      for a in var.address_space : [
        for b in try(var.hub.address_space, []) : try(
          cidrhost(format("%s/%d", cidrhost(a, 0), min(tonumber(split("/", a)[1]), tonumber(split("/", b)[1]))), 0) !=
          cidrhost(format("%s/%d", cidrhost(b, 0), min(tonumber(split("/", a)[1]), tonumber(split("/", b)[1]))), 0),
        false)
      ]
    ]))
    error_message = "The VNet address_space overlaps with the hub address space."
  }
}

variable "peering_names" {
  description = "Peering names (to_hub in this VNet, from_hub in the hub VNet). Required when hub is set."
  type = object({
    to_hub   = string
    from_hub = string
  })
  default = null

  validation {
    condition     = var.hub == null || var.peering_names != null
    error_message = "peering_names is required when hub is set."
  }
}

variable "route_table_name" {
  description = "Name of the route table created when the hub has a firewall (default route to the firewall)."
  type        = string
  default     = null

  validation {
    condition     = try(var.hub.firewall_private_ip, null) == null || var.route_table_name != null
    error_message = "route_table_name is required when the hub has a firewall_private_ip."
  }
}
