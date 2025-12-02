import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:uuid/uuid.dart';

// Conditional import for web
import 'web_image_picker_stub.dart' if (dart.library.html) 'web_image_picker.dart';

class ImageUploadService {
  static final _storage = FirebaseStorage.instance;
  static final _picker = ImagePicker();

  /// Pick an image from camera or gallery
  /// On web, uses file_picker for better compatibility
  static Future<XFile?> pickImage({required ImageSource source}) async {
    try {
      // On web, camera is not supported well, so use file picker for gallery
      if (kIsWeb && source == ImageSource.gallery) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
          withData: true,
        );
        if (result != null && result.files.isNotEmpty) {
          final file = result.files.first;
          if (file.bytes != null) {
            // Create an XFile-like wrapper for consistency
            return _WebXFile(file.name, file.bytes!);
          }
        }
        return null;
      }

      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      return image;
    } catch (e) {
      print('Error picking image: $e');
      return null;
    }
  }

  /// Pick image using file picker (works better on desktop/web)
  /// For web, uses native HTML file input for best compatibility
  static Future<Uint8List?> pickImageBytes() async {
    try {
      print('pickImageBytes: Starting...');
      
      // On web, use native HTML file input
      if (kIsWeb) {
        print('pickImageBytes: Using WebImagePicker for web...');
        final bytes = await WebImagePicker.pickImage();
        if (bytes != null) {
          print('pickImageBytes: Got ${bytes.length} bytes from web picker');
          return bytes;
        }
        print('pickImageBytes: No image selected from web picker');
        return null;
      }
      
      // On desktop/mobile, use file_picker
      print('pickImageBytes: Using file_picker...');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      print('pickImageBytes: Result = $result');
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        print('pickImageBytes: File name = ${file.name}, size = ${file.size}, bytes null = ${file.bytes == null}');
        if (file.bytes != null) {
          return file.bytes;
        }
        // If bytes are null, try reading from path (desktop)
        if (file.path != null) {
          print('pickImageBytes: Trying to read from path: ${file.path}');
          final fileData = await XFile(file.path!).readAsBytes();
          return fileData;
        }
      }
      print('pickImageBytes: Returning null');
      return null;
    } catch (e) {
      print('Error picking image: $e');
      return null;
    }
  }
  
  /// Capture image from camera
  /// On web, uses HTML5 capture attribute to access device camera
  /// On mobile, uses native camera through image_picker
  static Future<Uint8List?> captureImageFromCamera() async {
    try {
      print('captureImageFromCamera: Starting...');
      
      // On web, use HTML5 capture to access camera
      if (kIsWeb) {
        print('captureImageFromCamera: Using WebImagePicker.captureFromCamera for web...');
        final bytes = await WebImagePicker.captureFromCamera();
        if (bytes != null) {
          print('captureImageFromCamera: Got ${bytes.length} bytes from camera');
          return bytes;
        }
        print('captureImageFromCamera: No image captured');
        return null;
      }
      
      // On mobile/desktop, use image_picker with camera source
      print('captureImageFromCamera: Using image_picker...');
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      
      if (image != null) {
        final bytes = await image.readAsBytes();
        print('captureImageFromCamera: Got ${bytes.length} bytes');
        return bytes;
      }
      
      print('captureImageFromCamera: No image captured');
      return null;
    } catch (e) {
      print('Error capturing image from camera: $e');
      return null;
    }
  }

  /// Upload image to Firebase Storage
  /// Returns the download URL on success, null on failure
  static Future<String?> uploadImage({
    required Uint8List imageBytes,
    required String folder, // 'items' or 'library_items'
    required String itemId,
    String? fileName,
  }) async {
    try {
      print('uploadImage: Starting upload, bytes length = ${imageBytes.length}');
      final name = fileName ?? '${const Uuid().v4()}.jpg';
      final path = '$folder/$itemId/$name';
      print('uploadImage: Uploading to $path');
      
      // On web, use direct XMLHttpRequest upload to bypass FlutterFire SDK issues
      if (kIsWeb) {
        print('uploadImage: Using direct web upload...');
        final url = await WebImagePicker.uploadToFirebaseStorage(
          bytes: imageBytes,
          storageBucket: 'scout-litteempathy.firebasestorage.app',
          path: path,
          contentType: 'image/jpeg',
        );
        if (url != null) {
          print('uploadImage: Web upload success! URL = $url');
          return url;
        }
        print('uploadImage: Web upload failed, trying SDK fallback...');
      }
      
      // Fallback to SDK for non-web or if web upload fails
      final ref = _storage.ref().child(path);
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );

      print('uploadImage: Using SDK putData...');
      final uploadTask = ref.putData(imageBytes, metadata);
      
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        print('uploadImage: Progress - ${snapshot.bytesTransferred}/${snapshot.totalBytes} bytes');
      }, onError: (e) {
        print('uploadImage: Stream error - $e');
      });
      
      final snapshot = await uploadTask;
      print('uploadImage: Upload complete, state = ${snapshot.state}');
      
      if (snapshot.state == TaskState.success) {
        final downloadUrl = await ref.getDownloadURL();
        print('uploadImage: Success! URL = $downloadUrl');
        return downloadUrl;
      }
      print('uploadImage: Upload failed with state ${snapshot.state}');
      return null;
    } catch (e, stackTrace) {
      print('Error uploading image: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Delete an image from Firebase Storage
  static Future<bool> deleteImage(String imageUrl) async {
    try {
      // Use web-specific delete on web platform
      if (kIsWeb) {
        print('ImageUploadService.deleteImage: Using web delete for $imageUrl');
        return await WebImagePicker.deleteFromFirebaseStorage(imageUrl: imageUrl);
      }
      
      // Use Firebase SDK on native platforms
      final ref = _storage.refFromURL(imageUrl);
      await ref.delete();
      return true;
    } catch (e) {
      print('Error deleting image: $e');
      return false;
    }
  }

  /// Get all images for an item
  static Future<List<String>> getItemImages({
    required String folder,
    required String itemId,
  }) async {
    try {
      final ref = _storage.ref().child('$folder/$itemId');
      final result = await ref.listAll();
      
      final urls = <String>[];
      for (final item in result.items) {
        final url = await item.getDownloadURL();
        urls.add(url);
      }
      return urls;
    } catch (e) {
      print('Error getting images: $e');
      return [];
    }
  }
}

/// Wrapper class for web file data to work like XFile
class _WebXFile implements XFile {
  final String _name;
  final Uint8List _bytes;

  _WebXFile(this._name, this._bytes);

  @override
  String get name => _name;

  @override
  String get path => _name;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async {
    return encoding.decode(_bytes);
  }

  @override
  Stream<Uint8List> openRead([int? start, int? end]) {
    return Stream.value(_bytes.sublist(start ?? 0, end));
  }

  @override
  Future<int> length() async => _bytes.length;

  @override
  Future<DateTime> lastModified() async => DateTime.now();

  @override
  String? get mimeType => 'image/jpeg';

  @override
  Future<void> saveTo(String path) async {
    throw UnsupportedError('saveTo is not supported on web');
  }
}
