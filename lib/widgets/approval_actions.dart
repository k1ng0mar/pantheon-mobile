import 'package:flutter/material.dart';

import '../theme.dart';
import 'buttons.dart';

/// Grant/deny action row for a pending approval.
///
/// Renders tier choices only where offered: `tiers` is the approval's
/// parsed `available_tiers` (`once`/`session`/`always`, backend order).
/// When `tiers` is empty (older backend) it falls back to the plain
/// Deny/Grant pair. Never renders a tier the backend did not offer.
///
/// Callbacks: [onDeny] denies; [onGrant] grants with the tier's mode
/// string, or `null` for the plain fallback grant (dashboard defaults
/// to a once grant).
class ApprovalActions extends StatelessWidget {
  const ApprovalActions({
    super.key,
    required this.tiers,
    required this.onDeny,
    required this.onGrant,
    this.denyFilled = true,
  });

  final List<String> tiers;
  final VoidCallback onDeny;
  final ValueChanged<String?> onGrant;
  final bool denyFilled;

  static String tierLabel(String tier) => switch (tier) {
        'once' => 'Allow once',
        'session' => 'Approve session',
        'always' => 'Always allow',
        _ => tier,
      };

  static String tierHint(String tier) => switch (tier) {
        'once' => 'Approve just this request.',
        'session' => 'Approve for this session only.',
        'always' => 'Never ask for this exact request again.',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final deny = PillButton(
      label: 'Deny',
      color: P.err,
      filled: denyFilled,
      onTap: onDeny,
    );
    if (tiers.isEmpty) {
      return Row(
        children: [
          deny,
          const SizedBox(width: 8),
          PillButton(
            label: 'Grant',
            color: P.ok,
            onTap: () => onGrant(null),
          ),
        ],
      );
    }
    // Tiered grants: Deny first, then exactly the offered tiers in
    // backend order. The one-shot stays the filled default; the wider
    // tiers are outlined so the row doesn't read as "grant everything".
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        deny,
        for (final tier in tiers)
          PillButton(
            label: tierLabel(tier),
            color: P.ok,
            filled: tier == 'once',
            onTap: () => onGrant(tier),
          ),
      ],
    );
  }
}
