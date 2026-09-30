/// One website login from `GET /api/logins`:
/// {"id","site","username","password":"••••"}.
///
/// Passwords are masked server-side and never returned; this model
/// deliberately has no password field so a secret can never be
/// stored or rendered client-side.
class LoginEntry {
  final String id;
  final String site;
  final String username;

  LoginEntry({
    required this.id,
    required this.site,
    required this.username,
  });

  factory LoginEntry.fromJson(Map<String, dynamic> j) => LoginEntry(
        id: j['id'] as String? ?? '',
        site: j['site'] as String? ?? '',
        username: j['username'] as String? ?? '',
      );
}
