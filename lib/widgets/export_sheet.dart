import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'buttons.dart';
import 'forms.dart';
import 'states.dart';

/// Show an exported markdown transcript with a Copy button.
/// (No share plugin is bundled, so clipboard is the share path.)
Future<void> showExportSheet(
    BuildContext context, String title, List<int> bytes) {
  final text = utf8.decode(bytes, allowMalformed: true);
  return showPSheet<void>(
    context,
    SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: 8),
            Text(title,
                style: PT.sectionTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('${bytes.length} bytes of markdown', style: PT.meta),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: P.tonal,
                  borderRadius: BorderRadius.circular(P.r12),
                  border: Border.all(color: P.border),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    text,
                    style: PT.mono.copyWith(fontSize: 11, height: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            GradientButton(
              label: 'Copy to clipboard',
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (context.mounted) {
                  Navigator.pop(context);
                  toast(context, 'Transcript copied.');
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
}
