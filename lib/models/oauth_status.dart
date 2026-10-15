/// One OAuth provider's connection state (`GET /api/oauth/status` →
/// `providers[]`). Backend: `pantheon-secrets/src/oauth.rs` via the new
/// status endpoint. `expiresAt` is null when the provider issues no expiry
/// or no token is stored; `scopes` may be empty when the provider grants
/// capabilities at the integration level (Notion).
class OAuthProviderStatus {
  final String id;
  final bool connected;
  final List<String> scopes;
  final DateTime? expiresAt;

  OAuthProviderStatus({
    required this.id,
    required this.connected,
    required this.scopes,
    this.expiresAt,
  });

  factory OAuthProviderStatus.fromJson(Map<String, dynamic> j) {
    final rawScopes = j['scopes'];
    return OAuthProviderStatus(
      id: j['id'] as String? ?? 'unknown',
      connected: j['connected'] as bool? ?? false,
      scopes: rawScopes is List
          ? rawScopes.whereType<String>().toList()
          : const [],
      expiresAt: j['expires_at'] is String
          ? DateTime.tryParse(j['expires_at'] as String)
          : null,
    );
  }

  /// Display name for the provider id (`github` → `GitHub`).
  String get displayName {
    switch (id) {
      case 'github':
        return 'GitHub';
      case 'google':
        return 'Google';
      case 'notion':
        return 'Notion';
      case 'spotify':
        return 'Spotify';
      default:
        return id;
    }
  }

  /// True when a stored token has a known expiry in the past.
  bool get expired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);
}

/// OAuth connection status across providers (`GET /api/oauth/status`).
class OAuthStatus {
  final List<OAuthProviderStatus> providers;

  OAuthStatus({required this.providers});

  factory OAuthStatus.fromJson(Map<String, dynamic> j) {
    final raw = j['providers'];
    return OAuthStatus(
      providers: raw is List
          ? raw
              .whereType<Map<String, dynamic>>()
              .map(OAuthProviderStatus.fromJson)
              .toList()
          : const [],
    );
  }

  /// Providers in the canonical order (github, google, notion, spotify),
  /// unknown ids appended after.
  List<OAuthProviderStatus> get ordered {
    const order = ['github', 'google', 'notion', 'spotify'];
    final byId = {for (final p in providers) p.id: p};
    final out = <OAuthProviderStatus>[
      for (final id in order)
        if (byId.containsKey(id)) byId[id]!,
    ];
    out.addAll(providers.where((p) => !order.contains(p.id)));
    return out;
  }
}
