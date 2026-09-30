import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Circular agent avatar.
///
/// `avatar` is `preset:avatar-N` (1–6) for the bundled set, an absolute
/// file path for a custom upload, or null — which falls back to the
/// gradient-initial circle. An unresolvable value (unknown preset, missing
/// file) also falls back instead of crashing.
class ProfilePicture extends StatelessWidget {
  final String? avatar;
  final String name;
  final double size;
  final bool active;

  const ProfilePicture({
    super.key,
    required this.avatar,
    required this.name,
    this.size = 48,
    this.active = false,
  });

  /// Bundled asset for `preset:avatar-N`; null for anything else.
  static String? presetAsset(String? avatar) {
    if (avatar == null || !avatar.startsWith('preset:')) return null;
    final preset = avatar.substring('preset:'.length);
    return RegExp(r'^avatar-[1-6]$').hasMatch(preset)
        ? 'assets/avatars/$preset.jpg'
        : null;
  }

  static final Map<String, Future<bool>> _existsCache = {};

  static Future<bool> _fileExists(String path) => _existsCache
      .putIfAbsent(path, () async => await File(path).exists());

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: P.gradient,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(
            fontFamily: PT.displayFamily,
            fontSize: size * 0.42,
            fontWeight: FontWeight.w600,
            color: Colors.white),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asset = presetAsset(avatar);
    Widget face;
    if (asset != null) {
      face = CircleAvatar(
          radius: size / 2, backgroundImage: AssetImage(asset));
    } else if (avatar != null && avatar!.startsWith('/')) {
      face = FutureBuilder<bool>(
        future: _fileExists(avatar!),
        builder: (_, snap) {
          if (snap.data == true) {
            return CircleAvatar(
                radius: size / 2,
                backgroundImage: FileImage(File(avatar!)));
          }
          return _fallback();
        },
      );
    } else {
      face = _fallback();
    }
    if (!active) return face;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        face,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: P.ok,
              shape: BoxShape.circle,
              border: Border.all(color: P.surface, width: 2),
            ),
            child: const Icon(Icons.check_rounded,
                size: 11, color: Colors.white, weight: 2.4),
          ),
        ),
      ],
    );
  }
}
