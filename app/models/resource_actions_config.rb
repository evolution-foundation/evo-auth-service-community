# frozen_string_literal: true

# Configuration for all resources and actions in the system
# This serves as the single source of truth for RBAC permissions
class ResourceActionsConfig
  RESOURCES = {
    # Ubiquitous language (EVO-2072 — fixes FR12). This catalog is the single
    # source of truth shared by every backend, so the naming lives here:
    #   * `users`     = the human agent ("atendente") who operates the CRM and
    #                   handles conversations. UI label: "Users" / "Usuários".
    #   * `ai_agents` = the AI bot managed by evo-core. UI label: "AI Agents" /
    #                   "Agentes de IA". A DIFFERENT resource — never conflate it
    #                   with `users`.
    #   * role `agent` (db/seeds/rbac.rb) = the *role identity* of the human
    #                   agent, keyed 'agent'. NOT a catalog resource — do not
    #                   rename its key, `Role.find_by(key: 'agent')` depends on it.
    # The dead twin `agents` resource was consolidated into `ai_agents` (it only
    # ever gated the CRM AgentsController, which proxies AI-agent CRUD).
    # User Management
    users: {
      name: 'Users',
      description: 'User management and administration',
      actions: {
        read: { name: 'View', description: 'View user information and list users' },
        create: { name: 'Create', description: 'Create new users' },
        update: { name: 'Update', description: 'Update user information and settings' },
        delete: { name: 'Delete', description: 'Delete users from the system' },
        bulk_operations: { name: 'Bulk Operations', description: 'Perform bulk operations on users' },
        stats: { name: 'Statistics', description: 'View user statistics and metrics' },
        types: { name: 'User Types', description: 'View available user types' },
        permissions: { name: 'View Permissions', description: 'View user permissions' },
        check_permission: { name: 'Check Permission', description: 'Validate specific user permissions' },
        destroy_access_token: {name: 'Destroy Access Token', description: 'Revoke user access tokens'},
        remove_avatar: { name: 'Remove Avatar', description: 'Remove user profile avatar' },
        create_account_user: { name: 'Create Account User', description: 'Create account user associations' },
        manage: { name: 'Manage', description: 'Administer users via Settings (view/manage agents panel)' }
      }
    },

    # Account Management
    accounts: {
      name: 'Accounts',
      description: 'Account and organization management',
      actions: {
        read: { name: 'View', description: 'View account information' },
        create: { name: 'Create', description: 'Create new accounts' },
        update: { name: 'Update', description: 'Update account settings and information' },
        delete: { name: 'Delete', description: 'Delete accounts' },
        stats: { name: 'Statistics', description: 'View account statistics and analytics' },
        types: { name: 'Account Types', description: 'View available account types' },
      }
    },

    # Access Tokens Management
    access_tokens: {
      name: 'Access Tokens',
      description: 'API access token management and authentication',
      actions: {
        read: { name: 'View', description: 'View access tokens and their details' },
        create: { name: 'Create', description: 'Generate new access tokens' },
        update: { name: 'Update', description: 'Update access token information and scopes' },
        delete: { name: 'Delete', description: 'Revoke and delete access tokens' },
        update_token: { name: 'Regenerate Token', description: 'Regenerate access token value' },
      }
    },

    # Role Management
    roles: {
      name: 'Roles',
      description: 'Role and permission management',
      actions: {
        read: { name: 'View', description: 'View roles and permissions' },
        create: { name: 'Create', description: 'Create custom roles' },
        update: { name: 'Update', description: 'Update role details and permissions' },
        delete: { name: 'Delete', description: 'Delete custom roles' },
        bulk_assign: { name: 'Bulk Assign', description: 'Bulk assign roles to multiple users' },
        bulk_update_permissions: { name: 'Update Permissions', description: 'Update role permission tree' }
      }
    },

    # OAuth Applications
    oauth_applications: {
      name: 'OAuth Applications',
      description: 'OAuth application management',
      actions: {
        read: { name: 'View', description: 'View OAuth applications' },
        create: { name: 'Create', description: 'Create new OAuth applications' },
        update: { name: 'Update', description: 'Update OAuth applications' },
        delete: { name: 'Delete', description: 'Delete OAuth applications' },
        regenerate_secret: { name: 'Regenerate Secret', description: 'Regenerate OAuth application secret' }
      }
    },

    # Profile Management
    profiles: {
      name: 'Profiles',
      description: 'User profile management',
      actions: {
        read: { name: 'View', description: 'View user profiles' },
        update: { name: 'Update', description: 'Update profile information' },
        update_avatar: { name: 'Update Avatar', description: 'Update profile avatar' },
        update_password: { name: 'Update Password', description: 'Update password' },
        manage_notifications: { name: 'Manage Notifications', description: 'Manage notification preferences' }
      }
    },

    # === EVO AI CORE SERVICE ===
    # `ai_agents` = the AI bot (evo-core). Distinct from `users` (the human
    # agent / "atendente") and from the seed role `agent`. See the ubiquitous
    # language note at the top of RESOURCES (EVO-2072).
    ai_agents: {
      name: 'AI Agents',
      description: 'AI agent management and configuration',
      actions: {
        read: { name: 'View', description: 'View AI agents and their configurations' },
        create: { name: 'Create', description: 'Create new AI agents' },
        update: { name: 'Update', description: 'Update agent configurations' },
        delete: { name: 'Delete', description: 'Delete AI agents' },
        sync: { name: 'Sync', description: 'Sync agents with Evolution bots' },
        import: { name: 'Import', description: 'Import agents from external sources' },
        share: { name: 'Share', description: 'Share agents with other users' },
        manage_folder: { name: 'Manage Folder', description: 'Organize agents in folders' }
      }
    },

    # Built-in tools catalog (NOT the same as ai_custom_tools). Kept: the processor
    # tools_routes endpoints (GET /tools, /tools/{id}, /tools/categories/list,
    # POST /tools/reload-config) are mounted (main.py) and enforce ai_tools.
    # {available,read,categories,config}; the frontend Agents/Tools page consumes
    # them via toolsService. EVO-2070 audit (§A0) contradicted the spec matrix,
    # which had this as dead — see story Dev Agent Record.
    ai_tools: {
      name: 'AI Custom Tools',
      description: 'Custom tools and integrations for AI agents',
      actions: {
        read: { name: 'View', description: 'View custom tools and configurations' },
        create: { name: 'Create', description: 'Create new custom tools' },
        update: { name: 'Update', description: 'Update tool configurations' },
        delete: { name: 'Delete', description: 'Delete custom tools' },
        test: { name: 'Test', description: 'Test tool functionality and connections' },
        available: { name: 'Available', description: 'List all available tools' },
        categories: { name: 'Categories', description: 'List all tool categories' },
        config: { name: 'Config', description: 'Tools configuration from file' }
      }
    },

    ai_api_keys: {
      name: 'AI API Keys',
      description: 'API key management for AI services',
      actions: {
        read: { name: 'View', description: 'View API keys (without revealing secrets)' },
        create: { name: 'Create', description: 'Create new API keys' },
        update: { name: 'Update', description: 'Update API key configurations' },
        delete: { name: 'Delete', description: 'Delete API keys' }
      }
    },

    # Kept: the core-service (Go) enforces ai_folders in 14 mounted routes
    # (pkg/folder + pkg/folder_share, registered in cmd/api/main.go) and the
    # frontend consumes them via agentService (/folders CRUD + sharing). The
    # EVO-2070 §A0 audit matrix marked this dead because it never grepped the
    # core service — removing it would 403 the agent-folders feature for everyone.
    ai_folders: {
      name: 'AI Folders',
      description: 'Folder organization for AI resources',
      actions: {
        read: { name: 'View', description: 'View folders and their contents' },
        create: { name: 'Create', description: 'Create new folders' },
        update: { name: 'Update', description: 'Update folder properties' },
        delete: { name: 'Delete', description: 'Delete folders and reorganize contents' },
        share: { name: 'Share', description: 'Share folders with other users' },
        access_shared: { name: 'Access Shared', description: 'Access folders shared by others' }
      }
    },

    # Kept: NOT a dead twin of ai_custom_mcp_servers. The core-service enforces
    # ai_mcp_servers in 6 mounted routes (pkg/mcp_server, main.go) backing the
    # "MCP Servers" feature (frontend MCPServers.tsx + Admin/McpServers.tsx via
    # mcpServerService -> /mcp-servers), which is distinct from "Custom MCP
    # Servers" (ai_custom_mcp_servers -> /custom-mcp-servers). The §A0 audit
    # missed the core enforcement; removing it would 403 the MCP Servers screens.
    ai_mcp_servers: {
      name: 'MCP Servers',
      description: 'Model Context Protocol server management',
      actions: {
        read: { name: 'View', description: 'View MCP servers and configurations' },
        create: { name: 'Create', description: 'Create new MCP servers' },
        update: { name: 'Update', description: 'Update MCP server configurations' },
        delete: { name: 'Delete', description: 'Delete MCP servers' },
        test: { name: 'Test', description: 'Test MCP server connections' }
      }
    },

    # === EVO AI AGENT PROCESSOR SERVICE ===
    ai_agent_processor: {
      name: 'AI Agent Processor',
      description: 'AI agent processing and execution management',
      actions: {
        read: { name: 'View', description: 'View agent processing status and results', system: true },
        execute: { name: 'Execute', description: 'Execute agents and processing tasks', system: true },
        stream: { name: 'Stream', description: 'Stream agent responses and processing', system: true }
      }
    },

    ai_chat_sessions: {
      name: 'Chat Sessions',
      description: 'AI chat session management for agent interactions',
      actions: {
        read: { name: 'View', description: 'View chat sessions and conversation history', system: true },
        create: { name: 'Create', description: 'Create new chat sessions with agents', system: true },
        update: { name: 'Update', description: 'Update chat session metadata and settings', system: true },
        delete: { name: 'Delete', description: 'Delete chat sessions and conversation history', system: true },
        bulk_delete: { name: 'Bulk Delete', description: 'Delete multiple chat sessions at once', system: true },
        metrics: { name: 'View Metrics', description: 'View session execution metrics and statistics', system: true }
      }
    },

    ai_a2a_protocol: {
      name: 'A2A Protocol',
      description: 'Agent-to-Agent communication protocol management',
      actions: {
        read: { name: 'View', description: 'View A2A protocol configurations and status', system: true },
        execute: { name: 'Execute', description: 'Execute A2A protocol operations and communications', system: true },
        stream: { name: 'Stream', description: 'Stream A2A protocol responses', system: true },
        message_send: { name: 'Send Messages', description: 'Send messages via A2A protocol', system: true },
        task_management: { name: 'Manage Tasks', description: 'Manage A2A protocol tasks and workflows', system: true }
      }
    },

    ai_custom_mcp_servers: {
      name: 'Custom MCP Servers',
      description: 'Custom Model Context Protocol server management',
      actions: {
        read: { name: 'View', description: 'View custom MCP server and configurations' },
        create: { name: 'Create', description: 'Create new custom MCP server' },
        update: { name: 'Edit', description: 'Edit existing custom MCP server' },
        delete: { name: 'Delete', description: 'Delete custom MCP server' },
        test: { name: 'Test', description: 'Test custom MCP server connections and functionality' }
      }
    },

    ai_custom_tools: {
      name: 'Custom AI Tools',
      description: 'Custom AI tool management for agent capabilities',
      actions: {
        read: { name: 'View', description: 'View custom AI tools and configurations' },
        create: { name: 'Create', description: 'Create new custom AI tools' },
        update: { name: 'Edit', description: 'Edit existing custom AI tools' },
        delete: { name: 'Delete', description: 'Delete custom AI tools' },
        test: { name: 'Test', description: 'Test custom AI tool functionality and endpoints' }
      }
    },

    ai_clients: {
      name: 'AI Clients',
      description: 'AI client usage monitoring and management',
      actions: {
        read: { name: 'View', description: 'View client information and configurations' },
        usage: { name: 'View Usage', description: 'View client usage statistics and summaries' },
        limits: { name: 'Manage Limits', description: 'Manage client usage limits and quotas' }
      }
    },

    # === EVOLUTION CUSTOMER SUPPORT PLATFORM ===
    conversations: {
      name: 'Conversations',
      description: 'Customer conversation management and messaging',
      actions: {
        read: { name: 'View', description: 'View conversations and message history' },
        create: { name: 'Create', description: 'Create new conversations' },
        update: { name: 'Update', description: 'Update conversation details and status' },
        delete: { name: 'Delete', description: 'Delete conversations' },
        meta: { name: 'Meta', description: 'View conversation meta information' },
        search: { name: 'Search', description: 'Search conversations' },
        filter: { name: 'Filter', description: 'Filter conversations' },
        available_for_pipeline: { name: 'Available for Pipeline', description: 'List conversations available for pipeline' },
        mute: { name: 'Mute', description: 'Mute conversation notifications' },
        unmute: { name: 'Unmute', description: 'Unmute conversation notifications' },
        transcript: { name: 'Transcript', description: 'Request conversation transcript' },
        toggle_status: { name: 'Toggle Status', description: 'Change conversation status' },
        toggle_priority: { name: 'Toggle Priority', description: 'Change conversation priority' },
        toggle_typing_status: { name: 'Toggle Typing Status', description: 'Toggle typing indicator' },
        update_last_seen: { name: 'Update Last Seen', description: 'Update last seen for conversation' },
        unread: { name: 'Unread', description: 'Mark conversation as unread' },
        custom_attributes: { name: 'Custom Attributes', description: 'Manage conversation custom attributes' },
        attachments: { name: 'Attachments', description: 'View conversation attachments' },
        inbox_assistant: { name: 'Inbox Assistant', description: 'Access inbox assistant features' },
        read_all: { name: 'Read all inboxes', description: 'View conversations from all inboxes (bypass per-inbox restriction)' },
        import: { name: 'Import', description: 'Import conversation history from CSV (EVO-1557)' }
      }
    },

    contacts: {
      name: 'Contacts',
      description: 'Customer contact management and profiles',
      actions: {
        read: { name: 'View', description: 'View contact information and profiles' },
        create: { name: 'Create', description: 'Create new contacts' },
        update: { name: 'Update', description: 'Update contact information' },
        delete: { name: 'Delete', description: 'Delete contacts' },
        active: { name: 'Active', description: 'List active contacts' },
        search: { name: 'Search', description: 'Search contacts' },
        filter: { name: 'Filter', description: 'Filter contacts' },
        import: { name: 'Import', description: 'Import contact data' },
        export: { name: 'Export', description: 'Export contact data' },
        contactable_inboxes: { name: 'Contactable Inboxes', description: 'View contactable inboxes' },
        destroy_custom_attributes: { name: 'Destroy Custom Attributes', description: 'Remove custom attributes from contact' },
        avatar: { name: 'Avatar', description: 'Manage contact avatar' }
      }
    },

    inboxes: {
      name: 'Inboxes',
      description: 'Communication channel and inbox management',
      actions: {
        read: { name: 'View', description: 'View inboxes and channel configurations' },
        create: { name: 'Create', description: 'Create new inboxes and channels' },
        update: { name: 'Update', description: 'Update inbox settings and configurations' },
        delete: { name: 'Delete', description: 'Delete inboxes' },
        assignable_agents: { name: 'Assignable Agents', description: 'List assignable agents for inbox' },
        agent_bot: { name: 'Agent Bot', description: 'View agent bot for inbox' },
        set_agent_bot: { name: 'Set Agent Bot', description: 'Assign agent bot to inbox' },
        setup_channel_provider: { name: 'Setup Channel Provider', description: 'Setup channel provider for inbox' },
        disconnect_channel_provider: { name: 'Disconnect Channel Provider', description: 'Disconnect channel provider from inbox' },
        avatar: { name: 'Avatar', description: 'Manage inbox avatar' },
        sync_whatsapp_templates: { name: 'Sync WhatsApp Templates', description: 'Sync WhatsApp templates for inbox' },
        whatsapp_templates: { name: 'WhatsApp Templates', description: 'Manage WhatsApp templates for inbox' },
        update_whatsapp_template: { name: 'Update WhatsApp Template', description: 'Update WhatsApp template' },
        delete_whatsapp_template: { name: 'Delete WhatsApp Template', description: 'Delete WhatsApp template' },
        message_templates: { name: 'Message Templates', description: 'Manage message templates for inbox' },
        update_message_template: { name: 'Update Message Template', description: 'Update message template' },
        delete_message_template: { name: 'Delete Message Template', description: 'Delete message template' }
      }
    },

    teams: {
      name: 'Teams',
      description: 'Agent team management and organization',
      actions: {
        read: { name: 'View', description: 'View teams and member information' },
        create: { name: 'Create', description: 'Create new teams' },
        update: { name: 'Update', description: 'Update team information' },
        delete: { name: 'Delete', description: 'Delete teams' }
      }
    },

    labels: {
      name: 'Labels',
      description: 'Conversation and contact labeling system',
      actions: {
        read: { name: 'View', description: 'View available labels' },
        create: { name: 'Create', description: 'Create new labels' },
        update: { name: 'Update', description: 'Update label properties' },
        delete: { name: 'Delete', description: 'Delete labels' }
      }
    },

    macros: {
      name: 'Macros',
      description: 'Automated action sequences for agent productivity',
      actions: {
        read: { name: 'View', description: 'View available macros' },
        create: { name: 'Create', description: 'Create new macros' },
        update: { name: 'Update', description: 'Update macro configurations' },
        delete: { name: 'Delete', description: 'Delete macros' },
        execute: { name: 'Execute', description: 'Execute macros on conversations' }
      }
    },

    canned_responses: {
      name: 'Canned Responses',
      description: 'Pre-defined message templates for quick responses',
      actions: {
        read: { name: 'View', description: 'View canned responses' },
        create: { name: 'Create', description: 'Create new canned responses' },
        update: { name: 'Update', description: 'Update canned response content' },
        delete: { name: 'Delete', description: 'Delete canned responses' }
      }
    },

    message_templates: {
      name: 'Message Templates',
      description: 'Global (channel-independent) message templates',
      actions: {
        read: { name: 'View', description: 'View global message templates' },
        create: { name: 'Create', description: 'Create global message templates' },
        update: { name: 'Update', description: 'Update global message templates' },
        delete: { name: 'Delete', description: 'Delete global message templates' }
      }
    },

    products: {
      name: 'Products',
      description: 'Product catalog for AI agent recommendations and pipeline sales',
      actions: {
        read: { name: 'View', description: 'View products and variants' },
        create: { name: 'Create', description: 'Create new products' },
        update: { name: 'Update', description: 'Update product information and variants' },
        delete: { name: 'Delete', description: 'Delete products from the catalog' }
      }
    },

    templates: {
      name: 'Templates',
      description: 'Workspace configuration bundles for export and import',
      actions: {
        read: { name: 'View', description: 'View templates settings page' },
        export: { name: 'Export', description: 'Export workspace configuration as a template bundle' },
        import: { name: 'Import', description: 'Import a template bundle into the workspace' }
      }
    },

    webhooks: {
      name: 'Webhooks',
      description: 'Webhook integration management for external systems',
      actions: {
        read: { name: 'View', description: 'View webhook configurations' },
        create: { name: 'Create', description: 'Create new webhook endpoints' },
        update: { name: 'Update', description: 'Update webhook configurations' },
        delete: { name: 'Delete', description: 'Delete webhooks' }
      }
    },

    agent_bots: {
      name: 'Agent Bots',
      description: 'Automated bot agents for customer interactions',
      actions: {
        read: { name: 'View', description: 'View bot configurations' },
        create: { name: 'Create', description: 'Create new agent bots' },
        update: { name: 'Update', description: 'Update bot configurations' },
        delete: { name: 'Delete', description: 'Delete agent bots' },
        avatar: { name: 'Avatar', description: 'Manage agent bot avatar' }
      }
    },

    automation_rules: {
      name: 'Automation Rules',
      description: 'Automated workflow rules and triggers',
      actions: {
        read: { name: 'View', description: 'View automation rules' },
        create: { name: 'Create', description: 'Create new automation rules' },
        update: { name: 'Update', description: 'Update rule conditions and actions' },
        delete: { name: 'Delete', description: 'Delete automation rules' },
        clone: { name: 'Clone', description: 'Clone automation rules' }
      }
    },

    integrations: {
      name: 'Integrations',
      description: 'Third-party service integrations and connections',
      actions: {
        read: { name: 'View', description: 'View integration configurations' },
        create: { name: 'Create', description: 'Create new integrations' },
        update: { name: 'Update', description: 'Update integration settings' },
        delete: { name: 'Delete', description: 'Delete integrations' },
        connect: { name: 'Connect', description: 'Establish integration connections' },
        disconnect: { name: 'Disconnect', description: 'Disconnect integrations' },
        execute: { name: 'Execute', description: 'Execute integration events (AI prompt processing)' }
      }
    },

    dashboard_apps: {
      name: 'Dashboard Apps',
      description: 'Custom dashboard applications and widgets',
      actions: {
        read: { name: 'View', description: 'View dashboard apps' },
        create: { name: 'Create', description: 'Create new dashboard apps' },
        update: { name: 'Update', description: 'Update app configurations' },
        delete: { name: 'Delete', description: 'Delete dashboard apps' }
      }
    },

    # Installation Configuration (Admin Panel)
    installation_configs: {
      name: 'Installation Configs',
      description: 'System-wide configuration managed via admin panel',
      actions: {
        manage: { name: 'Manage', description: 'View and update installation configurations', system: true }
      }
    },

    # Account Settings
    working_hours: {
      name: 'Working Hours',
      description: 'Working hours configuration',
      actions: {
        read: { name: 'View', description: 'View working hours' },
        create: { name: 'Create', description: 'Create working hours' },
        update: { name: 'Update', description: 'Update working hours' },
        delete: { name: 'Delete', description: 'Delete working hours' }
      }
    },

    csat_survey_responses: {
      name: 'CSAT Survey Responses',
      description: 'Customer satisfaction survey responses',
      actions: {
        read: { name: 'View', description: 'View CSAT responses' },
        create: { name: 'Create', description: 'Create CSAT responses' },
        update: { name: 'Update', description: 'Update CSAT responses' },
        delete: { name: 'Delete', description: 'Delete CSAT responses' }
      }
    },

    # External Integrations
    microsoft_authorizations: {
      name: 'Microsoft Authorizations',
      description: 'Microsoft integration authorization',
      actions: {
        read: { name: 'View', description: 'View Microsoft authorizations' },
        create: { name: 'Create', description: 'Create Microsoft authorizations' },
        update: { name: 'Update', description: 'Update Microsoft authorizations' },
        delete: { name: 'Delete', description: 'Delete Microsoft authorizations' }
      }
    },


    instagram_authorizations: {
      name: 'Instagram Authorizations',
      description: 'Instagram integration authorization',
      actions: {
        read: { name: 'View', description: 'View Instagram authorizations' },
        create: { name: 'Create', description: 'Create Instagram authorizations' },
        update: { name: 'Update', description: 'Update Instagram authorizations' },
        delete: { name: 'Delete', description: 'Delete Instagram authorizations' }
      }
    },

    google_authorizations: {
      name: 'Google Authorizations',
      description: 'Google integration authorization',
      actions: {
        read: { name: 'View', description: 'View Google authorizations' },
        create: { name: 'Create', description: 'Create Google authorizations' },
        update: { name: 'Update', description: 'Update Google authorizations' },
        delete: { name: 'Delete', description: 'Delete Google authorizations' }
      }
    },

    whatsapp_authorizations: {
      name: 'WhatsApp Authorizations',
      description: 'WhatsApp integration authorization',
      actions: {
        read: { name: 'View', description: 'View WhatsApp authorizations' },
        create: { name: 'Create', description: 'Create WhatsApp authorizations' },
        update: { name: 'Update', description: 'Update WhatsApp authorizations' },
        delete: { name: 'Delete', description: 'Delete WhatsApp authorizations' }
      }
    },

    twitter_authorizations: {
      name: 'Twitter Authorizations',
      description: 'Twitter integration authorization',
      actions: {
        read: { name: 'View', description: 'View Twitter authorizations' },
        create: { name: 'Create', description: 'Create Twitter authorizations' },
        update: { name: 'Update', description: 'Update Twitter authorizations' },
        delete: { name: 'Delete', description: 'Delete Twitter authorizations' }
      }
    },

    # Pipeline Management
    pipeline_stages: {
      name: 'Pipeline Stages',
      description: 'Pipeline stage management',
      actions: {
        read: { name: 'View', description: 'View pipeline stages' },
        create: { name: 'Create', description: 'Create pipeline stages' },
        update: { name: 'Update', description: 'Update pipeline stages' },
        delete: { name: 'Delete', description: 'Delete pipeline stages' }
      }
    },

    custom_attribute_definitions: {
      name: 'Custom Attribute Definitions',
      description: 'Custom field definitions for contacts and conversations',
      actions: {
        read: { name: 'View', description: 'View custom attribute definitions' },
        create: { name: 'Create', description: 'Create new custom attributes' },
        update: { name: 'Update', description: 'Update attribute definitions' },
        delete: { name: 'Delete', description: 'Delete custom attributes' }
      }
    },

    custom_filters: {
      name: 'Custom Filters',
      description: 'Saved search filters and queries',
      actions: {
        read: { name: 'View', description: 'View saved filters' },
        create: { name: 'Create', description: 'Create new custom filters' },
        update: { name: 'Update', description: 'Update filter criteria' },
        delete: { name: 'Delete', description: 'Delete custom filters' }
      }
    },

    pipelines: {
      name: 'Pipelines',
      description: 'Sales and workflow pipeline management',
      actions: {
        read: { name: 'View', description: 'View pipelines and stages' },
        create: { name: 'Create', description: 'Create new pipelines' },
        update: { name: 'Update', description: 'Update pipeline settings and stages' },
        delete: { name: 'Delete', description: 'Delete pipelines' }
      }
    },

    crm_forms: {
      name: 'Lead Capture Forms',
      description: 'Public lead-capture form builder (form -> pipeline)',
      actions: {
        read: { name: 'View', description: 'View lead-capture forms' },
        create: { name: 'Create', description: 'Create new lead-capture forms' },
        update: { name: 'Update', description: 'Update lead-capture forms' },
        delete: { name: 'Delete', description: 'Delete lead-capture forms' }
      }
    },

    chat_pages: {
      name: 'Chat Pages',
      description: 'Public chat page builder (slug -> embedded web widget)',
      actions: {
        read: { name: 'View', description: 'View chat pages' },
        create: { name: 'Create', description: 'Create new chat pages' },
        update: { name: 'Update', description: 'Update chat pages' },
        delete: { name: 'Delete', description: 'Delete chat pages' }
      }
    },

    # === EVO FLOW SERVICE (segments / journeys / campaigns) ===
    segments: {
      name: 'Segments',
      description: 'Dynamic contact audience definitions based on condition filters',
      actions: {
        read: { name: 'View', description: 'View segments and their definitions' },
        create: { name: 'Create', description: 'Create new segments' },
        update: { name: 'Update', description: 'Update segment definitions and settings' },
        delete: { name: 'Delete', description: 'Delete segments' },
        recompute: { name: 'Recompute', description: 'Recompute segment membership' }
      }
    },

    journeys: {
      name: 'Journeys',
      description: 'Multi-step visual automations (trigger plus conditional actions)',
      actions: {
        read: { name: 'View', description: 'View journeys and flow editor' },
        create: { name: 'Create', description: 'Create new journeys' },
        update: { name: 'Update', description: 'Update journey flow and settings' },
        delete: { name: 'Delete', description: 'Delete journeys' },
        toggle_active: { name: 'Toggle Active', description: 'Activate or deactivate a journey' },
        duplicate: { name: 'Duplicate', description: 'Duplicate a journey' },
        manage_sessions: { name: 'Manage Sessions', description: 'View and manage journey execution sessions' }
      }
    },

    campaigns: {
      name: 'Campaigns',
      description: 'Bulk message campaigns consuming segments as audience',
      actions: {
        read: { name: 'View', description: 'View campaigns and their stats' },
        create: { name: 'Create', description: 'Create new campaigns' },
        update: { name: 'Update', description: 'Update campaign settings and content' },
        delete: { name: 'Delete', description: 'Delete campaigns' },
        schedule: { name: 'Schedule', description: 'Schedule campaigns for later execution' },
        execute: { name: 'Execute', description: 'Execute campaigns immediately' },
        pause: { name: 'Pause', description: 'Pause running campaigns' },
        resume: { name: 'Resume', description: 'Resume paused campaigns' },
        stop: { name: 'Stop', description: 'Stop running campaigns' },
        duplicate: { name: 'Duplicate', description: 'Duplicate a campaign' },
        bulk_action: { name: 'Bulk Action', description: 'Perform bulk actions on campaigns' }
      }
    },

    }.freeze

  # Backend mirror of the write-group classification in the frontend's
  # permissionDomains.ts. Two pieces, both must stay in sync with the frontend
  # (an action added on one side must be added on the other, or the two disagree
  # on what a "write" is and a save 403s):
  #   NON_WRITE_ACTIONS            -> mirrors READ_ACTIONS: non-mutating verbs that
  #                                   are resource-independent. `read`/`delete`/the
  #                                   injected `write` are listed so they never
  #                                   classify as write.
  #   STANDALONE_ACTIONS_BY_RESOURCE -> mirrors STANDALONE_ACTIONS: keys that render
  #                                   on their own row for a SPECIFIC resource
  #                                   (conversations.read_all, users.manage) and so
  #                                   are neither read nor write there.
  NON_WRITE_ACTIONS = %i[
    read delete write
    meta search filter available_for_pipeline attachments transcript
    inbox_assistant active contactable_inboxes assignable_agents agent_bot
    stats types permissions check_permission export
    available categories config access_shared usage metrics
  ].to_set.freeze

  STANDALONE_ACTIONS_BY_RESOURCE = {
    conversations: %i[read_all].to_set,
    users: %i[manage].to_set
  }.freeze

  # A granular action is a manageable write when it mutates the resource AND is
  # user-manageable: not system-managed, not a read (NON_WRITE_ACTIONS), and not a
  # per-resource standalone (STANDALONE_ACTIONS_BY_RESOURCE). System actions are
  # hidden from the role editor, so a coarse write standing only for them would
  # render an un-grantable checkbox and 403 a delegated admin.
  def self.manageable_write_actions(resource_key, actions)
    standalone = STANDALONE_ACTIONS_BY_RESOURCE[resource_key.to_sym] || Set.new
    actions.reject do |key, cfg|
      NON_WRITE_ACTIONS.include?(key) || standalone.include?(key) || cfg[:system]
    end.keys
  end

  # Coarse "write" bridge (EVO-2127): the role editor renders read/write/delete
  # groups and now persists them. Inject a `write` leaf ONLY into resources that
  # actually have a manageable granular write, so valid_permission?("<resource>.write")
  # passes (no 422) exactly where the editor shows a Write group — and never on
  # all-system or read-only resources (which would otherwise render a spurious,
  # un-grantable Write checkbox that 403s delegated admins). The outer RESOURCES
  # hash is frozen but the per-resource :actions hashes are not. Nothing enforces
  # the coarse write yet (enforcement stays granular; collapsing keys is a follow-up).
  RESOURCES.each do |resource_key, resource_config|
    next unless manageable_write_actions(resource_key, resource_config[:actions]).any?

    resource_config[:actions][:write] ||= {
      name: 'Write',
      description: 'Coarse write (covers create/update/… for this resource)'
    }
  end

  class << self
    # Get all resources
    def all_resources
      RESOURCES
    end

    # Get resource configuration
    def resource(resource_key)
      RESOURCES[resource_key.to_sym]
    end

    # Get all actions for a resource
    def resource_actions(resource_key)
      resource(resource_key)&.dig(:actions) || {}
    end

    # Per resource, the manageable granular writes (see manageable_write_actions:
    # excludes read/delete/write, the read/standalone denylist, and system
    # actions), so a read-only or all-system resource yields none — matching the
    # resources that received a coarse write leaf. Drives the write => coarse-write
    # implications in User::OPERATIONAL_IMPLICATIONS.
    def write_actions_by_resource
      RESOURCES.each_with_object({}) do |(resource_key, cfg), acc|
        writes = manageable_write_actions(resource_key, cfg[:actions])
        acc[resource_key.to_s] = writes.map(&:to_s) if writes.any?
      end
    end

    # Get action configuration
    def action(resource_key, action_key)
      resource_actions(resource_key)[action_key.to_sym]
    end

    # Generate permission key
    def permission_key(resource_key, action_key)
      "#{resource_key}.#{action_key}"
    end

    # Get all possible permission keys
    def all_permission_keys
      RESOURCES.flat_map do |resource_key, resource_config|
        resource_config[:actions].keys.map do |action_key|
          permission_key(resource_key, action_key)
        end
      end
    end

    # Check if a permission key is valid
    def valid_permission?(permission_key)
      resource_key, action_key = permission_key.split('.')
      return false unless resource_key && action_key

      resource_actions(resource_key).key?(action_key.to_sym)
    end

    # Get permission display name
    def permission_display_name(permission_key)
      resource_key, action_key = permission_key.split('.')
      return permission_key unless resource_key && action_key

      resource_config = resource(resource_key)
      action_config = action(resource_key, action_key)
      
      return permission_key unless resource_config && action_config

      "#{resource_config[:name]} - #{action_config[:name]}"
    end

    # Lock metadata for a permission key. `basic` keys are held by every
    # authenticated user (User::BASIC_READ_PERMISSIONS); `implied_by` names the
    # grant that carries this one operationally (User::OPERATIONAL_IMPLICATIONS).
    # Either makes the permission NON-manageable in a role editor: granting or
    # revoking it on a role has no effect, so the UI must show it locked instead
    # of offering a checkbox that lies. User is the single source of truth; this
    # only reads its constants (at call time, so no load-order coupling).
    # Reverse index implied_key => first source that implies it, built once from
    # User::OPERATIONAL_IMPLICATIONS (frozen at load). api_format calls
    # permission_lock_info for every catalog key; a linear `.find` over the now
    # ~150-entry implications map made that O(keys × implications) per fetch.
    # First-source-wins (matches the old `.find`) via ||=.
    def implication_source_index
      @implication_source_index ||= User::OPERATIONAL_IMPLICATIONS.each_with_object({}) do |(source, implied), idx|
        implied.each { |key| idx[key] ||= source }
      end.freeze
    end

    def permission_lock_info(permission_key)
      return { basic: true, implied_by: nil } if User::BASIC_READ_PERMISSIONS.include?(permission_key)

      { basic: false, implied_by: implication_source_index[permission_key] }
    end

    # Get formatted data for API responses
    def api_format
      {
        resources: RESOURCES.map do |resource_key, resource_config|
          [
            resource_key,
            {
              name: resource_config[:name],
              description: resource_config[:description],
              actions: resource_config[:actions].map do |action_key, action_config|
                info = permission_lock_info(permission_key(resource_key, action_key))
                [
                  action_key,
                  {
                    name: action_config[:name],
                    description: action_config[:description],
                    basic: info[:basic],
                    implied_by: info[:implied_by],
                    system: action_config[:system] || false
                  }
                ]
              end.to_h
            }
          ]
        end.to_h,
        all_permissions: all_permission_keys.map do |permission_key|
          resource_key, action_key = permission_key.split('.')
          info = permission_lock_info(permission_key)
          {
            key: permission_key,
            display_name: permission_display_name(permission_key),
            resource: resource_key,
            action: action_key,
            resource_name: resource(resource_key)[:name],
            action_name: action(resource_key, action_key)[:name],
            description: action(resource_key, action_key)[:description],
            basic: info[:basic],
            implied_by: info[:implied_by],
            system: action(resource_key, action_key)[:system] || false
          }
        end
      }
    end

  end
end