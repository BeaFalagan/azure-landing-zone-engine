# network

Red de un proyecto conectada al hub de su entorno:

- **VNet** con DNS propios o los de Azure.
- **Subnets** sin salida implícita a Internet (`default_outbound_access_enabled = false`), con service endpoints y delegación opcionales.
- **Un NSG por subnet** y una regla por recurso (`azurerm_network_security_rule`), de modo que cambiar una regla aparece como un único cambio en el plan.
- **Tabla de rutas** con `0.0.0.0/0` hacia el firewall del hub, solo si el hub declara `firewall_private_ip`. La propagación BGP se desactiva para que todo el tráfico de salida pase por el firewall.
- **Peering en los dos sentidos.** El lado hub se crea con el provider `azurerm.hub`, en la suscripción de conectividad, y antes que el lado del proyecto, porque `use_remote_gateways` exige que el hub ya tenga `allow_gateway_transit`.

## Reglas NSG

| Campo | Valores |
|---|---|
| `direction` / `access` / `protocol` | `inbound`/`outbound`, `allow`/`deny`, `tcp`/`udp`/`icmp`/`any` |
| `source` / `destination` | CIDR, service tag (`VirtualNetwork`, `AzureLoadBalancer`, `Internet`), `*`, `@subnet` (la propia subnet, valor por defecto de `destination`) o `@hub` (rangos del hub) |
| `ports` | `["443"]`, `["8080-8090"]`, `["*"]` (por defecto) |
| `priority` | Opcional. Por defecto `100 + 10 × posición` en la lista |

Azure solo admite service tags en los argumentos en singular (`source_address_prefix`); el módulo usa el singular cuando hay un valor y el plural cuando hay varios, como en `@hub` con varios rangos.

## Validaciones

Antes del plan comprueba:
- los CIDR están escritos como dirección de red (`10.48.48.0/24`, no `10.48.48.5/24`);
- las subnets son `/29` o mayores, están dentro del `address_space` y no se solapan;
- la VNet no se solapa con el hub;
- los nombres de regla son únicos;
- no hay prioridades repetidas por dirección y están entre 100 y 4096;
- `@hub` solo se usa si hay hub.

## Providers

El módulo declara `configuration_aliases = [azurerm.hub]`. Sin hub, se pasa el provider por defecto en los dos alias. Por ese alias no se puede ejecutar `terraform validate` directamente en esta carpeta: se valida a través de `examples/basic`.

## Ejemplo

Ver [examples/basic](examples/basic/main.tf).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.17.0 |
| azurerm | >= 5.12, < 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| azurerm | >= 5.12, < 6.0 |
| azurerm.hub | >= 5.12, < 6.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_network_security_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_network_security_rule.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_rule) | resource |
| [azurerm_route_table.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/route_table) | resource |
| [azurerm_subnet.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_network_security_group_association.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_subnet_route_table_association.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_route_table_association) | resource |
| [azurerm_virtual_network.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |
| [azurerm_virtual_network_peering.from_hub](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network_peering) | resource |
| [azurerm_virtual_network_peering.to_hub](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network_peering) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| address\_space | VNet address space (IPv4 CIDRs written as network addresses). | `list(string)` | n/a | yes |
| location | Azure region. | `string` | n/a | yes |
| name | Virtual network name. | `string` | n/a | yes |
| resource\_group\_name | Resource group of the network resources. | `string` | n/a | yes |
| dns\_servers | Custom DNS servers. Empty list = Azure-provided DNS. | `list(string)` | `[]` | no |
| hub | Hub to peer with. null = isolated VNet (no peering, no route to a firewall). | <pre>object({<br/>    virtual_network_id  = string<br/>    address_space       = list(string)<br/>    firewall_private_ip = optional(string)<br/>    use_remote_gateways = optional(bool, false)<br/>  })</pre> | `null` | no |
| peering\_names | Peering names (to\_hub in this VNet, from\_hub in the hub VNet). Required when hub is set. | <pre>object({<br/>    to_hub   = string<br/>    from_hub = string<br/>  })</pre> | `null` | no |
| route\_table\_name | Name of the route table created when the hub has a firewall (default route to the firewall). | `string` | `null` | no |
| subnets | Subnets by short name. Each subnet gets its own NSG.<br/>NSG rule source/destination accept a CIDR, a service tag (VirtualNetwork, AzureLoadBalancer, Internet), "*",<br/>"@subnet" (this subnet) or "@hub" (hub address space). Rule priority defaults to 100 + 10 x position in the list. | <pre>map(object({<br/>    name              = string<br/>    nsg_name          = string<br/>    prefix            = string<br/>    service_endpoints = optional(list(string), [])<br/>    delegation = optional(object({<br/>      service = string<br/>      actions = list(string)<br/>    }))<br/>    nsg_rules = optional(list(object({<br/>      name        = string<br/>      direction   = string<br/>      access      = string<br/>      protocol    = string<br/>      source      = string<br/>      destination = optional(string, "@subnet")<br/>      ports       = optional(list(string), ["*"])<br/>      priority    = optional(number)<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| tags | Tags for every network resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| network\_security\_group\_ids | NSG IDs by subnet short name. |
| peering\_ids | Peering IDs (to\_hub, from\_hub), or null when not peered. |
| route\_table\_id | Route table ID, or null when the hub has no firewall. |
| subnet\_ids | Subnet IDs by short name. |
| virtual\_network | Virtual network (id, name, address\_space). |
<!-- END_TF_DOCS -->
