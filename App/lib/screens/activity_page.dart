import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/db_helper.dart';
import '../services/api_service.dart';
import 'map_page.dart';

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  List<Map<String, dynamic>> _visits = [];
  bool _loading = true;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _loadVisits();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_listening) {
      final api = Provider.of<ApiService>(context, listen: false);
      api.addListener(_onApiChanged);
      _listening = true;
    }
  }

  void _onApiChanged() {
    _loadVisits();
  }

  Future<void> _loadVisits() async {
    final oldCount = _visits.length;
    final rows = await DBHelper.getVisitHistory();
    setState(() {
      _visits = rows;
      _loading = false;
    });
    if (mounted && rows.isNotEmpty && rows.length > oldCount) {
      // show a quick notification about newest visit
      final newest = rows.first;
      final dist = newest['distance'] != null
          ? double.tryParse(newest['distance'].toString()) ?? 0.0
          : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dist != null
                ? 'Visit recorded — ${dist.toStringAsFixed(2)} m'
                : 'Visit recorded',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _visits.isEmpty
          ? const Center(child: Text('No visits yet'))
          : RefreshIndicator(
              onRefresh: _loadVisits,
              child: ListView.builder(
                itemCount: _visits.length,
                itemBuilder: (ctx, i) {
                  final v = _visits[i];
                  final title =
                      v['landmark_title'] ?? 'Landmark ${v['landmark_id']}';
                  final timeStr = v['visit_time'] ?? '';
                  String displayTime = timeStr;
                  try {
                    final dt = DateTime.parse(timeStr).toLocal();
                    displayTime =
                        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                  } catch (_) {}
                  final dist = v['distance'] != null
                      ? double.tryParse(v['distance'].toString()) ?? 0.0
                      : 0.0;
                  return ListTile(
                    leading: const Icon(Icons.place),
                    title: Text(title),
                    subtitle: Text(
                      '$displayTime — ${dist.toStringAsFixed(2)} m',
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        final itemCtx = ctx;
                        final landmarkId = v['landmark_id'] as int?;
                        if (landmarkId != null) {
                          final lm = await DBHelper.getLandmarkById(landmarkId);
                          if (lm != null) {
                            if (!mounted) return;
                            if (!itemCtx.mounted) return;
                            Navigator.of(itemCtx).push(
                              MaterialPageRoute(
                                builder: (_) => MapPage(
                                  targetLat: lm.lat,
                                  targetLon: lm.lon,
                                ),
                              ),
                            );
                            return;
                          }
                        }
                        if (!mounted) return;
                        if (!itemCtx.mounted) return;
                        Navigator.of(itemCtx).push(
                          MaterialPageRoute(builder: (_) => const MapPage()),
                        );
                      },
                      child: const Text('View on Map'),
                    ),
                  );
                },
              ),
            ),
    );
  }

  @override
  void dispose() {
    if (_listening) {
      final api = Provider.of<ApiService>(context, listen: false);
      api.removeListener(_onApiChanged);
    }
    super.dispose();
  }
}
