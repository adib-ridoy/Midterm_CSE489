import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/landmark.dart';
import 'db_helper.dart';
import 'package:workmanager/workmanager.dart';
import 'background_worker.dart';

class ApiService extends ChangeNotifier {
  final String baseUrl = 'https://labs.anontech.info/cse489/exm3/api.php';
  String apiKey = '24241348'; // change if you have a different key

  List<Landmark> _landmarks = [];
  List<Landmark> get landmarks => _landmarks;

  // Simple in-memory visit jobs tracking
  final Map<int, String> _jobs = {};
  String? _lastVisitTime;
  Timer? _visitWatcher;
  // set of landmark IDs that currently have pending queued visits
  Set<int> _pendingLandmarkIds = {};
  Map<int, int> _pendingCounts = {};

  Future<void> getLandmarks() async {
    final uri = Uri.parse('$baseUrl?action=get_landmarks&key=$apiKey');
    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final decoded = json.decode(resp.body);
        final deletedIds = await DBHelper.getDeletedLandmarkIds();
        if (decoded is List) {
          var fetched = await Future.wait(
            decoded.map((e) async {
              final lm = Landmark.fromJson(e);
              final image = lm.image;
              if (image.isNotEmpty &&
                  (image.startsWith('http') || image.contains('uploads'))) {
                final local = await _persistImageIfRemote(image);
                if (local.isNotEmpty) {
                  return Landmark(
                    id: lm.id,
                    title: lm.title,
                    lat: lm.lat,
                    lon: lm.lon,
                    image: local,
                    score: lm.score,
                    visitCount: lm.visitCount,
                    avgDistance: lm.avgDistance,
                  );
                }
              }
              return lm;
            }),
          );
          fetched = fetched.where((l) => !deletedIds.contains(l.id)).toList();
          _landmarks = fetched;
        } else if (decoded is Map && decoded['landmarks'] is List) {
          var fetched = await Future.wait(
            (decoded['landmarks'] as List).map((e) async {
              final lm = Landmark.fromJson(e);
              final image = lm.image;
              if (image.isNotEmpty &&
                  (image.startsWith('http') || image.contains('uploads'))) {
                final local = await _persistImageIfRemote(image);
                if (local.isNotEmpty) {
                  return Landmark(
                    id: lm.id,
                    title: lm.title,
                    lat: lm.lat,
                    lon: lm.lon,
                    image: local,
                    score: lm.score,
                    visitCount: lm.visitCount,
                    avgDistance: lm.avgDistance,
                  );
                }
              }
              return lm;
            }),
          );
          fetched = fetched.where((l) => !deletedIds.contains(l.id)).toList();
          _landmarks = fetched;
        }
        // cache to local DB
        await DBHelper.upsertLandmarks(_landmarks);
        notifyListeners();
        return;
      }
      // fallthrough to use cache on non-200
    } catch (e) {
      // ignore network errors, fall back to cache
    }

    // fallback to cached landmarks
    final cached = await DBHelper.getCachedLandmarks();
    _landmarks = cached;
    notifyListeners();
  }

  Future<int> visitLandmark({
    required int landmarkId,
    required double userLat,
    required double userLon,
  }) async {
    final uri = Uri.parse('$baseUrl?action=visit_landmark&key=$apiKey');
    final body = json.encode({
      'landmark_id': landmarkId,
      'user_lat': userLat,
      'user_lon': userLon,
    });
    try {
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
      if (resp.statusCode == 200) {
        final decoded = json.decode(resp.body);
        if (decoded is Map && decoded['job_id'] != null) {
          final jobId = int.tryParse(decoded['job_id'].toString()) ?? 0;
          // Persist as queued visit so background worker will poll until done
          try {
            final queuedId = await DBHelper.enqueueVisit(
              landmarkId,
              userLat,
              userLon,
            );
            await DBHelper.updateQueuedVisitJob(queuedId, jobId);
            // schedule background sync so worker will pick this up if app is backgrounded
            try {
              await Workmanager().registerOneOffTask(
                'sync-now-${DateTime.now().millisecondsSinceEpoch}',
                kSyncTask,
              );
            } catch (_) {}
            // notify UI watchers
            notifyListeners();
          } catch (_) {
            // If DB persist fails, fallback to in-memory tracking
            _jobs[jobId] = 'pending';
            notifyListeners();
          }
          return jobId;
        } else {
          throw Exception('visit_landmark: unexpected response');
        }
      }
      throw Exception('visit_landmark failed: ${resp.statusCode}');
    } catch (e) {
      // enqueue for background sync
      await enqueueVisit(
        landmarkId: landmarkId,
        userLat: userLat,
        userLon: userLon,
      );
      throw Exception('Queued visit for background sync');
    }
  }

  Future<void> enqueueVisit({
    required int landmarkId,
    required double userLat,
    required double userLon,
  }) async {
    try {
      await DBHelper.enqueueVisit(landmarkId, userLat, userLon);
    } catch (_) {}
    // schedule a one-off background task to process queues
    try {
      await Workmanager().registerOneOffTask(
        'sync-now-${DateTime.now().millisecondsSinceEpoch}',
        kSyncTask,
      );
    } catch (_) {
      // ignore if register fails (e.g., not supported on platform)
    }
  }

  Future<Map<String, dynamic>> getJobStatus(int jobId) async {
    final uri = Uri.parse(
      '$baseUrl?action=get_job_status&key=$apiKey&job_id=$jobId',
    );
    final resp = await http.get(uri);
    if (resp.statusCode == 200) {
      final decodedRaw = json.decode(resp.body);
      if (decodedRaw is Map) {
        final decoded = Map<String, dynamic>.from(
          decodedRaw.map((k, v) => MapEntry(k.toString(), v)),
        );
        if (decoded['status'] != null) {
          _jobs[jobId] = decoded['status'].toString();
        }
        notifyListeners();
        return decoded;
      }
    }
    throw Exception('getJobStatus failed: ${resp.statusCode}');
  }

  Future<bool> createLandmark({
    required String title,
    required double lat,
    required double lon,
    String? imagePath,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty || lat.isNaN || lon.isNaN) {
      return false;
    }

    final uri = Uri.parse('$baseUrl?action=create_landmark&key=$apiKey');
    final request = http.MultipartRequest('POST', uri);
    request.fields['title'] = cleanTitle;
    request.fields['lat'] = lat.toString();
    request.fields['lon'] = lon.toString();

    if (imagePath != null && imagePath.isNotEmpty) {
      final file = File(imagePath);
      if (await file.exists()) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'image',
            imagePath,
            filename: file.uri.pathSegments.isNotEmpty
                ? file.uri.pathSegments.last
                : 'landmark.jpg',
          ),
        );
      }
    }

    try {
      final streamed = await request.send().timeout(
        const Duration(seconds: 20),
      );
      final resp = await http.Response.fromStream(streamed);
      final bodyText = resp.body.trim();
      final statusOk = resp.statusCode >= 200 && resp.statusCode < 300;

      bool looksSuccessful = statusOk;

      if (statusOk && bodyText.isNotEmpty) {
        final bodyLower = bodyText.toLowerCase();

        final explicitErrorMarkers = [
          'error',
          'failed',
          'invalid',
          'not allowed',
          'denied',
          'exception',
        ];
        final explicitSuccessMarkers = [
          'success',
          'created',
          'ok',
          'saved',
          'inserted',
          'landmark added',
          'landmark created',
          'done',
        ];

        final hasExplicitError = explicitErrorMarkers.any(
          (marker) => bodyLower.contains(marker),
        );
        final hasExplicitSuccess = explicitSuccessMarkers.any(
          (marker) => bodyLower.contains(marker),
        );

        if (hasExplicitError && !hasExplicitSuccess) {
          looksSuccessful = false;
        } else if (!hasExplicitError && !hasExplicitSuccess) {
          // Some backends return a successful payload without a success string,
          // such as an empty body, a raw JSON object with only an id, or a
          // minimal success object. Treat a 2xx response as success unless the
          // response is clearly an error payload.
          try {
            final decoded = json.decode(bodyText);
            if (decoded is Map) {
              final statusValue = decoded['status'];
              final messageValue = decoded['message'];
              final idValue = decoded['id'] ?? decoded['landmark_id'];

              final hasErrorStatus =
                  statusValue is String && statusValue.toLowerCase() == 'error';
              final hasErrorMessage =
                  messageValue is String &&
                  messageValue.toLowerCase().contains('error');
              final hasSuccessStatus =
                  statusValue is String &&
                  (statusValue.toLowerCase() == 'success' ||
                      statusValue.toLowerCase() == 'ok' ||
                      statusValue.toLowerCase() == 'created');

              if (hasErrorStatus || hasErrorMessage) {
                looksSuccessful = false;
              } else if (hasSuccessStatus || idValue != null) {
                looksSuccessful = true;
              }
            } else if (decoded is List) {
              looksSuccessful = true;
            }
          } catch (_) {
            looksSuccessful = true;
          }
        }
      }

      if (looksSuccessful) {
        await getLandmarks();
        return true;
      }
    } catch (_) {
      // fall through to local fallback below
    }

    // on failure, persist locally as a queued item (basic fallback)
    final tempId = DateTime.now().millisecondsSinceEpoch * -1;
    final temp = Landmark(
      id: tempId,
      title: cleanTitle,
      lat: lat,
      lon: lon,
      image: imagePath ?? '',
      score: 0.0,
      visitCount: 0,
    );
    await DBHelper.upsertLandmarks([temp]);
    _landmarks.add(temp);
    notifyListeners();
    return false;
  }

  Future<bool> deleteLandmark({required int landmarkId}) async {
    final uri = Uri.parse('$baseUrl?action=delete_landmark&key=$apiKey');
    final body = json.encode({'landmark_id': landmarkId});
    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (resp.statusCode == 200) {
      await DBHelper.softDeleteLandmark(landmarkId);
      await getLandmarks();
      return true;
    }

    // fallback: mark deleted locally
    await DBHelper.softDeleteLandmark(landmarkId);
    _landmarks.removeWhere((l) => l.id == landmarkId);
    notifyListeners();
    return false;
  }

  Future<bool> restoreLandmark({required int landmarkId}) async {
    final uri = Uri.parse('$baseUrl?action=restore_landmark&key=$apiKey');
    final body = json.encode({'landmark_id': landmarkId});
    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (resp.statusCode == 200) {
      await DBHelper.restoreLandmark(landmarkId);
      await getLandmarks();
      return true;
    }

    // fallback: restore locally
    await DBHelper.restoreLandmark(landmarkId);
    final cached = await DBHelper.getCachedLandmarks();
    _landmarks = cached;
    notifyListeners();
    return false;
  }

  void startVisitWatcher({
    Duration interval = const Duration(seconds: 10),
  }) async {
    try {
      _lastVisitTime = await DBHelper.getLatestVisitTime();
    } catch (_) {
      _lastVisitTime = null;
    }
    _visitWatcher?.cancel();
    _visitWatcher = Timer.periodic(interval, (t) async {
      try {
        // 1) detect new completed visits
        final latest = await DBHelper.getLatestVisitTime();
        if (latest != null && latest != _lastVisitTime) {
          _lastVisitTime = latest;
          notifyListeners();
        }
        // 2) check queued visits to update pending landmark ids
        final queued = await DBHelper.getQueuedVisits();
        final newPending = <int>{};
        final newCounts = <int, int>{};
        for (final q in queued) {
          final landmarkId = q['landmark_id'] as int?;
          final status = q['status'] as String? ?? '';
          if (landmarkId != null && status != 'done') {
            newPending.add(landmarkId);
            newCounts[landmarkId] = (newCounts[landmarkId] ?? 0) + 1;
          }
        }
        if (newPending.length != _pendingLandmarkIds.length ||
            !newPending.containsAll(_pendingLandmarkIds)) {
          _pendingLandmarkIds = newPending;
          _pendingCounts = newCounts;
          notifyListeners();
        }
      } catch (_) {}
    });
  }

  /// Public getter for last visit time observed by the watcher (ISO string)
  String? get lastVisitTime => _lastVisitTime;

  /// Landmark IDs that currently have pending queued visits (status != 'done')
  Set<int> get pendingLandmarkIds => _pendingLandmarkIds;

  /// Pending counts per landmark id
  Map<int, int> get pendingCounts => _pendingCounts;

  /// Total queued items
  int get totalQueuedCount => _pendingCounts.values.fold(0, (a, b) => a + b);

  /// Return a full URL for image paths returned by the server.
  /// The server sometimes returns relative paths like `uploads/..`.
  String imageUrl(String imagePath) {
    if (imagePath.isEmpty) return '';
    try {
      final uri = Uri.parse(imagePath);
      if (uri.hasScheme) return imagePath; // already absolute
    } catch (_) {}
    // derive base host by removing trailing '/api.php' from baseUrl
    final host = baseUrl.replaceFirst(RegExp(r'/api\.php\$?'), '/');
    return host + imagePath;
  }

  Future<String> _persistImageIfRemote(String imagePath) async {
    try {
      String url = imagePath;
      try {
        final u = Uri.parse(imagePath);
        if (!u.hasScheme) {
          url = imageUrl(imagePath);
        }
      } catch (_) {
        url = imageUrl(imagePath);
      }

      final uri = Uri.parse(url);
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return '';
      final bytes = resp.bodyBytes;
      final docDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(p.join(docDir.path, 'images'));
      if (!imagesDir.existsSync()) imagesDir.createSync(recursive: true);
      final base = p.basename(uri.path);
      final filePath = p.join(imagesDir.path, base);
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return '';
    }
  }

  @override
  void dispose() {
    _visitWatcher?.cancel();
    super.dispose();
  }
}
