# frozen_string_literal: true

# Configuration for all resources and actions in the system
# This serves as the single source of truth for RBAC permissions
class ResourceActionsConfig
  RESOURCES = {
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
        create_account_user: { name: 'Create Account User', description: 'Create account user associations' }
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
        bulk_assign: { name: 'Bulk Assign', description: 'Bulk assign roles to multiple users' }
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

    # Permissions (for permission management interface)
    permissions: {
      name: 'Permissions',
      description: 'Permission management interface',
      actions: {
        read: { name: 'View', description: 'View available permissions' }
      }
    },

    # === EVO AI CORE SERVICE ===
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
        read: { name: 'View', description: 'View agent processing status and results' },
        execute: { name: 'Execute', description: 'Execute agents and processing tasks' },
        stream: { name: 'Stream', description: 'Stream agent responses and processing' }
      }
    },

    ai_chat_sessions: {
      name: 'Chat Sessions',
      description: 'AI chat session management for agent interactions',
      actions: {
        read: { name: 'View', description: 'View chat sessions and conversation history' },
        create: { name: 'Create', description: 'Create new chat sessions with agents' },
        update: { name: 'Update', description: 'Update chat session metadata and settings' },
        delete: { name: 'Delete', description: 'Delete chat sessions and conversation history' },
        bulk_delete: { name: 'Bulk Delete', description: 'Delete multiple chat sessions at once' },
        metrics: { name: 'View Metrics', description: 'View session execution metrics and statistics' }
      }
    },

    ai_a2a_protocol: {
      name: 'A2A Protocol',
      description: 'Agent-to-Agent communication protocol management',
      actions: {
        read: { name: 'View', description: 'View A2A protocol configurations and status' },
        execute: { name: 'Execute', description: 'Execute A2A protocol operations and communications' },
        stream: { name: 'Stream', description: 'Stream A2A protocol responses' },
        message_send: { name: 'Send Messages', description: 'Send messages via A2A protocol' },
        task_management: { name: 'Manage Tasks', description: 'Manage A2A protocol tasks and workflows' }
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
        inbox_assistant: { name: 'Inbox Assistant', description: 'Access inbox assistant features' }
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

    channels: {
      name: 'Channels',
      description: 'Communication channel management and configuration',
      actions: {
        read: { name: 'View', description: 'View channels and configurations' },
        create: { name: 'Create', description: 'Create new communication channels' },
        update: { name: 'Update', description: 'Update channel settings and configurations' },
        delete: { name: 'Delete', description: 'Delete communication channels' },
        settings: { name: 'Settings', description: 'Access channel settings and configuration' },
        test_connection: { name: 'Test Connection', description: 'Test channel connectivity and functionality' }
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
        message_templates: { name: 'Message Templates', description: 'Manage message templates for inbox' }
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
        disconnect: { name: 'Disconnect', description: 'Disconnect integrations' }
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

    # OAuth Controllers
    oauth_contacts: {
      name: 'OAuth Contacts',
      description: 'OAuth-based contact management',
      actions: {
        read: { name: 'View', description: 'View OAuth contacts' },
        create: { name: 'Create', description: 'Create OAuth contacts' },
        update: { name: 'Update', description: 'Update OAuth contacts' },
        delete: { name: 'Delete', description: 'Delete OAuth contacts' }
      }
    },

    oauth_agents: {
      name: 'OAuth Agents',
      description: 'OAuth-based agent management',
      actions: {
        read: { name: 'View', description: 'View OAuth agents' },
        create: { name: 'Create', description: 'Create OAuth agents' },
        update: { name: 'Update', description: 'Update OAuth agents' },
        delete: { name: 'Delete', description: 'Delete OAuth agents' }
      }
    },

    oauth_pipeline_stages: {
      name: 'OAuth Pipeline Stages',
      description: 'OAuth-based pipeline stage management',
      actions: {
        read: { name: 'View', description: 'View OAuth pipeline stages' },
        create: { name: 'Create', description: 'Create OAuth pipeline stages' },
        update: { name: 'Update', description: 'Update OAuth pipeline stages' },
        delete: { name: 'Delete', description: 'Delete OAuth pipeline stages' }
      }
    },

    oauth_pipelines: {
      name: 'OAuth Pipelines',
      description: 'OAuth-based pipeline management',
      actions: {
        read: { name: 'View', description: 'View OAuth pipelines' },
        create: { name: 'Create', description: 'Create OAuth pipelines' },
        update: { name: 'Update', description: 'Update OAuth pipelines' },
        delete: { name: 'Delete', description: 'Delete OAuth pipelines' }
      }
    },

    # Agent Management
    agents: {
      name: 'Agents',
      description: 'Agent management and administration',
      actions: {
        read: { name: 'View', description: 'View agent information' },
        create: { name: 'Create', description: 'Create new agents' },
        update: { name: 'Update', description: 'Update agent information' },
        delete: { name: 'Delete', description: 'Delete agents' }
      }
    },

    agent_apikeys: {
      name: 'Agent API Keys',
      description: 'Agent API key management',
      actions: {
        read: { name: 'View', description: 'View agent API keys' },
        create: { name: 'Create', description: 'Create agent API keys' },
        update: { name: 'Update', description: 'Update agent API keys' },
        delete: { name: 'Delete', description: 'Delete agent API keys' }
      }
    },

    agent_folders: {
      name: 'Agent Folders',
      description: 'Agent folder management',
      actions: {
        read: { name: 'View', description: 'View agent folders' },
        create: { name: 'Create', description: 'Create agent folders' },
        update: { name: 'Update', description: 'Update agent folders' },
        delete: { name: 'Delete', description: 'Delete agent folders' }
      }
    },

    agent_shared_folders: {
      name: 'Agent Shared Folders',
      description: 'Shared agent folder management',
      actions: {
        read: { name: 'View', description: 'View shared agent folders' },
        create: { name: 'Create', description: 'Create shared agent folders' },
        update: { name: 'Update', description: 'Update shared agent folders' },
        delete: { name: 'Delete', description: 'Delete shared agent folders' }
      }
    },

    # Installation Configuration (Admin Panel)
    installation_configs: {
      name: 'Installation Configs',
      description: 'System-wide configuration managed via admin panel',
      actions: {
        manage: { name: 'Manage', description: 'View and update installation configurations' }
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

    # Team Management
    team_members: {
      name: 'Team Members',
      description: 'Team member management',
      actions: {
        read: { name: 'View', description: 'View team members' },
        create: { name: 'Create', description: 'Create team members' },
        update: { name: 'Update', description: 'Update team members' },
        delete: { name: 'Delete', description: 'Delete team members' }
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

    live_reports: {
      name: 'Live Reports',
      description: 'Real-time reports and analytics',
      actions: {
        read: { name: 'View', description: 'View live reports' },
        create: { name: 'Create', description: 'Create live reports' },
        update: { name: 'Update', description: 'Update live reports' },
        delete: { name: 'Delete', description: 'Delete live reports' }
      }
    },

    summary_reports: {
      name: 'Summary Reports',
      description: 'Summary reports and analytics',
      actions: {
        read: { name: 'View', description: 'View summary reports' },
        create: { name: 'Create', description: 'Create summary reports' },
        update: { name: 'Update', description: 'Update summary reports' },
        delete: { name: 'Delete', description: 'Delete summary reports' }
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

    reports: {
      name: 'Reports & Analytics',
      description: 'Performance reporting and analytics dashboard',
      actions: {
        read: { name: 'View', description: 'View reports and analytics data' },
        export: { name: 'Export', description: 'Export report data' },
        create_custom: { name: 'Create Custom', description: 'Create custom reports' }
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

    installation_configs: {
      name: 'Installation Configs',
      description: 'System-level installation configuration management',
      actions: {
        manage: { name: 'Manage', description: 'Manage installation configuration settings' }
      }
    },

    }.freeze

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

    # Get formatted data for API responses
    def api_format
      {
        resources: RESOURCES.transform_values do |resource_config|
          {
            name: resource_config[:name],
            description: resource_config[:description],
            actions: resource_config[:actions].transform_values do |action_config|
              {
                name: action_config[:name],
                description: action_config[:description]
              }
            end
          }
        end,
        all_permissions: all_permission_keys.map do |permission_key|
          resource_key, action_key = permission_key.split('.')
          {
            key: permission_key,
            display_name: permission_display_name(permission_key),
            resource: resource_key,
            action: action_key,
            resource_name: resource(resource_key)[:name],
            action_name: action(resource_key, action_key)[:name],
            description: action(resource_key, action_key)[:description]
          }
        end
      }
    end

  end
end