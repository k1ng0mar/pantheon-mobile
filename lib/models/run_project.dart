/// A run project: a named bucket of runs. `GET /api/projects` wraps the
/// list as `{"projects": [...]}`; [RunProject.fromJson] parses one item.
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
