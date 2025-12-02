// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';

/// Web-specific image picker using HTML file input
class WebImagePicker {
  static html.File? _lastPickedFile;
  
  /// Get the last picked HTML File (for direct blob upload)
  static html.File? get lastPickedFile => _lastPickedFile;
  
  /// Create a Blob from Uint8List for Firebase upload
  static html.Blob createBlob(Uint8List bytes, String mimeType) {
    return html.Blob([bytes], mimeType);
  }
  
  /// Upload file directly using XMLHttpRequest (bypasses FlutterFire SDK issues)
  static Future<String?> uploadToFirebaseStorage({
    required Uint8List bytes,
    required String storageBucket,
    required String path,
    String contentType = 'image/jpeg',
  }) async {
    try {
      // Get the current user's ID token for authentication
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('WebImagePicker.upload: No authenticated user');
        return null;
      }
      
      final idToken = await user.getIdToken();
      if (idToken == null) {
        print('WebImagePicker.upload: Could not get ID token');
        return null;
      }
      
      // Encode the path for URL
      final encodedPath = Uri.encodeComponent(path);
      
      // Firebase Storage REST API URL
      final uploadUrl = 'https://firebasestorage.googleapis.com/v0/b/$storageBucket/o?uploadType=media&name=$encodedPath';
      
      print('WebImagePicker.upload: Uploading to $uploadUrl');
      
      final completer = Completer<String?>();
      
      final xhr = html.HttpRequest();
      xhr.open('POST', uploadUrl);
      xhr.setRequestHeader('Authorization', 'Firebase $idToken');
      xhr.setRequestHeader('Content-Type', contentType);
      
      xhr.onLoad.listen((event) async {
        if (xhr.status == 200) {
          print('WebImagePicker.upload: Success! Status ${xhr.status}');
          try {
            final response = xhr.responseText;
            print('WebImagePicker.upload: Response = $response');
            
            // Parse the response to get the download token
            final Map<String, dynamic> jsonResponse = Map<String, dynamic>.from(
              const JsonDecoder().convert(response ?? '{}') as Map
            );
            
            final downloadTokens = jsonResponse['downloadTokens'] as String?;
            
            String downloadUrl;
            if (downloadTokens != null && downloadTokens.isNotEmpty) {
              // Use the token from the response
              downloadUrl = 'https://firebasestorage.googleapis.com/v0/b/$storageBucket/o/$encodedPath?alt=media&token=$downloadTokens';
            } else {
              // Fallback without token (may require auth to access)
              downloadUrl = 'https://firebasestorage.googleapis.com/v0/b/$storageBucket/o/$encodedPath?alt=media';
            }
            
            print('WebImagePicker.upload: Download URL = $downloadUrl');
            completer.complete(downloadUrl);
          } catch (e) {
            print('WebImagePicker.upload: Error parsing response: $e');
            // Fallback URL
            final downloadUrl = 'https://firebasestorage.googleapis.com/v0/b/$storageBucket/o/$encodedPath?alt=media';
            completer.complete(downloadUrl);
          }
        } else {
          print('WebImagePicker.upload: Failed with status ${xhr.status}: ${xhr.responseText}');
          completer.complete(null);
        }
      });
      
      xhr.onError.listen((event) {
        print('WebImagePicker.upload: XHR error');
        completer.complete(null);
      });
      
      // Create blob and send
      final blob = html.Blob([bytes], contentType);
      xhr.send(blob);
      
      return completer.future;
    } catch (e) {
      print('WebImagePicker.upload: Error - $e');
      return null;
    }
  }
  
  /// Delete file from Firebase Storage using REST API
  static Future<bool> deleteFromFirebaseStorage({
    required String imageUrl,
  }) async {
    try {
      print('WebImagePicker.delete: Deleting $imageUrl');
      
      // Get the current user's ID token for authentication
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('WebImagePicker.delete: No authenticated user');
        return false;
      }
      
      final idToken = await user.getIdToken();
      if (idToken == null) {
        print('WebImagePicker.delete: Could not get ID token');
        return false;
      }
      
      // Parse the URL to extract bucket and encoded path
      // URL format: https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{encodedPath}?alt=media&token=...
      // We need to keep the path URL-encoded for the delete request
      
      // Extract bucket from the URL
      final bucketMatch = RegExp(r'/b/([^/]+)/o/').firstMatch(imageUrl);
      if (bucketMatch == null) {
        print('WebImagePicker.delete: Could not find bucket in URL');
        return false;
      }
      final bucket = bucketMatch.group(1);
      
      // Extract the encoded path - everything between /o/ and ? (or end of string)
      final pathStart = imageUrl.indexOf('/o/') + 3;
      final pathEnd = imageUrl.indexOf('?', pathStart);
      final encodedPath = pathEnd > 0 
          ? imageUrl.substring(pathStart, pathEnd)
          : imageUrl.substring(pathStart);
      
      if (encodedPath.isEmpty) {
        print('WebImagePicker.delete: Could not extract path from URL');
        return false;
      }
      
      // Firebase Storage REST API URL for delete - keep the path encoded
      final deleteUrl = 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/$encodedPath';
      
      print('WebImagePicker.delete: DELETE $deleteUrl');
      
      final completer = Completer<bool>();
      
      final xhr = html.HttpRequest();
      xhr.open('DELETE', deleteUrl);
      xhr.setRequestHeader('Authorization', 'Firebase $idToken');
      
      xhr.onLoad.listen((event) {
        if (xhr.status == 200 || xhr.status == 204) {
          print('WebImagePicker.delete: Success! Status ${xhr.status}');
          completer.complete(true);
        } else {
          print('WebImagePicker.delete: Failed with status ${xhr.status}: ${xhr.responseText}');
          completer.complete(false);
        }
      });
      
      xhr.onError.listen((event) {
        print('WebImagePicker.delete: XHR error');
        completer.complete(false);
      });
      
      xhr.send();
      
      return completer.future;
    } catch (e) {
      print('WebImagePicker.delete: Error - $e');
      return false;
    }
  }
  
  /// Pick image from file system
  static Future<Uint8List?> pickImage() async {
    return _pickImageInternal(useCamera: false);
  }
  
  /// Capture image from camera
  /// Uses getUserMedia API to access webcam on desktop, or capture attribute on mobile
  static Future<Uint8List?> captureFromCamera() async {
    // Try to use getUserMedia for webcam access (works on desktop)
    // This provides a live preview and capture experience
    try {
      final bytes = await _captureFromWebcam();
      if (bytes != null) {
        return bytes;
      }
    } catch (e) {
      print('WebImagePicker.captureFromCamera: getUserMedia failed, falling back to file input: $e');
    }
    
    // Fallback to file input with capture attribute (works on mobile)
    return _pickImageInternal(useCamera: true);
  }
  
  /// Capture from webcam using getUserMedia API
  static Future<Uint8List?> _captureFromWebcam() async {
    final completer = Completer<Uint8List?>();
    
    // Create video element for camera preview
    final video = html.VideoElement()
      ..autoplay = true
      ..setAttribute('playsinline', 'true');
    
    // Create canvas for capturing frame
    final canvas = html.CanvasElement();
    
    // Create overlay dialog for camera preview
    final overlay = html.DivElement()
      ..style.position = 'fixed'
      ..style.top = '0'
      ..style.left = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.backgroundColor = 'rgba(0, 0, 0, 0.9)'
      ..style.display = 'flex'
      ..style.flexDirection = 'column'
      ..style.alignItems = 'center'
      ..style.justifyContent = 'center'
      ..style.zIndex = '10000';
    
    // Style video
    video.style
      ..maxWidth = '90%'
      ..maxHeight = '70%'
      ..borderRadius = '8px';
    
    // Create button container
    final buttonContainer = html.DivElement()
      ..style.marginTop = '20px'
      ..style.display = 'flex'
      ..style.gap = '20px';
    
    // Create capture button
    final captureBtn = html.ButtonElement()
      ..text = '📷 Take Photo'
      ..style.padding = '15px 30px'
      ..style.fontSize = '18px'
      ..style.backgroundColor = '#4CAF50'
      ..style.color = 'white'
      ..style.border = 'none'
      ..style.borderRadius = '8px'
      ..style.cursor = 'pointer';
    
    // Create cancel button
    final cancelBtn = html.ButtonElement()
      ..text = '✕ Cancel'
      ..style.padding = '15px 30px'
      ..style.fontSize = '18px'
      ..style.backgroundColor = '#f44336'
      ..style.color = 'white'
      ..style.border = 'none'
      ..style.borderRadius = '8px'
      ..style.cursor = 'pointer';
    
    buttonContainer.children.addAll([captureBtn, cancelBtn]);
    overlay.children.addAll([video, buttonContainer]);
    
    html.MediaStream? stream;
    
    void cleanup() {
      // Stop all tracks
      stream?.getTracks().forEach((track) => track.stop());
      // Remove overlay
      overlay.remove();
    }
    
    // Cancel button handler
    cancelBtn.onClick.listen((_) {
      cleanup();
      completer.complete(null);
    });
    
    // Capture button handler
    captureBtn.onClick.listen((_) {
      try {
        // Set canvas size to video size
        canvas.width = video.videoWidth;
        canvas.height = video.videoHeight;
        
        // Draw video frame to canvas
        final ctx = canvas.context2D;
        ctx.drawImage(video, 0, 0);
        
        // Convert to blob and read as bytes
        canvas.toBlob('image/jpeg', 0.85).then((blob) {
          final reader = html.FileReader();
          reader.onLoadEnd.listen((_) {
            final result = reader.result;
            if (result is ByteBuffer) {
              completer.complete(result.asUint8List());
            } else {
              completer.complete(null);
            }
            cleanup();
          });
          reader.readAsArrayBuffer(blob);
        });
      } catch (e) {
        print('WebImagePicker: Error capturing frame: $e');
        cleanup();
        completer.complete(null);
      }
    });
    
    // Request camera access
    try {
      stream = await html.window.navigator.mediaDevices!.getUserMedia({
        'video': {
          'facingMode': 'environment', // Prefer back camera
          'width': {'ideal': 1920},
          'height': {'ideal': 1080},
        },
        'audio': false,
      });
      
      video.srcObject = stream;
      html.document.body!.append(overlay);
      
    } catch (e) {
      print('WebImagePicker: getUserMedia error: $e');
      cleanup();
      rethrow;
    }
    
    return completer.future;
  }
  
  /// Internal method to pick image from file system
  static Future<Uint8List?> _pickImageInternal({required bool useCamera}) async {
    final completer = Completer<Uint8List?>();
    _lastPickedFile = null;
    
    final input = html.FileUploadInputElement()
      ..accept = 'image/*';
    
    // Set capture attribute for camera access on mobile devices (fallback)
    // 'environment' = back camera, 'user' = front/selfie camera
    if (useCamera) {
      input.setAttribute('capture', 'environment');
    }
    
    input.onChange.listen((event) async {
      if (input.files != null && input.files!.isNotEmpty) {
        final file = input.files!.first;
        _lastPickedFile = file;  // Store for blob upload
        
        final reader = html.FileReader();
        
        reader.onLoadEnd.listen((event) {
          try {
            // readAsArrayBuffer returns a ByteBuffer, convert to Uint8List
            final result = reader.result;
            print('WebImagePicker: reader.result type = ${result.runtimeType}');
            if (result is ByteBuffer) {
              final bytes = result.asUint8List();
              print('WebImagePicker: Converted ByteBuffer to ${bytes.length} bytes');
              completer.complete(bytes);
            } else if (result is Uint8List) {
              print('WebImagePicker: Got Uint8List with ${result.length} bytes');
              completer.complete(result);
            } else {
              print('WebImagePicker: Unexpected result type: ${result.runtimeType}');
              completer.complete(null);
            }
          } catch (e) {
            print('WebImagePicker: Error processing file: $e');
            completer.complete(null);
          }
        });
        
        reader.onError.listen((event) {
          print('WebImagePicker: Error reading file: ${reader.error}');
          completer.complete(null);
        });
        
        reader.readAsArrayBuffer(file);
      } else {
        completer.complete(null);
      }
    });
    
    // Trigger the file picker
    input.click();
    
    return completer.future;
  }
}
