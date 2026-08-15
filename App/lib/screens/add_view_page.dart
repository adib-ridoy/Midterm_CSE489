import 'package:flutter/material.dart';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';

class AddViewPage extends StatefulWidget {
  const AddViewPage({super.key});

  @override
  State<AddViewPage> createState() => _AddViewPageState();
}

class _AddViewPageState extends State<AddViewPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtl = TextEditingController();
  final _latCtl = TextEditingController();
  final _lonCtl = TextEditingController();
  XFile? _pickedImage;
  bool _isSubmitting = false;

  Future<bool> _ensureLocationPermission(BuildContext ctx) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return false;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Location services are disabled.')),
      );
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return false;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Location permission is required.')),
      );
      return false;
    }
    return true;
  }

  Future<void> _fetchLocation() async {
    if (!await _ensureLocationPermission(context)) return;
    try {
      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _latCtl.text = pos.latitude.toString();
        _lonCtl.text = pos.longitude.toString();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to get current GPS: $e')));
    }
  }

  Future<void> _pickImage() async {
    final p = ImagePicker();
    final file = await p.pickImage(source: ImageSource.camera);
    setState(() {
      _pickedImage = file;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add / View')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _titleCtl,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latCtl,
                      decoration: const InputDecoration(labelText: 'Latitude'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _lonCtl,
                      decoration: const InputDecoration(labelText: 'Longitude'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: _fetchLocation,
                    child: const Text('Use current GPS'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _pickImage,
                    child: const Text('Take photo'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _pickedImage != null
                  ? Image.file(File(_pickedImage!.path), height: 120)
                  : const SizedBox.shrink(),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _isSubmitting
                    ? null
                    : () async {
                        setState(() {
                          _isSubmitting = true;
                        });

                        final title = _titleCtl.text.trim();
                        final lat = double.tryParse(_latCtl.text.trim());
                        final lon = double.tryParse(_lonCtl.text.trim());

                        if (title.isEmpty) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a title.'),
                            ),
                          );
                          setState(() => _isSubmitting = false);
                          return;
                        }
                        if (lat == null || lon == null) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please fill valid latitude and longitude.',
                              ),
                            ),
                          );
                          setState(() => _isSubmitting = false);
                          return;
                        }
                        if (_pickedImage == null) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please take a photo first.'),
                            ),
                          );
                          setState(() => _isSubmitting = false);
                          return;
                        }

                        final api = Provider.of<ApiService>(
                          context,
                          listen: false,
                        );
                        final uiCtx = context;
                        try {
                          final ok = await api.createLandmark(
                            title: title,
                            lat: lat,
                            lon: lon,
                            imagePath: _pickedImage?.path,
                          );
                          if (!mounted) return;
                          if (!uiCtx.mounted) return;
                          if (ok) {
                            ScaffoldMessenger.of(uiCtx).showSnackBar(
                              const SnackBar(content: Text('Landmark created')),
                            );
                            _titleCtl.clear();
                            _latCtl.clear();
                            _lonCtl.clear();
                            setState(() {
                              _pickedImage = null;
                              _isSubmitting = false;
                            });
                          } else {
                            ScaffoldMessenger.of(uiCtx).showSnackBar(
                              const SnackBar(
                                content: Text('Failed to create landmark'),
                              ),
                            );
                            setState(() => _isSubmitting = false);
                          }
                        } catch (e) {
                          if (!mounted) return;
                          if (!uiCtx.mounted) return;
                          ScaffoldMessenger.of(
                            uiCtx,
                          ).showSnackBar(SnackBar(content: Text('Error: $e')));
                          setState(() => _isSubmitting = false);
                        }
                      },
                child: _isSubmitting
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          const Text('Submitting…'),
                        ],
                      )
                    : const Text('Create Landmark'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
