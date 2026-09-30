import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/link_preview.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import 'forms.dart';

/// Rich link preview card rendered under a chat message's text.
///
/// Fetches `GET /api/link-preview?url=` once per URL — results are held
/// in a static in-memory cache so rebuilds and repeated messages never
/// refetch within the session. While loading (or when the lookup fails
/// / returns nothing usable) this renders nothing, so the plain URL
/// text remains and layout never shifts for a spinner. On success the
/// card fades in: preview image, title, and domain/site name.
/// Tapping opens the URL externally.
class LinkPreviewCard extends StatefulWidget {
  final String url;
  final PantheonApi api;

  const LinkPreviewCard({super.key, required this.url, required this.api});

  /// In-memory per-session cache: URL -> in-flight or completed lookup.
  /// Failures and empty results are cached as null so a dead link does
  /// not get retried on every rebuild. Bounded to avoid unbounded growth
  /// in long sessions.
  static final Map<String, Future<LinkPreview?>> _cache = {};
  static const _maxCacheEntries = 100;

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  bool _visible = false;
  bool _imageOk = true;

  @override
  Widget build(BuildContext context) {
    var future = LinkPreviewCard._cache[widget.url];
    if (future == null) {
      if (LinkPreviewCard._cache.length >= LinkPreviewCard._maxCacheEntries) {
        LinkPreviewCard._cache
            .remove(LinkPreviewCard._cache.keys.first);
      }
      future = widget.api.fetchLinkPreview(widget.url);
      LinkPreviewCard._cache[widget.url] = future;
    }
    return FutureBuilder<LinkPreview?>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done ||
            snap.data == null) {
          return const SizedBox.shrink();
        }
        final preview = snap.data!;
        if (!_visible) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _visible = true);
          });
        }
        final host = _hostOf(widget.url);
        final domain = (preview.siteName?.isNotEmpty ?? false)
            ? preview.siteName!
            : host;
        return AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(P.r12),
              onTap: () => _open(widget.url),
              child: Container(
                decoration: BoxDecoration(
                  color: P.tonal,
                  borderRadius: BorderRadius.circular(P.r12),
                  border: Border.all(color: P.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (preview.image != null && _imageOk)
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.network(
                          preview.image!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) {
                            WidgetsBinding.instance
                                .addPostFrameCallback((_) {
                              if (mounted) {
                                setState(() => _imageOk = false);
                              }
                            });
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (preview.title != null)
                            Text(
                              preview.title!,
                              style: PT.body.copyWith(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: P.ink,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (preview.description != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              preview.description!,
                              style: PT.small.copyWith(color: P.inkSecondary),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (domain.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.link_rounded,
                                    size: 12, color: P.inkMuted),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    domain,
                                    style: PT.meta.copyWith(
                                        color: P.inkMuted, fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static String _hostOf(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return '';
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) toast(context, "Couldn't open link.");
  }
}
