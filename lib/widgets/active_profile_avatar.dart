import 'dart:async';

import 'package:flutter/material.dart';

import '../services/pantheon_api.dart';
import 'agent_avatar.dart';
import 'profile_picture.dart';

/// The chat agent avatar: the ACTIVE profile's picture, resolved from
/// `ConfigDoc.activeAgent` -> that profile's `avatar` field and rendered
/// with [ProfilePicture]. Falls back to the generic [AgentAvatar] while
/// resolving, when no profiles exist, or when the active profile has no
/// picture set.
///
/// Re-resolves on [PantheonApi.configChanged] — the same "reload after
/// PUT" mechanism the Profiles screen uses — so switching profiles there
/// updates an open chat header without a restart.
class ActiveProfileAvatar extends StatefulWidget {
  final PantheonApi api;
  final double size;

  const ActiveProfileAvatar({super.key, required this.api, this.size = 22});

  @override
  State<ActiveProfileAvatar> createState() => _ActiveProfileAvatarState();
}

class _ActiveProfileAvatarState extends State<ActiveProfileAvatar> {
  String? _name;
  String? _avatar;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = PantheonApi.configChanged.listen((_) => _resolve());
    _resolve();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _resolve() async {
    try {
      final doc = await widget.api.getConfig();
      final name = doc.activeAgent;
      final raw = name == null ? null : doc.agents[name]?['avatar'];
      if (!mounted) return;
      setState(() {
        _name = name;
        _avatar = raw is String && raw.isNotEmpty ? raw : null;
      });
    } catch (_) {
      // Keep whatever resolved last time; the generic fallback below
      // covers the case where nothing ever resolved.
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatar = _avatar;
    if (avatar == null) return AgentAvatar(size: widget.size);
    return ProfilePicture(
        avatar: avatar, name: _name ?? '?', size: widget.size);
  }
}
