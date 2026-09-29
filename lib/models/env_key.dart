/// One key from `GET /api/env`:
/// {"key","redacted","used_by":[…],"shadowed_by_process_env":bool}.
/// Values are redacted server-side; the app never sees or shows secrets.
class EnvKey {
  final String key;
  final String redacted;
  final List<String> usedBy;
  final bool shadowedByProcessEnv;

  EnvKey({
    required this.key,
    required this.redacted,
    required this.usedBy,
    required this.shadowedByProcessEnv,
  });

  factory EnvKey.fromJson(Map<String, dynamic> j) => EnvKey(
        key: j['key'] as String? ?? '',
        redacted: j['redacted'] as String? ?? '••••',
        usedBy: (j['used_by'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        shadowedByProcessEnv:
            j['shadowed_by_process_env'] as bool? ?? false,
      );
}
