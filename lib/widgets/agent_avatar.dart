import 'dart:io';

import 'package:flutter/material.dart';

import '../services/app_preferences.dart';
import '../theme.dart';

/// The agent's avatar: the custom gallery image when one is set and the
/// file still exists, otherwise the default glyph avatar.
///
/// The file read is guarded — a missing or unreadable file falls back to
/// the default instead of crashing.
class AgentAvatar extends StatelessWidget {
  final double size;

  const AgentAvatar({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: AppPreferences.instance.agentAvatarPath,
      builder: (_, path, __) {
        ImageProvider? image;
        if (path != null && path.isNotEmpty) {
          try {
            final file = File(path);
            if (file.existsSync()) image = FileImage(file);
          } catch (_) {
            image = null;
          }
        }
        return CircleAvatar(
          radius: size / 2,
          backgroundColor: P.tonal,
          backgroundImage: image,
          child: image == null
              ? Icon(Icons.auto_awesome_rounded,
                  size: size * 0.52, color: P.accent)
              : null,
        );
      },
    );
  }
}
