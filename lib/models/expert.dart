/// A standalone expert from `GET /api/experts`:
/// {"id","name","description","color","icon"}.
///
/// Persona text stays server-side; the app only needs the display fields.
/// `color` is a CSS hex string (e.g. "#7c5cff"); the UI parses it.
class Expert {
  final String id;
  final String name;
  final String description;
  final String color;
  final String? icon;

  Expert({
    required this.id,
    required this.name,
    required this.description,
    required this.color,
    this.icon,
  });

  factory Expert.fromJson(Map<String, dynamic> j) => Expert(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
        color: j['color']?.toString() ?? '',
        icon: j['icon'] as String?,
      );
}
