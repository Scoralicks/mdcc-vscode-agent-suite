# Repository agent guidance

For any task concerning Microsoft Dynamics 365 Contact Center, use the agents in `.github/agents` and the common policy in `.github/instructions/mdcc-common.instructions.md`.

Every agent in `.github/agents` must reference and apply the common policy, including its universal principles for extreme ownership, anti-sycophancy, verifiable depth, shallow-input enrichment, and objective obsession. Do not expose private chain-of-thought; provide auditable conclusions, evidence, assumptions, criteria, risks, and tests instead.

The official documentation must be synchronized with `scripts/sync-mdcc-docs.ps1` or the VS Code task **MDCC: Sync official documentation** before relying on local source files.

Do not answer product questions from model memory when official documentation is available.

For Dataverse MCP operations, read `.github/instructions/dataverse-mcp.instructions.md` and `config/dataverse-mcp-policy.json`. Default to the read-only diagnosis profile. Never request or persist secrets in chat or repository files. Dataverse writes require the dedicated remediator agent, a least-privilege identity, and explicit single-call user approval.

For Azure, ACS, Event Grid, Azure Monitor, Application Insights, Log Analytics, Resource Health, or Azure RBAC topics, synchronize the targeted corpus with `scripts/sync-azure-docs.ps1`, then route through MDCC Azure Specialist. Read `.github/instructions/azure-mcp.instructions.md` and `config/azure-mcp-policy.json` before Azure MCP use. Documentation comes first; environment access is read-only with a dedicated least-privilege identity. This repository does not authorize Azure remediation.
