import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:uuid/uuid.dart';

// Conditional import for web
import 'web_image_picker_stub.dart' if (dart.library.html) 'web_image_picker.dart';

/// Service for picking and uploading documents (PDF, DOC, DOCX)
class DocumentUploadService {
  /// Allowed document extensions
  static const allowedExtensions = ['pdf', 'doc', 'docx'];
  
  /// MIME types for documents
  static const mimeTypes = {
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  };

  /// Pick a document file
  /// Returns a map with 'name', 'bytes', and 'extension'
  static Future<Map<String, dynamic>?> pickDocument() async {
    try {
      print('DocumentUploadService.pickDocument: Starting...');
      
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        allowMultiple: false,
        withData: true,
      );
      
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        print('DocumentUploadService.pickDocument: Got file ${file.name}');
        
        Uint8List? bytes = file.bytes;
        
        // If bytes are null on desktop, try reading from path
        if (bytes == null && file.path != null) {
          print('DocumentUploadService.pickDocument: Reading from path ${file.path}');
          final fileData = await _readFileFromPath(file.path!);
          bytes = fileData;
        }
        
        if (bytes != null) {
          final extension = file.extension?.toLowerCase() ?? 'pdf';
          return {
            'name': file.name,
            'bytes': bytes,
            'extension': extension,
            'contentType': mimeTypes[extension] ?? 'application/octet-stream',
          };
        }
      }
      
      print('DocumentUploadService.pickDocument: No file selected');
      return null;
    } catch (e) {
      print('DocumentUploadService.pickDocument: Error - $e');
      return null;
    }
  }

  /// Upload document to Firebase Storage
  /// Returns the download URL on success, null on failure
  static Future<String?> uploadDocument({
    required Uint8List bytes,
    required String itemId,
    required String fileName,
    required String contentType,
  }) async {
    try {
      print('DocumentUploadService.uploadDocument: Starting upload of $fileName');
      
      // Generate unique filename
      final uuid = const Uuid().v4();
      final extension = fileName.split('.').last.toLowerCase();
      final storagePath = 'library_items/$itemId/documents/$uuid.$extension';
      
      // On web, use WebImagePicker's upload method (it works for any file type)
      if (kIsWeb) {
        print('DocumentUploadService.uploadDocument: Using web upload...');
        final url = await WebImagePicker.uploadToFirebaseStorage(
          bytes: bytes,
          storageBucket: 'scout-litteempathy.firebasestorage.app',
          path: storagePath,
          contentType: contentType,
        );
        
        if (url != null) {
          print('DocumentUploadService.uploadDocument: Success - $url');
          return url;
        }
      }
      
      // TODO: Add native platform upload using Firebase SDK if needed
      print('DocumentUploadService.uploadDocument: Upload failed or not on web');
      return null;
    } catch (e) {
      print('DocumentUploadService.uploadDocument: Error - $e');
      return null;
    }
  }

  /// Delete a document from Firebase Storage
  static Future<bool> deleteDocument(String documentUrl) async {
    try {
      print('DocumentUploadService.deleteDocument: Deleting $documentUrl');
      
      if (kIsWeb) {
        return await WebImagePicker.deleteFromFirebaseStorage(imageUrl: documentUrl);
      }
      
      // TODO: Add native platform delete using Firebase SDK if needed
      return false;
    } catch (e) {
      print('DocumentUploadService.deleteDocument: Error - $e');
      return false;
    }
  }

  /// Get icon for document type
  static String getDocumentIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return '📄';
      case 'doc':
      case 'docx':
        return '📝';
      default:
        return '📎';
    }
  }
  
  /// Read file from path (for desktop)
  static Future<Uint8List?> _readFileFromPath(String path) async {
    try {
      // Use dart:io on non-web platforms
      // This is a simplified version - in production you'd use proper file I/O
      return null;
    } catch (e) {
      print('Error reading file from path: $e');
      return null;
    }
  }
}
