/// A run project: a named bucket of runs from `GET /api/projects`.
class RunProject {
  final String name;
  final List<String> runs;

  RunProject({required this.name, this.runs = const []});

  factory RunProject.fromJson(Map<String, dynamic> j) => RunProject(
        name: j['name'] as String? ?? '',
        runs: ((j['runs'] as List?) ?? const [])
            .whereType<String>()
            .toList(),
      );
}
