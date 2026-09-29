/// One MCP server from `GET /api/mcp/servers`:
/// {"name","transport","command","args","url","requires_env",
///  "needs_credentials","enabled","readiness","approved","health"}.
class McpServer {
  final String name;
  final String transport;
  final String? command;
  final List<String> args;
  final String? url;
  final List<String> requiresEnv;
  final bool needsCredentials;
  final bool enabled;
  final String readiness;
  final bool approved;
  final Map<String, dynamic>? health;

  McpServer({
    required this.name,
    required this.transport,
    this.command,
    required this.args,
    this.url,
    required this.requiresEnv,
    required this.needsCredentials,
    required this.enabled,
    required this.readiness,
    required this.approved,
    this.health,
  });

  factory McpServer.fromJson(Map<String, dynamic> j) => McpServer(
        name: j['name'] as String? ?? '',
        transport: j['transport'] as String? ?? 'stdio',
        command: j['command'] as String?,
        args: (j['args'] as List?)?.map((e) => e.toString()).toList() ?? [],
        url: j['url'] as String?,
        requiresEnv: (j['requires_env'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        needsCredentials: j['needs_credentials'] as bool? ?? false,
        enabled: j['enabled'] as bool? ?? true,
        readiness: j['readiness'] as String? ?? 'unknown',
        approved: j['approved'] as bool? ?? false,
        health: j['health'] is Map
            ? (j['health'] as Map).cast<String, dynamic>()
            : null,
      );

  String get describe {
    if (transport == 'stdio') {
      final a = args.isEmpty ? '' : ' ${args.join(' ')}';
      return '${command ?? '—'}$a';
    }
    return url ?? transport;
  }
}

/// One source group from `GET /api/mcp/servers`:
/// {"source","origin","servers":[…]}.
class McpServerGroup {
  final String source;
  final String origin;
  final List<McpServer> servers;

  McpServerGroup(
      {required this.source, required this.origin, required this.servers});

  factory McpServerGroup.fromJson(Map<String, dynamic> j) {
    final list = (j['servers'] as List?) ?? [];
    return McpServerGroup(
      source: j['source'] as String? ?? '',
      origin: j['origin'] as String? ?? '',
      servers: list
          .whereType<Map>()
          .map((e) => McpServer.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}
