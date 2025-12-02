import 'dart:typed_data';

/// Stub implementation for non-web platforms
class WebImagePicker {
  static dynamic get lastPickedFile => null;
  
  static dynamic createBlob(Uint8List bytes, String mimeType) {
    throw UnsupportedError('createBlob is only supported on web');
  }
  
  static Future<String?> uploadToFirebaseStorage({
    required Uint8List bytes,
    required String storageBucket,
    required String path,
    String contentType = 'image/jpeg',
  }) async {
    throw UnsupportedError('uploadToFirebaseStorage is only supported on web');
  }
  
  static Future<bool> deleteFromFirebaseStorage({
    required String imageUrl,
  }) async {
    throw UnsupportedError('deleteFromFirebaseStorage is only supported on web');
  }
  
  static Future<Uint8List?> pickImage() async {
    throw UnsupportedError('WebImagePicker is only supported on web');
  }
  
  static Future<Uint8List?> captureFromCamera() async {
    throw UnsupportedError('WebImagePicker is only supported on web');
  }
}
