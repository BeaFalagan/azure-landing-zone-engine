locals {
  # Same catalog the engine uses: allowed regions, environments and assignable roles.
  catalog = yamldecode(file("${path.module}/../engine/catalog/catalog.yaml"))

  region = local.catalog.regions[var.location].short

  names = {
    resource_group  = "rg-${var.organization}-lzengine-${local.region}"
    storage_account = "st${var.organization}lzstate${local.region}"
    identity        = { for kind in ["plan", "apply"] : kind => "id-${var.organization}-lzengine-${kind}-${local.region}" }
  }

  tags = merge(var.tags, {
    managed_by = "terraform-bootstrap"
    source     = "bootstrap"
  })

  # Containers: project states (<bu>/<project>/<env>.tfstate) and the bootstrap state itself,
  # kept apart so the pipeline identities have no access to the bootstrap state.
  state_containers = {
    projects  = "tfstate"
    bootstrap = "bootstrap"
  }

  # GitHub OIDC subjects (default subject format, no customization).
  # plan:  pull requests and pushes to main (the plan before approval).
  # apply: only jobs running in a protected GitHub environment.
  github_issuer   = "https://token.actions.githubusercontent.com"
  github_audience = "api://AzureADTokenExchange"
  federated_credentials = merge(
    {
      "plan-pull-request" = { identity = "plan", subject = "repo:${var.github_repository}:pull_request" }
      "plan-main"         = { identity = "plan", subject = "repo:${var.github_repository}:ref:refs/heads/main" }
    },
    {
      for env in var.environments : "apply-${var.github_environment_prefix}${env}" => {
        identity = "apply"
        subject  = "repo:${var.github_repository}:environment:${var.github_environment_prefix}${env}"
      }
    },
  )

  landing_zones_scope = "/providers/Microsoft.Management/managementGroups/${var.landing_zones_management_group_id}"

  # ABAC: the apply identity may only create/delete assignments of catalog roles, and only to groups.
  allowed_role_guids = join(", ", sort(values(local.catalog.roles)))
  rbac_admin_condition = trimspace(<<-EOT
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
     )
     OR
     (
      @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.allowed_role_guids}}
      AND
      @Request[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'Group'}
     )
    )
    AND
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
     )
     OR
     (
      @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.allowed_role_guids}}
      AND
      @Resource[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'Group'}
     )
    )
    EOT
  )

  hub_ids = toset(var.hub_virtual_network_ids)

  # Azure role assignments, keyed by "<identity>/<purpose>". Scopes are known at plan time
  # except the state container, which is handled by its own resource.
  azure_role_assignments = merge(
    {
      "plan/landing-zones-reader" = { identity = "plan", role = "Reader", scope = local.landing_zones_scope }
      "plan/log-analytics-reader" = { identity = "plan", role = "Reader", scope = var.log_analytics_workspace_id }
      "apply/landing-zones-contributor" = {
        identity = "apply", role = "Contributor", scope = local.landing_zones_scope
      }
      "apply/log-analytics-diagnostics" = {
        identity = "apply", role = "Monitoring Contributor", scope = var.log_analytics_workspace_id
      }
    },
    { for id in local.hub_ids : "plan/hub-reader/${basename(id)}" => { identity = "plan", role = "Reader", scope = id } },
    { for id in local.hub_ids : "apply/hub-peering/${basename(id)}" => { identity = "apply", role = "Network Contributor", scope = id } },
  )

  state_role_assignments = {
    plan  = "Storage Blob Data Reader"
    apply = "Storage Blob Data Contributor"
  }

  # Microsoft Graph application permissions (require admin consent, granted here).
  # The engine creates Entra ID groups and becomes their owner, which lets it manage
  # membership without GroupMember.ReadWrite.All.
  msgraph_client_id = "00000003-0000-0000-c000-000000000000"
  graph_app_roles = {
    plan  = ["Group.Read.All", "User.Read.All"]
    apply = ["Group.Create", "User.Read.All"]
  }
  graph_assignments = merge([
    for identity, roles in local.graph_app_roles : {
      for role in roles : "${identity}/${role}" => { identity = identity, role = role }
    }
  ]...)
}
