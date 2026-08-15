import 'dart:convert';
import 'dart:io';
import 'package:workmanager/workmanager.dart';
import 'package:http/http.dart' as http;
import 'db_helper.dart';
import '../models/landmark.dart';

const String kSyncTask = 'syncQueuedTask';
const String baseUrl = 'https://labs.anontech.info/cse489/exm3/api.php';
const String apiKey = '24241348';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await processQueues();
      return Future.value(true);
    } catch (e) {
      return Future.value(false);
    }
  });
}

Future<void> processQueues() async {
  // 1. Process queued creates (landmarks with negative id)
  final queuedCreates = await DBHelper.getQueuedCreates();
  for (final temp in queuedCreates) {
    try {
      final uri = Uri.parse('$baseUrl?action=create_landmark&key=$apiKey');
      final request = http.MultipartRequest('POST', uri);
      request.fields['title'] = temp.title;
      request.fields['lat'] = temp.lat.toString();
      request.fields['lon'] = temp.lon.toString();
      if (temp.image.isNotEmpty && File(temp.image).existsSync()) {
        final f = await http.MultipartFile.fromPath('image', temp.image);
        request.files.add(f);
      }
      final streamed = await request.send();
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode == 200) {
        // refresh full landmark list and update DB
        await _refreshLandmarksFromServer();
      }
    } catch (e) {
      // skip, will retry later
    }
  }

  // 2. Drain queued visits: send visit_landmark to obtain job_id
  final queuedVisits = await DBHelper.getQueuedVisits();
  for (final q in queuedVisits) {
    try {
      final id = q['id'] as int;
      final landmarkId = q['landmark_id'] as int;
      final userLat = (q['user_lat'] as num).toDouble();
      final userLon = (q['user_lon'] as num).toDouble();

      // if already has job_id and pending, poll status
      final jobId = q['job_id'] as int?;
      if (jobId != null) {
        final status = await _pollJob(jobId);
        if (status != null && status['status'] == 'done') {
          final distance = (status['distance'] != null)
              ? double.tryParse(status['distance'].toString()) ?? 0.0
              : 0.0;
          await DBHelper.insertVisit(
            landmarkId,
            DateTime.now().toIso8601String(),
            distance,
          );
          await DBHelper.markQueuedVisitDone(id);
        }
        continue;
      }

      // otherwise create visit job
      final uri = Uri.parse('$baseUrl?action=visit_landmark&key=$apiKey');
      final body = json.encode({
        'landmark_id': landmarkId,
        'user_lat': userLat,
        'user_lon': userLon,
      });
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
      if (resp.statusCode == 200) {
        final decoded = json.decode(resp.body);
        if (decoded is Map && decoded['job_id'] != null) {
          final job = int.tryParse(decoded['job_id'].toString()) ?? 0;
          await DBHelper.updateQueuedVisitJob(id, job);
        }
      }
    } catch (e) {
      // ignore and retry later
    }
  }
}

Future<Map<String, dynamic>?> _pollJob(int jobId) async {
  try {
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
        return decoded;
      }
    }
  } catch (e) {
    // ignore
  }
  return null;
}

Future<void> _refreshLandmarksFromServer() async {
  try {
    final uri = Uri.parse('$baseUrl?action=get_landmarks&key=$apiKey');
    final resp = await http.get(uri);
    if (resp.statusCode == 200) {
      final decoded = json.decode(resp.body);
      List<Landmark> list = [];
      if (decoded is List) {
        list = decoded.map((e) => Landmark.fromJson(e)).toList();
      } else if (decoded is Map && decoded['landmarks'] is List) {
        list = (decoded['landmarks'] as List)
            .map((e) => Landmark.fromJson(e))
            .toList();
      }
      await DBHelper.upsertLandmarks(list);
    }
  } catch (e) {
    // ignore
  }
}
