import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

Future<bool> requestBackgroundLocationPermission(BuildContext context) async {
  final perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.always) return true;

  final allow = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Background location required'),
      content: const Text(
        'This app may request background location access to reliably upload queued visits and poll job status when the app is not in the foreground. Please grant "Allow all the time" in app settings if needed.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Open settings'),
        ),
      ],
    ),
  );

  if (allow == true) {
    // Try to open app settings so the user can grant background location
    final opened = await Geolocator.openAppSettings();
    return opened;
  }
  return false;
}
