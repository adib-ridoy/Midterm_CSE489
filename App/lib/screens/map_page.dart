import 'package:flutter/material.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';

class MapPage extends StatefulWidget {
  final double? targetLat;
  final double? targetLon;

  const MapPage({super.key, this.targetLat, this.targetLon});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  @override
  void initState() {
    super.initState();
    final api = Provider.of<ApiService>(context, listen: false);
    api.getLandmarks().catchError((_) {});
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
    final markers = api.landmarks.map((l) {
      final img = l.image;
      // color marker based on score: low scores are red, higher scores move toward green
      final t = (l.score / 100.0).clamp(0.0, 1.0);
      final markerColor = Color.lerp(Colors.red, Colors.green, t)!;

      return Marker(
        width: 40,
        height: 40,
        point: LatLng(l.lat, l.lon),
        child: GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(l.title),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    img.startsWith('http')
                        ? CachedNetworkImage(
                            imageUrl: img,
                            height: 120,
                            fit: BoxFit.cover,
                            placeholder: (ctx, url) => const SizedBox(
                              height: 120,
                              child: Center(child: CircularProgressIndicator()),
                            ),
                            errorWidget: (ctx, url, err) => const SizedBox(
                              height: 120,
                              child: Icon(Icons.broken_image),
                            ),
                          )
                        : (img.isNotEmpty
                              ? (img.contains('uploads')
                                    ? CachedNetworkImage(
                                        imageUrl: api.imageUrl(img),
                                        height: 120,
                                        fit: BoxFit.cover,
                                        placeholder: (ctx, url) =>
                                            const SizedBox(
                                              height: 120,
                                              child: Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              ),
                                            ),
                                        errorWidget: (ctx, url, err) =>
                                            const SizedBox(
                                              height: 120,
                                              child: Icon(Icons.broken_image),
                                            ),
                                      )
                                    : Image.file(
                                        File(img),
                                        height: 120,
                                        fit: BoxFit.cover,
                                      ))
                              : const SizedBox.shrink()),
                    const SizedBox(height: 8),
                    Text('Score: ${l.score.toStringAsFixed(1)}'),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close'),
                  ),
                  api.pendingLandmarkIds.contains(l.id)
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'Pending (${api.pendingCounts[l.id] ?? 0})',
                          ),
                        )
                      : TextButton(
                          onPressed: () async {
                            Navigator.of(ctx).pop();
                            await _visitLandmarkById(ctx, l.id);
                          },
                          child: const Text('Visit'),
                        ),
                ],
              ),
            );
          },
          child: Icon(Icons.location_on, size: 32, color: markerColor),
        ),
      );
    }).toList();

    final center = (widget.targetLat != null && widget.targetLon != null)
        ? LatLng(widget.targetLat!, widget.targetLon!)
        : LatLng(24.0, 90.0);
    final zoom = (widget.targetLat != null && widget.targetLon != null)
        ? 13.0
        : 6.0;

    return Scaffold(
      appBar: AppBar(title: const Text('Map')),
      body: FlutterMap(
        options: MapOptions(initialCenter: center, initialZoom: zoom),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.midterm_project',
          ),
          MarkerLayer(markers: markers),
        ],
      ),
      floatingActionButton: Builder(
        builder: (ctx) {
          final api = Provider.of<ApiService>(context);
          final total = api.totalQueuedCount;
          return total > 0
              ? FloatingActionButton.extended(
                  onPressed: () {},
                  label: Text('Queued: $total'),
                  icon: const Icon(Icons.queue),
                )
              : const SizedBox.shrink();
        },
      ),
    );
  }
}
