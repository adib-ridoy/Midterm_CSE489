import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/landmark.dart';
import '../services/api_service.dart';
import '../services/db_helper.dart';

class LandmarksPage extends StatefulWidget {
  const LandmarksPage({super.key});

  @override
  State<LandmarksPage> createState() => _LandmarksPageState();
}

class _LandmarksPageState extends State<LandmarksPage> {
  double _minScore = 0.0;
  bool _sortDesc = true;

  Future<void> _confirmDeleteLandmark(
    BuildContext ctx,
    ApiService api,
    Landmark landmark,
  ) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Move To Trash'),
        content: Text('Move "${landmark.title}" (id=${landmark.id}) to trash?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Move'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    final ok = await api.deleteLandmark(landmarkId: landmark.id);
    if (!mounted) return;
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Moved to trash' : 'Moved to trash locally (server sync failed)',
        ),
      ),
    );
  }

  Future<void> _openRestoreDialog(BuildContext pageCtx, ApiService api) async {
    Future<List<Landmark>> deletedFuture = DBHelper.getDeletedLandmarks();

    await showDialog<void>(
      context: pageCtx,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('Trash'),
          content: SizedBox(
            width: double.maxFinite,
            child: FutureBuilder<List<Landmark>>(
              future: deletedFuture,
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 100,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final deleted = snapshot.data ?? const <Landmark>[];
                if (deleted.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Trash is empty.'),
                  );
                }
                return SizedBox(
                  width: double.maxFinite,
                  height: 320,
                  child: ListView.separated(
                    itemCount: deleted.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final l = deleted[i];
                      return ListTile(
                        dense: true,
                        title: Text(l.title),
                        subtitle: Text('id=${l.id}'),
                        trailing: TextButton(
                          onPressed: () async {
                            final ok = await api.restoreLandmark(
                              landmarkId: l.id,
                            );
                            if (!mounted) return;
                            if (!pageCtx.mounted) return;
                            ScaffoldMessenger.of(pageCtx).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok ? 'Restored' : 'Failed to restore',
                                ),
                              ),
                            );
                            if (!dialogCtx.mounted) return;
                            setDialogState(() {
                              deletedFuture = DBHelper.getDeletedLandmarks();
                            });
                          },
                          child: const Text('Restore'),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setDialogState(() {
                  deletedFuture = DBHelper.getDeletedLandmarks();
                });
              },
              child: const Text('Refresh'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final api = Provider.of<ApiService>(context, listen: false);
    api.getLandmarks().catchError((e) {});
  }

  Future<bool> _ensureLocationPermission(BuildContext ctx) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return false;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Location services are disabled.')),
      );
      return false;
    }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (!mounted) return false;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Location permission denied.')),
      );
      return false;
    }
    return true;
  }

  Future<void> _visitLandmarkById(BuildContext ctx, int landmarkId) async {
    final api = Provider.of<ApiService>(context, listen: false);
    if (!await _ensureLocationPermission(ctx)) return;
    try {
      final pos = await Geolocator.getCurrentPosition();
      try {
        final jobId = await api.visitLandmark(
          landmarkId: landmarkId,
          userLat: pos.latitude,
          userLon: pos.longitude,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Visit submitted (job_id: $jobId)')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Visit queued for background sync')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        ctx,
      ).showSnackBar(SnackBar(content: Text('Failed to get location: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = Provider.of<ApiService>(context);
    var list = api.landmarks.toList();
    if (_minScore > 0) {
      list = list.where((l) => l.score >= _minScore).toList();
    }
    list.sort(
      (a, b) =>
          _sortDesc ? b.score.compareTo(a.score) : a.score.compareTo(b.score),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Landmarks'),
        actions: [
          IconButton(
            icon: Icon(_sortDesc ? Icons.arrow_downward : Icons.arrow_upward),
            onPressed: () => setState(() => _sortDesc = !_sortDesc),
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Trash',
            onPressed: () async {
              await _openRestoreDialog(context, api);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Optional filter: minimum score',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Row(
                  children: [
                    Text(_minScore > 0 ? _minScore.toStringAsFixed(0) : 'Off'),
                    Expanded(
                      child: Slider(
                        value: _minScore,
                        min: 0,
                        max: 100,
                        divisions: 20,
                        label: _minScore > 0
                            ? _minScore.toStringAsFixed(0)
                            : 'Off',
                        onChanged: (v) => setState(() => _minScore = v),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (ctx, i) {
                final l = list[i];
                Widget leading;
                final api = Provider.of<ApiService>(context, listen: false);
                final imagePath = l.image;
                if (imagePath.startsWith('http')) {
                  leading = CachedNetworkImage(
                    imageUrl: imagePath,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    placeholder: (ctx, url) => const SizedBox(
                      width: 56,
                      height: 56,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (ctx, url, err) => const SizedBox(
                      width: 56,
                      height: 56,
                      child: Icon(Icons.broken_image),
                    ),
                  );
                } else if (imagePath.isNotEmpty &&
                    !imagePath.contains('uploads')) {
                  // treat as local file only if it looks like a local path
                  final f = File(imagePath);
                  if (f.existsSync()) {
                    leading = Image.file(
                      f,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    );
                  } else {
                    leading = const SizedBox(
                      width: 56,
                      height: 56,
                      child: Icon(Icons.broken_image),
                    );
                  }
                } else if (imagePath.isNotEmpty) {
                  // server-returned relative path (e.g. uploads/...) -> network
                  leading = CachedNetworkImage(
                    imageUrl: api.imageUrl(imagePath),
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    placeholder: (ctx, url) => const SizedBox(
                      width: 56,
                      height: 56,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (ctx, url, err) => const SizedBox(
                      width: 56,
                      height: 56,
                      child: Icon(Icons.broken_image),
                    ),
                  );
                } else {
                  leading = const SizedBox(
                    width: 56,
                    height: 56,
                    child: Icon(Icons.location_on),
                  );
                }

                final hasPending = api.pendingLandmarkIds.contains(l.id);
                final pendingCount = api.pendingCounts[l.id] ?? 0;
                return ListTile(
                  leading: leading,
                  title: Text(l.title),
                  subtitle: Text('Score: ${l.score.toStringAsFixed(1)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      hasPending
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('Pending ($pendingCount)'),
                            )
                          : TextButton(
                              onPressed: () async {
                                final itemCtx = ctx;
                                await _visitLandmarkById(itemCtx, l.id);
                              },
                              child: const Text('Visit'),
                            ),
                      IconButton(
                        tooltip: 'Delete landmark',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final itemCtx = ctx;
                          await _confirmDeleteLandmark(itemCtx, api, l);
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
