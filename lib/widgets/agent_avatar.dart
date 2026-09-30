import 'dart:io';

import 'package:flutter/material.dart';

import '../services/app_preferences.dart';
import '../theme.dart';

/// The agent's avatar: the custom gallery image when one is set and the
/// file still exists, otherwise the default glyph avatar.
///
/// The file check is async (no sync disk I/O on the UI thread) and cached
/// per path, so it runs once per avatar path instead of on every rebuild.
/// A missing or unreadable file falls back to the default instead of
/// crashing.
class AgentAvatar extends StatelessWidget {
  final double size;

  const AgentAvatar({super.key, this.size = 40});

  /// Existence-check futures keyed by path: one async disk read per path,
  /// reused across rebuilds.
  static final Map<String, Future<ImageProvider?>> _resolved = {};

  static Future<ImageProvider?> _imageFor(String path) =>
      _resolved.putIfAbsent(path, () async {
        try {
          final file = File(path);
          return await file.exists() ? FileImage(file) : null;
        } catch (_) {
          return null;
        }
      });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: AppPreferences.instance.agentAvatarPath,
      builder: (_, path, __) {
        final glyph = Icon(Icons.auto_awesome_rounded,
            size: size * 0.52, color: P.accent);
        if (path == null || path.isEmpty) {
          return CircleAvatar(
            radius: size / 2,
            backgroundColor: P.tonal,
            child: glyph,
          );
        }
        return FutureBuilder<ImageProvider?>(
          future: _imageFor(path),
          builder: (_, snap) {
            final image = snap.data;
            return CircleAvatar(
              radius: size / 2,
              backgroundColor: P.tonal,
              backgroundImage: image,
              child: image == null ? glyph : null,
            );
          },
        );
      },
    );
  }
}
