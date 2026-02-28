# So What's the Difference?

You've probably seen other open-source tools in the AI and knowledge management space. Some are chat UIs, some are API gateways, some are workflow engines. Liteskill occupies a distinct position — a self-hosted, event-sourced AI platform that combines enterprise-grade access control with a full-featured chat experience, agentic pipelines, and native MCP tool integration.

Here's how it compares.

---

## Open WebUI

**What it is:** The most popular open-source ChatGPT-style interface. A Python/FastAPI backend with a Svelte frontend for chatting with Ollama, OpenAI, and compatible APIs.

**Where it overlaps:** Both are self-hosted LLM chat platforms with multi-model support, RAG, and streaming responses.

**Where Liteskill pulls ahead:**

- **Event sourcing vs. CRUD.** Open WebUI stores conversations as mutable database rows. Liteskill treats every state change as an immutable event — you get a full audit trail, state replay, and temporal queries out of the box. For regulated industries, this isn't a nice-to-have; it's a requirement.
- **Conversation-level ACLs.** Liteskill's unified ACL system provides owner, manager, editor, and viewer roles on individual conversations, reports, agents, wiki spaces, and more — with both direct user grants and group-based grants. Open WebUI's permissions are role-based (admin/user), not per-resource.
- **Native MCP protocol.** Liteskill speaks MCP (Model Context Protocol) over JSON-RPC 2.0, discovering and calling tools from any compliant server. Open WebUI's tool system is Python plugin-based — no interoperability with the broader MCP ecosystem.
- **Agent Studio & Teams.** Liteskill provides composable agents with strategies (ReAct, chain-of-thought, tree-of-thoughts), team topologies (sequential, parallel, supervisor), and full execution tracking with cost limits. Open WebUI offers persona/character creation, but not multi-step agentic orchestration.
- **RBAC + Entity ACLs.** Liteskill has two orthogonal authorization systems: system-wide RBAC (who can create conversations, manage servers, etc.) and per-entity ACLs (who can access this specific conversation). Open WebUI has basic role-based permissions.
- **Licensing.** Liteskill is Apache 2.0 with no restrictions. Open WebUI's license (post-v0.6.5) requires branding for deployments over 50 users unless you hold an enterprise license.

---

## LiteLLM

**What it is:** A Python proxy/gateway that provides a unified OpenAI-compatible API in front of 100+ LLM providers. It handles routing, load balancing, rate limiting, and budget management.

**Where it overlaps:** Both support dozens of LLM providers and track token usage and costs.

**Where Liteskill pulls ahead:**

- **It's an application, not infrastructure.** LiteLLM is an API gateway — it has no UI, no conversation management, no message persistence, and no chat experience. Liteskill is a complete platform your team can use directly.
- **Built-in provider management.** Liteskill handles multi-provider routing, circuit breaking, concurrency gating, and rate limiting internally through its LLM Gateway layer. You don't need a separate proxy sitting in front.
- **Everything else.** MCP tools, event sourcing, RAG, agents, reports, wiki, ACLs, streaming chat — LiteLLM doesn't address any of these because it's solving a different problem. That said, Liteskill can use LiteLLM as a provider if you want both.
- **No enterprise paywall.** LiteLLM gates SSO, audit logs, and advanced RBAC behind paid tiers ($250/month to $30K/year). Liteskill ships all auth and authorization features in the open-source release.

---

## n8n

**What it is:** A visual workflow automation platform (comparable to Zapier or Make) with growing AI capabilities. Node-based editor for building automated business processes.

**Where it overlaps:** Both can orchestrate multi-step AI workflows and integrate with external services.

**Where Liteskill pulls ahead:**

- **Purpose-built for AI conversations.** n8n bolts AI onto a workflow engine via LangChain nodes. Liteskill is built from the ground up for LLM interactions — streaming token-by-token responses, tool calling during generation, conversation forking, and message editing are all first-class features.
- **Event-sourced conversation state.** n8n stores workflow execution history as flat records. Liteskill's event sourcing captures every conversation state change as an immutable event, enabling replay, auditing, and recovery.
- **Native MCP integration.** n8n connects to services through its proprietary node system. Liteskill uses the open MCP protocol, meaning any MCP-compliant tool server works without custom integration code.
- **Licensing.** n8n uses a "Sustainable Use License" (fair-code) that prohibits commercial embedding, resale, or redistribution. Liteskill is Apache 2.0 — use it however you want, including embedding it in commercial products.
- **SSO and RBAC included.** n8n locks SSO (SAML, LDAP) and RBAC behind paid enterprise plans. Liteskill includes OIDC SSO, RBAC, and entity ACLs in the open-source release.

---

## BookStack

**What it is:** A documentation and wiki platform with a structured hierarchy (Shelves > Books > Chapters > Pages). Built with PHP/Laravel.

**Where it overlaps:** Both are self-hosted platforms with strong permission models and wiki/knowledge management features.

**Where Liteskill pulls ahead:**

- **AI-native.** BookStack is a static wiki with no LLM integration, no chat, no streaming, no tool calling, and no agentic capabilities. Liteskill's built-in wiki is one feature among many — and it's automatically synced to the RAG pipeline so your documentation becomes searchable context for AI conversations.
- **Event sourcing.** BookStack uses standard Laravel Eloquent ORM (mutable rows). Liteskill's append-only event store provides an immutable audit trail for every conversation and state change.
- **Unified access control.** BookStack has solid content-level permissions within its domain. Liteskill extends similar fine-grained access control across conversations, agents, teams, reports, MCP servers, data sources, and wiki spaces — all through a single unified ACL table.
- **Where BookStack wins.** BookStack has native SAML2 and LDAP support that's been battle-tested for years, and its MIT license is as permissive as it gets. Its content hierarchy is simple and opinionated in a way that works well for pure documentation use cases. If all you need is a wiki, BookStack is excellent at that.

---

## CrewAI

**What it is:** A Python framework for building multi-agent AI systems. Agents have roles, goals, and tools, and collaborate through sequential, hierarchical, or consensus-based processes.

**Where it overlaps:** Both support multi-agent orchestration with tool calling and MCP integration.

**Where Liteskill pulls ahead:**

- **It's a platform, not a library.** CrewAI is a Python framework you import into your own code — there's no UI, no user management, no persistence layer, no deployment story. Liteskill is a deployed application with a full web interface, real-time streaming, user accounts, and persistent conversation history.
- **Integrated chat + agents.** In Liteskill, agents and teams are defined through the Agent Studio UI, then invoked within the same platform where conversations happen. CrewAI requires building a separate application around its framework to achieve anything user-facing.
- **Enterprise auth built in.** CrewAI's open-source framework has no auth, no RBAC, no SSO. The enterprise platform (AMP) offers these but at $99-$120K/year with execution quotas. Liteskill includes OIDC SSO, RBAC, entity ACLs, and group-based authorization in the open-source release with no quotas.
- **Event-sourced execution tracking.** Liteskill tracks agent runs with structured logs, usage metrics, cost limits, and full event histories. CrewAI's open-source framework provides basic logging but no built-in execution persistence or cost controls.
- **Elixir concurrency model.** Liteskill runs on the BEAM VM — lightweight processes, preemptive scheduling, fault-tolerant supervision trees. Parallel agent topologies, concurrent tool calls, and streaming responses all benefit from Elixir's concurrency primitives without the thread-safety complexity of Python.

---

## At a Glance

| Capability | Liteskill | Open WebUI | LiteLLM | n8n | BookStack | CrewAI |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| LLM Chat UI | **Yes** | Yes | No | No | No | No |
| Event Sourcing | **Yes** | No | No | No | No | No |
| Conversation ACLs | **Yes** | No | N/A | N/A | N/A | N/A |
| RBAC | **Yes** | Basic | Paid | Paid | Yes | Paid |
| OIDC SSO | **Yes** | Yes | Paid | Paid | No | Paid |
| Native MCP Tools | **Yes** | No | No | No | No | Yes |
| Agent Orchestration | **Yes** | No | No | Basic | No | Yes |
| RAG Pipeline | **Yes** | Yes | No | No | No | No |
| Built-in Wiki | **Yes** | No | No | No | Yes | No |
| Structured Reports | **Yes** | No | No | No | No | No |
| Conversation Forking | **Yes** | No | N/A | N/A | N/A | N/A |
| Encryption at Rest | **Yes** | No | No | No | No | No |
| Multi-Provider LLM | **56+** | Yes | 100+ | Via nodes | No | Yes |
| License | **Apache 2.0** | Modified BSD | MIT (paywall) | Fair-code | MIT | MIT (paywall) |

---

## The Bottom Line

Most tools in this space solve one piece of the puzzle. Open WebUI gives you a chat interface. LiteLLM gives you a provider gateway. n8n gives you workflow automation. BookStack gives you a wiki. CrewAI gives you an agent framework.

Liteskill combines all of these into a single, event-sourced platform with enterprise access controls — and ships it all under Apache 2.0 with no feature paywalls, no branding requirements, and no execution quotas.
