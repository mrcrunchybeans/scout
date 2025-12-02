import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/document_upload_service.dart';
import 'dart:ui_web' as ui_web;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// A widget for picking, displaying, and managing documents
class DocumentPickerWidget extends StatefulWidget {
  /// List of documents with name, url, and type
  final List<Map<String, String>> documents;
  
  /// Item ID for storage path
  final String itemId;
  
  /// Callback when documents change
  final Function(List<Map<String, String>>) onDocumentsChanged;
  
  /// Whether the widget is read-only
  final bool readOnly;

  const DocumentPickerWidget({
    super.key,
    required this.documents,
    required this.itemId,
    required this.onDocumentsChanged,
    this.readOnly = false,
  });

  @override
  State<DocumentPickerWidget> createState() => _DocumentPickerWidgetState();
}

class _DocumentPickerWidgetState extends State<DocumentPickerWidget> {
  bool _uploading = false;
  List<Map<String, String>> _docs = [];

  @override
  void initState() {
    super.initState();
    _docs = List.from(widget.documents);
  }

  @override
  void didUpdateWidget(DocumentPickerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documents != widget.documents) {
      _docs = List.from(widget.documents);
    }
  }

  Future<void> _pickDocument() async {
    try {
      final fileData = await DocumentUploadService.pickDocument();
      
      if (fileData == null) {
        return;
      }

      if (mounted) {
        setState(() => _uploading = true);
      }

      final url = await DocumentUploadService.uploadDocument(
        bytes: fileData['bytes'],
        itemId: widget.itemId,
        fileName: fileData['name'],
        contentType: fileData['contentType'],
      );

      if (url != null && mounted) {
        final newDoc = {
          'name': fileData['name'] as String,
          'url': url,
          'type': fileData['extension'] as String,
        };
        
        setState(() {
          _docs.add(newDoc);
          _uploading = false;
        });
        widget.onDocumentsChanged(_docs);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document uploaded successfully')),
        );
      } else {
        setState(() => _uploading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload document')),
          );
        }
      }
    } catch (e) {
      print('_pickDocument: Error = $e');
      setState(() => _uploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _deleteDocument(int index) async {
    final doc = _docs[index];
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Document'),
        content: Text('Delete "${doc['name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await DocumentUploadService.deleteDocument(doc['url']!);

    if (success && mounted) {
      setState(() {
        _docs.removeAt(index);
      });
      widget.onDocumentsChanged(_docs);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document deleted')),
      );
    } else if (mounted) {
      // Even if storage delete fails, remove from list (file might already be gone)
      setState(() {
        _docs.removeAt(index);
      });
      widget.onDocumentsChanged(_docs);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document removed')),
      );
    }
  }

  Future<void> _viewDocument(Map<String, String> doc) async {
    final url = doc['url'];
    final name = doc['name'] ?? 'Document';
    final type = doc['type']?.toLowerCase();
    
    if (url == null) return;

    // For PDFs, show in-app viewer
    if (type == 'pdf') {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PdfViewerPage(url: url, title: name),
        ),
      );
      return;
    }

    // For DOC/DOCX, open externally (can't render natively)
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open document')),
          );
        }
      }
    } catch (e) {
      print('Error opening document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  IconData _getDocumentIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getDocumentColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with add button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Documents (${_docs.length})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (!widget.readOnly)
              _uploading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: _pickDocument,
                      tooltip: 'Add Document (PDF, DOC, DOCX)',
                    ),
          ],
        ),
        const SizedBox(height: 8),
        
        // Document list
        if (_docs.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_open, color: Colors.grey[400]),
                const SizedBox(width: 8),
                Text(
                  'No documents attached',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _docs.length,
            itemBuilder: (context, index) {
              final doc = _docs[index];
              final name = doc['name'] ?? 'Unknown';
              final type = doc['type'];
              
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _getDocumentColor(type).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getDocumentIcon(type),
                      color: _getDocumentColor(type),
                    ),
                  ),
                  title: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    type?.toUpperCase() ?? 'Document',
                    style: TextStyle(
                      color: _getDocumentColor(type),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.open_in_new),
                        onPressed: () => _viewDocument(doc),
                        tooltip: 'Open Document',
                      ),
                      if (!widget.readOnly)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteDocument(index),
                          tooltip: 'Delete Document',
                          color: Colors.red,
                        ),
                    ],
                  ),
                  onTap: () => _viewDocument(doc),
                ),
              );
            },
          ),
        
        // Add button at bottom if no documents
        if (!widget.readOnly && _docs.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: _uploading ? null : _pickDocument,
              icon: _uploading 
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: const Text('Upload Document'),
            ),
          ),
      ],
    );
  }
}

/// In-app PDF viewer page using native browser PDF rendering
class PdfViewerPage extends StatefulWidget {
  final String url;
  final String title;

  const PdfViewerPage({super.key, required this.url, required this.title});

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  late String _viewType;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'pdf-viewer-${DateTime.now().millisecondsSinceEpoch}';
    _registerIframe();
    
    // Set a timeout to hide loading after a few seconds
    // (iframe onLoad may not fire for PDFs)
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  void _registerIframe() {
    // Use direct PDF URL - modern browsers render PDFs natively in iframes
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) {
        final iframe = html.IFrameElement()
          ..src = widget.url
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allowFullscreen = true;
        
        iframe.onLoad.listen((_) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        });
        
        iframe.onError.listen((_) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _hasError = true;
            });
          }
        });
        
        return iframe;
      },
    );
  }

  void _downloadPdf() {
    // Create an anchor element to trigger download
    html.AnchorElement(href: widget.url)
      ..setAttribute('download', widget.title)
      ..setAttribute('target', '_blank')
      ..click();
  }

  void _openInNewTab() {
    html.window.open(widget.url, '_blank');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Open in new tab',
            onPressed: _openInNewTab,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Download PDF',
            onPressed: _downloadPdf,
          ),
        ],
      ),
      body: Stack(
        children: [
          HtmlElementView(viewType: _viewType),
          if (_isLoading)
            Container(
              color: Colors.white,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading PDF...'),
                  ],
                ),
              ),
            ),
          if (_hasError)
            Container(
              color: Colors.white,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text('Could not load PDF in viewer'),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _openInNewTab,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open in new tab'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
