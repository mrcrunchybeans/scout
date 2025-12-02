import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/image_upload_service.dart';

/// A widget for picking and displaying images
class ImagePickerWidget extends StatefulWidget {
  final List<String> imageUrls;
  final String folder;
  final String itemId;
  final Function(List<String>) onImagesChanged;
  final bool readOnly;

  const ImagePickerWidget({
    super.key,
    required this.imageUrls,
    required this.folder,
    required this.itemId,
    required this.onImagesChanged,
    this.readOnly = false,
  });

  @override
  State<ImagePickerWidget> createState() => _ImagePickerWidgetState();
}

class _ImagePickerWidgetState extends State<ImagePickerWidget> {
  bool _uploading = false;
  List<String> _urls = [];

  @override
  void initState() {
    super.initState();
    _urls = List.from(widget.imageUrls);
  }

  @override
  void didUpdateWidget(ImagePickerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrls != widget.imageUrls) {
      _urls = List.from(widget.imageUrls);
    }
  }

  Future<void> _showImageSourceDialog() async {
    if (kIsWeb) {
      // On web, show options dialog then immediately trigger the action
      // to preserve user gesture context for browser permissions
      final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo'),
                subtitle: const Text('Use camera to capture'),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                subtitle: const Text('Select existing image'),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      );
      
      if (choice == 'camera') {
        _captureFromCamera();
      } else if (choice == 'gallery') {
        _pickFromFilePicker();
      }
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );

    if (source != null) {
      await _pickAndUploadImage(source);
    }
  }

  /// Use file picker directly for web/desktop
  Future<void> _pickFromFilePicker() async {
    print('_pickFromFilePicker: Starting...');
    
    // IMPORTANT: On web, we must call the picker BEFORE any setState
    // because browsers require file inputs to be triggered directly from user gesture
    try {
      print('_pickFromFilePicker: Calling pickImageBytes...');
      final bytes = await ImageUploadService.pickImageBytes();
      print('_pickFromFilePicker: Got bytes = ${bytes != null ? "${bytes.length} bytes" : "null"}');
      
      if (bytes == null) {
        print('_pickFromFilePicker: No bytes, canceling');
        return;
      }

      await _uploadImageBytes(bytes);
    } catch (e) {
      print('_pickFromFilePicker: Error = $e');
      setState(() => _uploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
  
  /// Capture image from camera on web
  Future<void> _captureFromCamera() async {
    print('_captureFromCamera: Starting...');
    
    try {
      print('_captureFromCamera: Calling captureImageFromCamera...');
      final bytes = await ImageUploadService.captureImageFromCamera();
      print('_captureFromCamera: Got bytes = ${bytes != null ? "${bytes.length} bytes" : "null"}');
      
      if (bytes == null) {
        print('_captureFromCamera: No bytes, canceling');
        return;
      }

      await _uploadImageBytes(bytes);
    } catch (e) {
      print('_captureFromCamera: Error = $e');
      setState(() => _uploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
  
  /// Common method to upload image bytes
  Future<void> _uploadImageBytes(Uint8List bytes) async {
    // Now we can show uploading state
    if (mounted) {
      setState(() => _uploading = true);
    }

    print('_uploadImageBytes: Calling uploadImage...');
    final url = await ImageUploadService.uploadImage(
      imageBytes: bytes,
      folder: widget.folder,
      itemId: widget.itemId,
    );
    print('_uploadImageBytes: Upload result = $url');

    if (url != null && mounted) {
      setState(() {
        _urls.add(url);
        _uploading = false;
      });
      widget.onImagesChanged(_urls);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image uploaded successfully')),
      );
    } else {
      setState(() => _uploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload image')),
        );
      }
    }
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    setState(() => _uploading = true);

    try {
      final file = await ImageUploadService.pickImage(source: source);
      if (file == null) {
        setState(() => _uploading = false);
        return;
      }

      final bytes = await file.readAsBytes();
      final url = await ImageUploadService.uploadImage(
        imageBytes: bytes,
        folder: widget.folder,
        itemId: widget.itemId,
      );

      if (url != null && mounted) {
        setState(() {
          _urls.add(url);
          _uploading = false;
        });
        widget.onImagesChanged(_urls);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image uploaded successfully')),
        );
      } else {
        setState(() => _uploading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload image')),
          );
        }
      }
    } catch (e) {
      setState(() => _uploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _deleteImage(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Image'),
        content: const Text('Are you sure you want to delete this image?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final url = _urls[index];
      final success = await ImageUploadService.deleteImage(url);
      if (success && mounted) {
        setState(() {
          _urls.removeAt(index);
        });
        widget.onImagesChanged(_urls);
      }
    }
  }

  void _viewImage(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImageViewerPage(
          imageUrls: _urls,
          initialIndex: index,
          onDelete: widget.readOnly ? null : (i) async {
            await _deleteImage(i);
            if (mounted) Navigator.pop(context);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Images',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (!widget.readOnly)
              TextButton.icon(
                onPressed: _uploading ? null : _showImageSourceDialog,
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_a_photo),
                label: Text(_uploading ? 'Uploading...' : 'Add Image'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_urls.isEmpty)
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image_outlined, size: 40, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text(
                    'No images',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  if (!widget.readOnly) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: _uploading ? null : _showImageSourceDialog,
                      child: const Text('Add one'),
                    ),
                  ],
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _urls.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => _viewImage(index),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            _urls[index],
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                width: 120,
                                height: 120,
                                color: Colors.grey.shade200,
                                child: const Center(
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stack) {
                              return Container(
                                width: 120,
                                height: 120,
                                color: Colors.grey.shade200,
                                child: const Icon(Icons.broken_image),
                              );
                            },
                          ),
                        ),
                        if (!widget.readOnly)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => _deleteImage(index),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Full-screen image viewer with swipe navigation
class ImageViewerPage extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  final Function(int)? onDelete;

  const ImageViewerPage({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
    this.onDelete,
  });

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_currentIndex + 1} / ${widget.imageUrls.length}'),
        actions: [
          if (widget.onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => widget.onDelete!(_currentIndex),
            ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.imageUrls.length,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: Image.network(
                widget.imageUrls[index],
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                },
                errorBuilder: (context, error, stack) {
                  return const Center(
                    child: Icon(Icons.broken_image, size: 64, color: Colors.white54),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
